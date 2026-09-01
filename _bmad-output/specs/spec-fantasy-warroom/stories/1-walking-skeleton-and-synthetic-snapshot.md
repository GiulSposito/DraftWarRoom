---
title: 'Walking skeleton e snapshot sintético'
type: 'feature'
created: '2026-09-01'
status: 'done'
baseline_commit: '2e68cc8e69336573a5fb7b496ff90ccfd315b984'
review_loop_iteration: 0
context:
  - '/Users/gsposito/Projects/football/DraftWarRoom/_bmad-output/specs/spec-fantasy-warroom/SPEC.md'
  - '/Users/gsposito/Projects/football/DraftWarRoom/_bmad-output/specs/spec-fantasy-warroom/rds-contracts.md'
  - '/Users/gsposito/Projects/football/DraftWarRoom/_bmad-output/specs/spec-fantasy-warroom/operations.md'
  - '/Users/gsposito/Projects/football/DraftWarRoom/_bmad-output/specs/spec-fantasy-warroom/functional-core.md'
  - '/Users/gsposito/Projects/football/DraftWarRoom/_bmad-output/specs/spec-fantasy-warroom/preparation-pipeline.md'
  - '/Users/gsposito/Projects/football/DraftWarRoom/AGENTS.md'
---

<frozen-after-approval reason="human-owned intent — do not modify unless human renegotiates">

## Intent

**Problem:** Repositório greenfield. Não há esqueleto R executável, `config.R`, `Makefile`,
loader do core, nem fixture de projeção. Nada roda e as stories seguintes não têm base sobre
a qual construir.

**Approach:** Criar a estrutura mínima do repositório (`config.R`, `Makefile`, `R/` com um
loader do core), um builder de `data/projections.rds` sintético totalmente determinístico que
satisfaz `rds-contracts.md`, um validador do contrato de runtime da projeção, e
`tests/smoke.R` que reconstrói a fixture e valida o contrato — sem rede e sem `ffanalytics`.

## Boundaries & Constraints

**Always:**
- Apenas R base; persistência via `saveRDS`/`readRDS`.
- Fixture determinística: mesma entrada produz uma tabela `players` idêntica; nada de RNG
  não-semeado no caminho da fixture.
- `data/projections.rds` satisfaz o schema de `rds-contracts.md`: keys `schema_version` (=1L),
  `created_at` (POSIXct), `season` (int), `method` (="robust"), `scoring`, `vor_baseline`,
  `players`. A tabela `players` é normalizada, uma linha por `player_id`, sem duplicados.
- Campos obrigatórios validados com rejeição por `stop()`: `player_id`, `player`, `pos`,
  `points`; `pos` é um de `QB`, `RB`, `WR`, `TE`, `K`, `DST`.
- Regras de negócio em funções puras sob `R/`, nunca dependem de `shiny`. `config.R` e
  `tests/` apenas orquestram, sem fórmula própria.
- `Makefile` com exatamente os cinco alvos de `operations.md` — `prepare`, `test`,
  `simulate`, `draft`, `app` — todos via `Rscript`. `make test` -> `Rscript tests/smoke.R`.
- `make test` roda offline e reconstrói a fixture se ausente (`data/*.rds` é gitignored).
- `vor_baseline = c(QB = 13, RB = 35, WR = 36, TE = 13, K = 13, DST = 13)`; `method = "robust"`.

**Ask First:**
- Introduzir `renv`/`renv.lock` ou qualquer dependência fora do R base nesta story (o pin de
  `ffanalytics` pertence à story 2).
- Alterar qualquer contrato de `rds-contracts.md` ou os nomes dos alvos do `Makefile`.
- Adicionar um arquivo em `R/` fora de `load_core.R` e `projections.R`.

**Never:**
- `ffanalytics`, scraping, qualquer chamada de rede em qualquer arquivo desta story.
- Snake schedule, estado de draft, `state/draft.rds`, persistência de picks,
  `derive_draft_view`, `next_user_pick`, recomendação, simulação, loop de terminal, Shiny
  (stories 2–8).
- SQLite ou outro banco, event sourcing, R6, golem, targets, Docker, API, autenticação,
  background workers, injeção de dependência.
- Alvos de `Makefile` além dos cinco canônicos; scripts stub em `scripts/`.

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| Build da fixture | `build_synthetic_projections()` sem args | lista com todas as keys do contrato; `players` com >= 200 linhas cobrindo os 6 valores de `pos`; idêntica entre execuções | N/A |
| Grava snapshot | smoke escreve `data/projections.rds` (cria `data/` se preciso) | arquivo legível por `readRDS`; `load_projections()` devolve a lista | N/A |
| Validação OK | snapshot com obrigatórios presentes e `pos` válido | `validate_projections()` retorna `invisible(TRUE)` | N/A |
| `player_id` duplicado | `players` com `player_id` repetido | erro | `stop()` citando o id duplicado |
| Campo obrigatório ausente/NA | coluna `pos` ausente, ou `points` com NA | erro | `stop()` nomeando o campo |
| `pos` inválido | `pos = "OL"` | erro | `stop()` listando o valor inválido |
| smoke offline | `make test` sem rede | status 0, imprime n de jogadores e contagem por posição | qualquer asserção falha -> status != 0 |

</frozen-after-approval>

## Code Map

- Greenfield. Só existem `docs/`, `AGENTS.md`, `CLAUDE.md`, `.gitignore`, `_bmad-output/`.
  Nenhum código R.
- `.gitignore` já ignora `data/*.rds`, `state/*.rds`, `state/*.bak`, `renv/library/` — a
  fixture é sempre reconstruída em `make test`, nunca commitada.
- `R` e `Rscript` em `/usr/local/bin`; `R version 4.6.1`.
- Contrato de `data/projections.rds` e da tabela `players`:
  `_bmad-output/specs/spec-fantasy-warroom/rds-contracts.md:5-35`.
- Repo shape e comandos exatos: `_bmad-output/specs/spec-fantasy-warroom/operations.md:6-44`.
- Layout de `R/` e catálogo do core: `functional-core.md:31-37` — nesta story só o loader e o
  contrato de projeção; os quatro arquivos canônicos (`core.R`, `recommendation.R`,
  `simulation.R`, `persistence.R`) ficam para stories posteriores.
- Parâmetros da fixture (`vor_baseline`, `method`): `preparation-pipeline.md:32-41`.
- Roster inicial e formato da liga: `SPEC.md:80` e `rds-contracts.md:47-53`.

## Tasks & Acceptance

**Execution:**
- [x] `config.R` -- definir `league` (`teams = 12`, `rounds = 14`, `roster` vetor inteiro
  nomeado `QB=1, RB=2, WR=2, TE=1, FLEX=1, K=1, DST=1, BENCH=6`, `flex_positions = c("RB","WR")`),
  `scoring` (lista de regras Full-PPR: `rec = 1` mais overrides de passe/turnover/kicker/DST),
  `vor_baseline`, `season`, `method = "robust"`, `user_team` e `user_slot` como placeholders,
  caminhos de `data/` e `state/`. Sem lógica de negócio — só valores.
- [x] `R/load_core.R` -- `load_core(root = ".")` faz `source()` de todos os `R/*.R` exceto
  ele mesmo, em ordem alfabética estável.
- [x] `R/projections.R` -- `build_synthetic_projections(seed = 1L)` puro e determinístico que
  devolve a lista do contrato; `load_projections(path)` que lê e valida; `validate_projections(x)`
  que checa as keys da lista, os campos obrigatórios, o enum de `pos` e a unicidade de
  `player_id`, com `stop()` explicativo em cada falha.
- [x] `Makefile` -- alvos `prepare`, `test`, `simulate`, `draft`, `app` com os comandos
  exatos de `operations.md`; `.PHONY` em todos; `test` -> `Rscript tests/smoke.R`.
- [x] `tests/smoke.R` -- `source("R/load_core.R"); load_core()`; `build_synthetic_projections()`;
  grava `data/projections.rds`; `load_projections()`; `validate_projections()`; asserções
  positivas do contrato (keys, >= 200 linhas, 6 valores de `pos`, sem `player_id` duplicado,
  dois builds produzem `players` idênticas); asserções negativas (id duplicado, campo
  obrigatório ausente e `pos` inválido cada um dispara erro, via `tryCatch`); imprime resumo;
  `quit(status = 1)` em qualquer falha. Cobre cada linha da matriz I/O.
- [x] `data/.gitkeep`, `state/.gitkeep` -- estrutura mínima de diretórios (conteúdo `.rds`
  é gitignored).

**Acceptance Criteria:**
- Given um repositório limpo sem `data/projections.rds`, when rodo `make test`, then a fixture
  é reconstruída, o contrato é validado e o processo sai com status 0 sem qualquer acesso à rede.
- Given `make test` rodado duas vezes, when comparo a tabela `players` das duas fixtures, then
  elas são idênticas.
- Given a fixture sintética e um futuro snapshot real, when ambos passam por
  `validate_projections()`, then ambos são aceitos pelo mesmo schema.
- Given os alvos `make prepare|simulate|draft|app` nesta story, when executados, then podem
  falhar porque os scripts ainda não existem — apenas `make test` é funcional.
- Given `grep -RIn "ffanalytics" R/ tests/ config.R Makefile`, then não há resultado.

## Spec Change Log

## Design Notes

- Determinismo sem RNG: derivar `points`, `adp` e ranks por fórmula fechada sobre o índice
  dentro da posição (ex.: `base[pos] - decay * rank + amp * sin(rank)`), evitando `set.seed`
  no caminho da fixture. Se `sample()` for realmente necessário, salvar e restaurar
  `.Random.seed` e semear localmente com `seed`.
- Contagem por posição sugerida: QB 24, RB 60, WR 72, TE 24, K 24, DST 24 (~228 jogadores) —
  cobre 168 picks e o board com folga.
- `scoring` da fixture é o mesmo objeto de `config.R` (fonte única). A story 2 troca pela
  regra derivada de `ffanalytics` sem mudar o contrato do RDS.
- `R/load_core.R` e `R/projections.R` são adições mínimas à lista de `functional-core.md`
  porque a fixture sintética e o loader precisam de um lar e nenhum dos quatro arquivos
  canônicos pertence ao escopo desta story.
- `load_core()` existe para os adapters das próximas stories; aqui só `tests/smoke.R` o usa.

## Verification

**Commands:**
- `make test` -- expected: status 0, imprime contagem total e por posição, sem rede.
- `Rscript -e 'x <- readRDS("data/projections.rds"); stopifnot(x$schema_version == 1L, !anyDuplicated(x$players$player_id), all(x$players$pos %in% c("QB","RB","WR","TE","K","DST")), all(c("player_id","player","pos","points") %in% names(x$players)))'`
  -- expected: sem erro.
- `grep -RIn "ffanalytics\|scrape_data\|http" R/ config.R tests/ Makefile` -- expected: vazio.

## Suggested Review Order

**Contrato da projeção (o que a story estabelece)**

- Ponto de entrada: gerador da fixture sintética determinística, fórmula fechada sem RNG.
  [`projections.R:70`](../../../../R/projections.R#L70)
- O gate de schema compartilhado — a fixture e o snapshot real da story 2 passam pelo mesmo.
  [`projections.R:163`](../../../../R/projections.R#L163)
- `points` não-finito (`Inf`/`NaN`) rejeitado, além de NA e tipo.
  [`projections.R:205`](../../../../R/projections.R#L205)
- Ordenação por `points` com `method = "radix"` — determinismo independente de locale.
  [`projections.R:127`](../../../../R/projections.R#L127)
- Timestamp da fixture fixado como constante para reprodutibilidade.
  [`projections.R:19`](../../../../R/projections.R#L19)

**Carregamento de config**

- `config.R` lido de disco e rejeitado se faltar `scoring`/`vor_baseline`/`season`/`method` ou uma posição.
  [`projections.R:36`](../../../../R/projections.R#L36)
- Valores da liga, `scoring` Full-PPR e `vor_baseline` — fonte única, sem lógica.
  [`config.R:6`](../../../../config.R#L6)

**Loader do core**

- `load_core()` faz `source()` de `R/*.R`, resolve `R/` subindo diretórios e reempacota erro com o nome do arquivo.
  [`load_core.R:16`](../../../../R/load_core.R#L16)

**Periféricos**

- Smoke test: build, persist com `.bak`, reload, casos negativos cobrindo cada ramo do validador.
  [`smoke.R:28`](../../../../tests/smoke.R#L28)
- Bloco de asserções negativas (cada linha da matriz I/O + ramos extra do validador).
  [`smoke.R:71`](../../../../tests/smoke.R#L71)
- `Makefile`: os cinco alvos canônicos, `.DEFAULT_GOAL := test`.
  [`Makefile:1`](../../../../Makefile#L1)
