---
title: 'Adapter de projeção ffanalytics'
type: 'feature'
created: '2026-09-01'
status: 'done'
review_loop_iteration: 0
baseline_commit: 'dd5298b3c0beaaeadabc209468956c59e9bfb717'
context:
  - '/Users/gsposito/Projects/football/DraftWarRoom/_bmad-output/specs/spec-fantasy-warroom/SPEC.md'
  - '/Users/gsposito/Projects/football/DraftWarRoom/_bmad-output/specs/spec-fantasy-warroom/rds-contracts.md'
  - '/Users/gsposito/Projects/football/DraftWarRoom/_bmad-output/specs/spec-fantasy-warroom/preparation-pipeline.md'
  - '/Users/gsposito/Projects/football/DraftWarRoom/_bmad-output/specs/spec-fantasy-warroom/operations.md'
  - '/Users/gsposito/Projects/football/DraftWarRoom/AGENTS.md'
---

<frozen-after-approval reason="human-owned intent — do not modify unless human renegotiates">

## Intent

**Problem:** A story 1 estabeleceu o contrato de `data/projections.rds` com uma fixture
sintética. Ainda não existe o caminho real de preparação: nada transforma scrapes
multi-fonte do `ffanalytics` em um snapshot de projeção normalizado com scoring Full-PPR
da liga, e não há `renv` prendendo o `ffanalytics`.

**Approach:** Implementar `scripts/prepare.R` seguindo `preparation-pipeline.md` — único
arquivo que chama `ffanalytics`. A lógica de negócio pura (merge copy-and-override do
scoring; normalização da tabela do `ffanalytics` para o schema `players`) vive em funções
novas em `R/projections.R`, sem qualquer referência a `ffanalytics`. `prepare.R` grava
`data/raw_scrape.rds` e `data/projections.rds`, reaproveitando o raw salvo para reconstruir
sem re-scrapear. `renv` é inicializado com o `ffanalytics` preso ao commit instalado.

## Boundaries & Constraints

**Always:**
- `ffanalytics` (`scrape_data`, `projections_table`, `add_player_info`, `add_adp`, objeto de
  scoring padrão) é referenciado **apenas** em `scripts/prepare.R`. `R/` e `tests/` nunca o
  importam nem o mencionam.
- `scripts/prepare.R` é um adapter: orquestra `ffanalytics` + core, sem fórmula própria.
  Todo cálculo (scoring merge, mapeamento de campos, montagem do snapshot) fica em
  `R/projections.R`.
- O contrato de `data/projections.rds` (`rds-contracts.md:5-35`) não muda; o snapshot real
  passa pelo mesmo `validate_projections()` da fixture da story 1.
- Scoring por copy-and-override: partir das regras completas do `ffanalytics` e sobrepor
  só as diferenças da liga vindas de `config.R` (`rec = 1` mais passe/turnover/kicker/DST).
  Categorias não mencionadas (FG por distância, XP, sacks, TDs defensivos, brackets) são
  preservadas da base.
- Mapeamento de campos exatamente como a tabela de `preparation-pipeline.md`.
- `data/raw_scrape.rds` gravado antes de `projections_table()`; se já existir, `prepare.R` o
  reutiliza por padrão, re-scrape só com `--rescrape`.
- Parâmetros de `preparation-pipeline.md`: método `"robust"`, `vor_baseline` de `config.R`,
  posições `QB/RB/WR/TE/K/DST`. `add_ecr()`/`add_uncertainty()` fora de escopo.
- `renv.lock` prende `ffanalytics` ao commit efetivamente instalado (SHA de
  `packageDescription`); `renv.lock`/`renv/activate.R`/`.Rprofile` commitados,
  `renv/library/` não.
- `tests/smoke.R` continua offline e cobre o novo caminho de normalização com uma tabela
  sintética no formato de `projections_table()`.

**Ask First:**
- Assinaturas reais do `ffanalytics` instalado divergirem do assumido (nome do objeto de
  scoring, args de `scrape_data`/`projections_table`, forma da tabela) a ponto de exigir
  mudança de abordagem, não só ajuste de chamada.
- Precisar mudar `rds-contracts.md`, o schema de `validate_projections()`, ou o `Makefile`.
- Adicionar arquivo em `R/` além de estender `load_core.R` / `projections.R`.
- `add_adp()` indisponível para a temporada — snapshot sem `adp` ou abortar.

**Never:**
- Rede ou `ffanalytics` em `R/`, `tests/`, `config.R`, `app.R`, `scripts/draft.R`,
  `scripts/simulate.R`. Runtime nunca depende de scraping ao vivo.
- `make test` dependente de rede, do `ffanalytics`, ou de um snapshot real.
- Snake schedule, estado de draft, `derive_draft_view`, recomendação, simulação, loop de
  terminal, Shiny (stories 3–8).
- Endurecer `validate_projections()` além do contrato da story 1 (é deferred-work), mudar a
  fixture sintética, reconciliar com `docs/archive/`.

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| Scoring merge | `warroom_scoring(base, overrides)` com base completa do `ffanalytics` e overrides Full-PPR de `config.R` | lista com `rec = 1` e overrides aplicados; toda key da base ausente nos overrides preservada com o valor original | N/A |
| Override de key inexistente | `overrides` traz uma categoria fora da base | `stop()` nomeando a key desconhecida (evita erro de digitação silencioso) | `stop()` |
| Normalização feliz | `normalize_projections(proj_table, cfg)` com tabela válida do `projections_table()` | lista do contrato; `players` com uma linha por `player_id`, colunas mapeadas, `pos` em maiúsculas no enum; passa `validate_projections()` | N/A |
| `player_id` duplicado no scrape | tabela com `id` repetido | erro citando o(s) id(s) duplicado(s) | `stop()` |
| Coluna-fonte obrigatória ausente | tabela sem `points` (ou `id`, `position`) | `stop()` nomeando a coluna-fonte ausente | `stop()` |
| `pos` fora do enum | linha com `position = "OL"` ou similar | `stop()` listando o valor inválido (via `validate_projections()`) | `stop()` |
| ADP ausente | `proj_table` sem `adp`/`adp_sd` | snapshot gravado sem as colunas `adp`/`adp_sd`; aviso impresso; contrato ainda válido | warning |
| Rebuild a partir do raw | `data/raw_scrape.rds` existe, `prepare.R` sem `--rescrape` | pula `scrape_data()`, usa o raw salvo, regrava `projections.rds` | N/A |
| smoke offline | `make test` sem rede | status 0; caminho de normalização coberto com tabela sintética; sem tocar `ffanalytics` | asserção falha -> status 1 |

</frozen-after-approval>

## Code Map

- `scripts/prepare.R` -- **novo**. Único consumidor de `ffanalytics` e de `yaml`. Alvo
  `make prepare` (`operations.md:37`). Orquestra: carrega core + `config.R`, lê o YAML de
  overrides, `warroom_scoring(ffanalytics::scoring, overrides)`, scrape/rebuild, grava raw,
  `projections_table(avg_type = "robust")` + `add_player_info` + `add_adp`,
  `normalize_projections`, grava snapshot.
- `R/projections.R` -- estender. Já contém `build_synthetic_projections()`,
  `validate_projections()` (`projections.R:163`, o gate compartilhado — **não mudar**),
  `load_projections()`, `.warroom_load_config()` (`projections.R:36`),
  `.warroom_valid_pos` (`projections.R:10`), `.warroom_projection_keys` (`projections.R:12`),
  `.warroom_fixture_created_at` (`projections.R:19` — só fixture). Adicionar
  `warroom_scoring()` e `normalize_projections()` puras, sem `ffanalytics` nem `yaml`.
- `R/load_core.R` -- `load_core()` já faz `source()` de `R/*.R` em ordem alfabética;
  `prepare.R` o usa. Sem mudança.
- `config.R` -- fonte única de `vor_baseline`, `season`, `method`, `paths`. **Story 2**: a
  lista literal `scoring` de `config.R:21-32` está com chaves que **não existem** no
  `ffanalytics::scoring` real — trocar por um ponteiro para o arquivo de overrides:
  `paths$scoring <- file.path("config", "score_settings.yml")`. Remover a lista inline.
- `config/score_settings.yml` -- **fornecido pelo usuário**. Overrides de scoring da liga,
  já no formato de `ffanalytics::scoring` (seções `pass/rush/rec/misc/kick/ret/idp/dst` +
  `pts_bracket` como lista de `{threshold, points}`). Verificado: parseia limpo, zero
  chaves estranhas vs. a base. Diferenças-chave vs. default do `ffanalytics`: `pass_int`
  -2 (base -3), `rec$rec` 1 (base 0), `misc$fumbles_lost` -2 (base -3), `kick$fg_4049` 3
  (base 4). `all_pos: yes` vira `TRUE`.
- `tests/smoke.R` -- estender com bloco offline de normalização + `warroom_scoring`;
  helpers `fail()`, `expect_error()` já existem (`smoke.R:15`, `:21`).
- `preparation-pipeline.md` -- sequência de 9 passos e tabela de mapeamento de campos.
- `rds-contracts.md:5-35` -- contrato de `projections.rds` e da tabela `players`.
- `renv` -- já inicializado. `renv.lock` já criado com `ffanalytics` preso em
  `RemoteSha 42711a074d16caf723291eecd9d0daeb15340cf3` (v3.1.18.0000) e `yaml` 2.3.12.
  Rodar `renv::snapshot()` (tipo default/implicit) ao fim para reduzir o lock ao que
  `prepare.R` de fato usa. `.gitignore` já ignora `renv/library/`; commitar `renv.lock`,
  `renv/activate.R`, `renv/settings.json`, `.Rprofile`.

### API real do `ffanalytics` 3.1.18 (verificada nesta sessão)

- `scrape_data(src, pos = c("QB","RB","WR","TE","K","DST"), season, week)` — usar
  `week = 0` para projeção de temporada (obrigatório: `add_adp()` aborta com `week != 0`).
- `projections_table(data_result, scoring_rules, vor_baseline, avg_type = "robust")` —
  retorna **todas** as linhas empilhadas por `avg_type` se `avg_type` tiver mais de um
  valor; passar o escalar `"robust"` e ainda assim filtrar `avg_type == "robust"`. Colunas:
  `avg_type, id, pos, points, sd_pts, dropoff, floor, ceiling, points_vor, floor_vor,
  ceiling_vor, rank, floor_rank, ceiling_rank, pos_rank, tier`.
- `add_player_info(t)` — join por `id`, adiciona `first_name, last_name, team, position,
  age, exp`.
- `add_adp(t, sources = c("RTS","CBS","Yahoo","NFL","FFC","MFL"))` — adiciona `adp`,
  `adp_sd` (e `adp_diff`); faz scrape (rede). Sem essas colunas se falhar.
- Objeto de scoring padrão: `ffanalytics::scoring` (lista de 9: `pass, rush, rec, misc,
  kick, ret, idp, dst, pts_bracket`).

### Mapeamento `projections_table (+info +adp)` -> schema `players`

`player_id`<-`id` · `player`<-`paste(first_name, last_name)` · `nfl_team`<-`team` ·
`pos`<-`pos` · `points`<-`points` · `source_sd`<-`sd_pts` · `source_low`<-`floor` ·
`source_high`<-`ceiling` · `vor`<-`points_vor` · `low_vor`<-`floor_vor` ·
`high_vor`<-`ceiling_vor` · `overall_rank`<-`rank` · `pos_rank`<-`pos_rank` · `tier`<-`tier`
· `adp`<-`adp` · `adp_sd`<-`adp_sd`.

## Tasks & Acceptance

**Execution:**
- [x] `R/projections.R` -- adicionar `warroom_scoring(base, overrides)`: merge profundo
  copy-and-override de listas nomeadas; folha em `overrides` sobrepõe, folha só na `base`
  sobrevive; em listas sem nome (`pts_bracket`) `overrides` substitui a lista inteira;
  `stop()` nomeando a key se `overrides` trouxer key nomeada ausente na `base` (em qualquer
  nível). Adicionar `normalize_projections(proj_table, cfg, created_at = Sys.time())`: se
  houver coluna `avg_type`, manter só `avg_type == cfg$method`; validar colunas-fonte
  obrigatórias (`id`, `pos`, `points`) com `stop()` nomeando a ausente; mapear para o schema
  `players` (tabela no Code Map), `pos` em maiúsculas, `player <- trimws(paste(first_name,
  last_name))`, uma linha por `player_id`; `adp`/`adp_sd` opcionais (omitir com `warning()`
  se ausentes); montar a lista do contrato (`schema_version = 1L`, `created_at`, `season =
  cfg$season`, `method = cfg$method`, `scoring`, `vor_baseline = cfg$vor_baseline`,
  `players`) — `scoring` vem via argumento ou `cfg`; chamar `validate_projections()` e
  retornar. **Nenhuma menção a `ffanalytics` nem `yaml`.**
- [x] `config.R` -- remover a lista literal `scoring` (chaves inválidas para o
  `ffanalytics` real); adicionar `paths$scoring <- file.path("config", "score_settings.yml")`.
  Manter `vor_baseline`, `season`, `method`, demais `paths`. `.warroom_load_config()` em
  `R/projections.R` valida `scoring`/`vor_baseline`/`season`/`method` — ajustar para não
  exigir mais `scoring` em `config.R` (agora o scoring é resolvido em `prepare.R`); manter
  a exigência de `vor_baseline`/`season`/`method` e das 6 posições em `vor_baseline`.
- [x] `scripts/prepare.R` -- **novo**. `source("R/load_core.R"); load_core()`; `sys.source`
  de `config.R`; `overrides <- yaml::read_yaml(paths$scoring)`; `scoring <-
  warroom_scoring(ffanalytics::scoring, overrides)`; se `file.exists(paths$raw_scrape)` e
  sem `--rescrape` -> `raw <- readRDS(paths$raw_scrape)`, senão `raw <-
  ffanalytics::scrape_data(pos = c("QB","RB","WR","TE","K","DST"), season = season, week =
  0)` e `saveRDS(raw, paths$raw_scrape)`; `proj <- ffanalytics::projections_table(raw,
  scoring_rules = scoring, vor_baseline = vor_baseline, avg_type = "robust")`; `proj <-
  ffanalytics::add_player_info(proj)`; `proj <- tryCatch(ffanalytics::add_adp(proj),
  error = function(e) { warning("add_adp falhou: ", conditionMessage(e)); proj })`; `snap <-
  normalize_projections(proj, cfg = list(season = season, method = method, vor_baseline =
  vor_baseline), created_at = Sys.time())` com `scoring` incluído; `saveRDS(snap,
  paths$projections)`; imprimir resumo (n de jogadores, contagem por posição, SHA de
  `packageDescription("ffanalytics")$RemoteSha`). Se a API do `ffanalytics` divergir do
  descrito no Code Map a ponto de exigir outra abordagem, HALT (Ask First).
- [x] `tests/smoke.R` -- adicionar bloco **offline**: (a) `warroom_scoring()` — override
  aplicado (`rec$rec` 1), folha não mencionada preservada, `pts_bracket` substituída
  inteira, key desconhecida -> erro nomeando a key; (b) construir data frame no formato
  `projections_table (+info +adp)` (`avg_type`, `id`, `first_name`, `last_name`, `team`,
  `pos`, `points`, `sd_pts`, `floor`, `ceiling`, `points_vor`, `floor_vor`, `ceiling_vor`,
  `rank`, `pos_rank`, `tier`, `adp`, `adp_sd`), rodar `normalize_projections()`, assertar
  contrato + `validate_projections()`; casos negativos: `id` duplicado -> erro; sem `points`
  -> erro nomeando `points`; sem `adp`/`adp_sd` -> snapshot sem essas colunas + sucesso +
  warning; `avg_type` com linhas `"average"` extras -> filtradas. Sem rede, sem tocar
  `ffanalytics`.
- [x] `renv.lock` -- rodar `renv::snapshot(prompt = FALSE)` após `prepare.R` existir para
  reduzir o lock ao grafo real. Confirmar `ffanalytics` com `RemoteSha` fixo e `yaml`
  presentes. Commitar `renv.lock`, `renv/activate.R`, `renv/settings.json`, `.Rprofile`.

**Acceptance Criteria:**
- Given `grep -RIn "ffanalytics\|yaml::" R/ tests/ config.R app.R`, then não há resultado
  (o adapter é só `scripts/prepare.R`).
- Given `make test` sem rede, when executado, then status 0; fixture sintética +
  `warroom_scoring` + caminho de normalização validados; `ffanalytics` nunca carregado.
- Given a fixture sintética da story 1 e um snapshot de `normalize_projections()`, when
  ambos passam por `validate_projections()`, then ambos são aceitos pelo mesmo schema.
- Given `data/raw_scrape.rds` presente, when `make prepare` sem `--rescrape`, then
  `scrape_data()` não é chamado e `data/projections.rds` é regravado a partir do raw.
- Given `renv.lock`, when inspecionado, then `ffanalytics` fixa `RemoteSha`
  `42711a074d16caf723291eecd9d0daeb15340cf3` (não branch/latest).
- Given `make prepare` com rede no ambiente do usuário, then `data/raw_scrape.rds` e
  `data/projections.rds` são gravados e `load_projections()` aceita o snapshot.

## Spec Change Log

- **Refinamento dirigido pelo usuário (pré-implementação, não é loopback de review).**
  No step-03 a API real do `ffanalytics` 3.1.18 foi inspecionada e o usuário decidiu:
  (1) os overrides de scoring da liga ficam em `config/score_settings.yml` (fornecido), já
  no formato de `ffanalytics::scoring`; `warroom_scoring()` os funde sobre
  `ffanalytics::scoring` como base; adiciona-se o pacote `yaml`. (2) A lista `scoring`
  literal de `config.R` (story 1 — chaves inexistentes na API real: `pass_2pt`, `rec_2pt`,
  `dst_sack`, `dst_pa_*`) vira `paths$scoring`. Frozen block segue válido em intent
  (copy-and-override a partir do `ffanalytics`, diferenças da liga externas ao core); Code
  Map e Tasks carregam a mecânica exata. KEEP: `validate_projections()` da story 1
  intacto; `make test` offline.

## Design Notes

- `warroom_scoring(base, overrides)` — merge profundo de listas **nomeadas**: folha em
  `overrides` sobrepõe, folha só na `base` sobrevive. Lista **sem nomes** (`pts_bracket`):
  `overrides` substitui a lista inteira, sem recursão. Key nomeada em `overrides` ausente
  na `base`, em qualquer nível -> `stop()` nomeando a key. `yes`/`no` do YAML chegam como
  `logical` (ex.: `all_pos`); não converter.
  ```r
  base      <- list(rec = list(rec = 0, rec_yds = 0.1), kick = list(fg_50 = 5))
  overrides <- list(rec = list(rec = 1))
  warroom_scoring(base, overrides)   #> $rec$rec 1 ; $rec$rec_yds 0.1 ; $kick$fg_50 5
  ```
- `normalize_projections()` recebe a data frame já achatada (`projections_table` +
  `add_player_info` + `add_adp`). Colunas conhecidas no Code Map. Filtrar `avg_type`
  (`projections_table` pode empilhar tipos). Falhar com nome claro se `id`/`pos`/`points`
  faltarem.
- `created_at` do snapshot real é `Sys.time()` (POSIXct); o contrato só exige POSIXct.
- `scrape_data(..., week = 0)` é obrigatório: `add_adp()` aborta se `week != 0`.
- Canonicalização de `nfl_team` (`LA`/`LAR`, `WSH`/`WAS`, `JAC`/`JAX`) segue deferred-work;
  não bloquear esta story.
- O gate automático é `make test` (offline); `make prepare` com rede é verificação do
  ambiente do usuário.

## Verification

**Commands:**
- `make test` -- expected: status 0, sem rede; cobre `warroom_scoring` + normalização +
  fixture.
- `grep -RIn "ffanalytics\|yaml::" R/ tests/ config.R app.R` -- expected: vazio.
- `grep -RIn "ffanalytics" scripts/prepare.R` -- expected: não-vazio (único lugar).
- `Rscript -e 'source("R/load_core.R"); load_core(); s <- warroom_scoring(list(rec=list(rec=0),kick=list(xp=1)), list(rec=list(rec=1))); stopifnot(s$rec$rec==1, s$kick$xp==1)'`
  -- expected: sem erro.
- `grep -A2 '"ffanalytics"' renv.lock | grep 42711a07 && grep '"yaml"' renv.lock` --
  expected: casa as duas linhas.

**Manual checks:**
- `make prepare` com rede (ambiente do usuário): grava `data/raw_scrape.rds` e
  `data/projections.rds`; resumo mostra contagem plausível por posição e o SHA do
  `ffanalytics`. `Rscript -e 'source("R/load_core.R"); load_core(); load_projections()'`
  retorna sem erro.

## Suggested Review Order

**O adapter (ponto de entrada — a intenção do design)**

- Orquestração pura: core + config, YAML de overrides, scrape/rebuild, normalize, grava snapshot; único lugar com `ffanalytics`/`yaml`.
  [`prepare.R:60`](../../../../scripts/prepare.R#L60)
- `week = 0` obrigatório (senão `add_adp()` aborta); reuso do raw com guard de temporada.
  [`prepare.R:68`](../../../../scripts/prepare.R#L68)
- `avg_type = method` (de `config.R`), não literal — consistente com o filtro de `normalize_projections()`.
  [`prepare.R:89`](../../../../scripts/prepare.R#L89)
- `add_adp()` em `tryCatch`: ADP ausente vira warning, snapshot ainda válido.
  [`prepare.R:92`](../../../../scripts/prepare.R#L92)

**Scoring por copy-and-override (regra de negócio pura)**

- Merge profundo: shape de `base[[key]]` decide recursão vs. substituição; key desconhecida e override `NULL` são `stop()`.
  [`projections.R:293`](../../../../R/projections.R#L293)
- Overrides da liga em formato `ffanalytics::scoring`; diferenças: `pass_int` -2, `rec` 1, `fumbles_lost` -2, `fg_4049` 3.
  [`score_settings.yml:1`](../../../../config/score_settings.yml#L1)

**Normalização para o schema `players` (gate compartilhado)**

- Filtra `avg_type`, exige `id`/`pos`/`points`, mapeia campos, coage tipos, rejeita `player_id` duplicado, passa por `validate_projections()`.
  [`projections.R:406`](../../../../R/projections.R#L406)
- Coerção de tipo por coluna — paridade com a fixture sintética.
  [`projections.R:353`](../../../../R/projections.R#L353)
- `validate_projections()` **inalterado** — fixture e snapshot real passam pelo mesmo gate.
  [`projections.R:219`](../../../../R/projections.R#L219)

**config.R e a fixture sintética**

- Lista `scoring` inválida da story 1 removida; `paths$scoring` aponta para o YAML.
  [`config.R:32`](../../../../config.R#L32)
- `scoring` da fixture agora é placeholder mínimo — não replicar as regras reais da liga.
  [`projections.R:35`](../../../../R/projections.R#L35)
- `.warroom_load_config()` não exige mais `scoring` em `config.R`.
  [`projections.R:96`](../../../../R/projections.R#L96)

**Periféricos**

- Bloco offline do smoke: `warroom_scoring` (override, preservação, `pts_bracket`, `NULL`, shape, key desconhecida) + `normalize_projections` (feliz, `avg_type`, dup, colunas faltantes, ADP ausente, `pos` inválido, coerção, ordenação).
  [`smoke.R:169`](../../../../tests/smoke.R#L169)
- `renv.lock`: `ffanalytics` preso em `RemoteSha 42711a07…`, `yaml` 2.3.12.
  [`renv.lock:1`](../../../../renv.lock#L1)
