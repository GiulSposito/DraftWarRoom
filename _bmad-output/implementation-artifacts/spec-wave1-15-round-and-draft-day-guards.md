---
title: 'Onda 1 — liga em YAML (15 rounds) + guardas de dia de draft'
type: 'feature'
created: '2026-09-02'
status: 'done'
review_loop_iteration: 0
baseline_commit: '43b39af'
context:
  - '{project-root}/AGENTS.md'
  - '{project-root}/_bmad-output/specs/spec-fantasy-warroom/SPEC.md'
  - '{project-root}/_bmad-output/specs/spec-fantasy-warroom/rds-contracts.md'
  - '{project-root}/_bmad-output/specs/spec-fantasy-warroom/functional-core.md'
  - '{project-root}/_bmad-output/specs/spec-fantasy-warroom/RETROSPECTIVE.md'
---

<frozen-after-approval reason="human-owned intent — do not modify unless human renegotiates">

## Intent

**Problem:** A retrospectiva do épico (`RETROSPECTIVE.md`, itens 1/3/4/6) achou: (a) o
formato de liga era internamente inconsistente — 9 titulares + 6 de banco = 15
vagas de roster, mas o código roda 14 rounds / 168 picks, então o último round da
liga real fica de fora; (b) nada obriga que um draft retomado use o mesmo snapshot
a que foi atado; (c) `scripts/prepare.R` sobrescreve `data/projections.rds` sem
proteção, apesar de "imutável durante um draft"; (d) `recommend_players()` roda
fora da vez do usuário (via `/rec`) produzindo `p_next`/`adp_value` incoerentes. O
draft real é 2026-09-04.

**Approach:** Mover o formato de liga (times, roster, flex) para `config/league.yml`,
lido pelo core no caminho ao vivo; `rounds` deixa de ser um valor e passa a ser
derivado = soma de todas as vagas de roster (15), então banco e rounds nunca
discordam. Tudo que já lê `league$rounds` (`make_snake_schedule`,
`derive_draft_view`, `simulate_draft`, `calibrate_weights`, `recommend_players`)
passa a ver 15 automaticamente. Somar a isso três guardas pequenas: assert de
binding draft↔snapshot no resume do terminal e no startup do Shiny; `--force`
obrigatório para reescrever o snapshot; e uma checagem "usuário na vez" em
`recommend_players()`.

## Boundaries & Constraints

**Always:**
- `rounds` é sempre derivado como `sum(roster)` — nunca um campo de entrada,
  nunca hardcoded. `roster` inclui `BENCH`.
- `config/league.yml` é a única fonte do formato de liga no caminho ao vivo.
  `config.R` mantém `season`, `method`, `vor_baseline`, `user_team`, `user_slot`,
  `seed`, `paths` (+ `paths$league`) e perde o `league`.
- `new_draft(..., league = <lista>)` continua aceitando uma liga explícita (usado
  por testes/simulador); quando passada, `rounds` ainda é derivado de `roster`, um
  `rounds` na lista é ignorado.
- Determinismo intacto: mesmo snapshot + config + picks → mesma ordem. `method =
  "radix"` e tie-break em `player_id` preservados.
- Save atômico, "persistir fatos / derivar visões", e o contrato de
  `state/draft.rds` (agora `overall` 1..180) preservados.
- `yaml` só é lido em `scripts/prepare.R` (`score_settings.yml`) e no resolver de
  liga do core (`league.yml`) — em nenhum outro lugar. Atualizar o comentário de
  cabeçalho de `scripts/prepare.R` e a seção "Where things are" de `AGENTS.md`.

**Ask First:**
- Se qualquer mudança exigir tocar a assinatura pública de `record_pick`,
  `undo_pick`, `derive_draft_view` ou `recommend_players` além de um parâmetro
  opcional com default.
- Se `make simulate` passar a falhar por um motivo que não seja a contagem de
  rounds.

**Never:**
- Sem SQLite/DB, event sourcing, R6, golem, targets, Docker, API, auth, workers,
  DI. Sem chamada de rede no caminho ao vivo. Sem Monte Carlo no caminho de
  recomendação.
- Não mexer nos pesos de recomendação, nas fórmulas dos 4 componentes, nem nas
  guardas de K/DST/QB2/TE2 — isso é onda posterior.
- Não fazer o passe de performance de `recommend_players()` (item 5 da retro) nem
  o de consolidação de duplicação (item 2) nesta onda.
- Não alterar `config/score_settings.yml` nem o pipeline de scoring.

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| Resolver de liga | `config/league.yml` válido | lista `league` com `teams=12`, `roster` nomeado (com `BENCH`), `flex_positions`, `rounds=15` derivado | — |
| league.yml ausente | arquivo não existe | `stop()` claro nomeando o caminho esperado | mensagem aponta `config/league.yml` |
| league.yml malformado | sem `roster`, ou `roster` sem nomes, ou valor não-inteiro | `stop()` nomeando o defeito | — |
| Schedule 12×15 | `make_snake_schedule(12, 15)` | 180 linhas; `overall` 1..180; slot[13]=12, slot[24]=1 (reversões inalteradas) | — |
| Draft cheio | 180 picks registrados | `record_pick` do 181º → erro citando 180 | `stop()` "draft is full ... 180" |
| Resume com snapshot casado | `state$projection_created_at == snapshot$created_at` | draft retoma normalmente | — |
| Resume com snapshot trocado | timestamps diferem | `stop()` antes de entrar no loop / render, explicando o descasamento | terminal e Shiny |
| prepare sem `--force`, snapshot existe | `data/projections.rds` presente | recusa, instrui a passar `--force` | `stop()` |
| prepare com `--force` ou snapshot ausente | — | grava normalmente (com `.bak` do anterior quando existe) | — |
| `/rec` fora da vez | `derive_draft_view()$team_on_clock != state$user_team` | recomendação ainda retorna, mas com aviso/anotação explícita "assumindo seu próximo pick" | sem crash |

</frozen-after-approval>

## Code Map

- `config/league.yml` — **novo**. `teams: 12`; `roster:` mapa `QB/RB/WR/TE/FLEX/K/DST/BENCH`; `flex_positions: [RB, WR]`. Sem `rounds`.
- `R/core.R` — `.warroom_resolve_league()` (linhas ~71-110): hoje lê `cfg$league` de `config.R`; passa a ler `config/league.yml` via `yaml::read_yaml`, validar shape, e setar `rounds = sum(roster)`. Adicionar um resolver público `load_league(path = NULL)` que os adapters chamam. `make_snake_schedule` (~50-67), `derive_draft_view` (~260-309, usa `state$league$rounds`), `next_user_pick` (~318-329) — nenhuma mudança de lógica, só passam a ver 15.
- `R/recommendation.R` — `recommend_players()` (~453). Adicionar, logo após `view <- derive_draft_view(...)`, uma checagem `on_clock <- identical(view$team_on_clock, state$user_team)`; quando falso, anexar aviso ao resultado (coluna/atributo) sem abortar. `picks_remaining` (~472) já usa `league$rounds`.
- `R/simulation.R` — `.warroom_roster_is_valid` (~220-224, `n == league$rounds`), `simulate_draft` `total` (~325), `.warroom_eligible_sim_candidates` (~112-140) — todos parametrizados; verificar, não hardcodear.
- `R/persistence.R` — `.warroom_validate_state` (~50-85): valida `league$rounds` como inteiro positivo; adicionar assert `rounds == sum(roster)`.
- `config.R` — remover a lista `league` (linhas 6-11); adicionar `paths$league = file.path("config", "league.yml")`.
- `scripts/draft.R` — `run_draft()`: linhas ~159 (`cfg$league$teams`), ~174 (`league = cfg$league`) → usar `load_league()`. Após carregar `state` + `snapshot` no resume (~155-157), inserir o assert de binding.
- `app.R` — `server()`: linha ~111 (`league <- cfg$league`) → `load_league()`. Inserir o assert de binding no bloco `init_state` quando `file.exists(state_path)` (~106-115).
- `scripts/simulate.R` — linha ~24 (`cfg$league$teams`) → `load_league()`.
- `scripts/prepare.R` — cabeçalho: ajustar "the ONLY file ... that may call ffanalytics or yaml" (yaml agora também no core). Antes do `saveRDS(snap, paths$projections)` (~111): guarda `--force`.
- `tests/smoke.R` — ~40 pontos. Trocar `168`→`180`, `1:168`→`1:180`, `169`→`181`, `14L` (rounds) → `15L`, "14 players"→"15", `nrow(sched)==168`→`180`. `custom_league` (~444) e `cap_league$rounds<-20L` (~1331): redefinir via `roster` que soma ao alvo. Manter as asserções de reversão (slot[13]=12, slot[24]=1). Adicionar blocos novos: resolver de liga (feliz + 3 erros), assert de binding (terminal + Shiny), guarda `--force` do prepare, guarda "na vez" de `recommend_players`.
- `AGENTS.md` — "Where things are": citar `config/league.yml` como fonte do formato de liga, lido no caminho ao vivo; `yaml` agora em `prepare.R` **e** no resolver de liga do core.
- `renv.lock` — `yaml` 2.3.12 já presente; sem mudança.

## Tasks & Acceptance

**Execution:**
- [x] `config/league.yml` -- criado com `teams: 12`, `roster` (QB1/RB2/WR2/TE1/FLEX1/K1/DST1/BENCH6), `flex_positions: [RB, WR]`.
- [x] `R/core.R` -- `load_league(path = NULL)` público lê `config/league.yml`; `.warroom_shape_league()` valida e deriva `rounds = sum(roster)`; `.warroom_resolve_league()` re-deriva `rounds` também para uma liga explícita (chave `rounds` ignorada).
- [x] `config.R` -- lista `league` removida; `paths$league` adicionado.
- [x] `R/persistence.R` -- `.warroom_validate_state()` exige `rounds == sum(roster)`.
- [x] `R/recommendation.R` -- `.warroom_recs_result()` marca `attr(., "off_turn")` e prefixa a `reason` do topo quando o usuário não está na vez; sem abortar.
- [x] `scripts/draft.R` -- `load_league(cfg$paths$league)`; assert de binding no resume antes do loop.
- [x] `app.R` -- `load_league(cfg$paths$league)`; mesmo assert de binding no startup do `server()`.
- [x] `scripts/simulate.R` -- `load_league()` para o `team_order`.
- [x] `scripts/prepare.R` -- recusa sobrescrever `data/projections.rds` sem `--force` (antes de qualquer scrape); `.bak` do snapshot no caminho `--force`; cabeçalho ajustado.
- [x] `tests/smoke.R` -- `14`/`168`/`169` -> `15`/`180`/`181`; ligas custom redefinidas por `roster`; cenários (f)/(k)/(7g) ajustados para o strand guard em 15 rounds; blocos novos: resolver de liga, binding (terminal + Shiny), guarda `--force`, guarda "na vez".
- [x] `AGENTS.md` -- "Where things are" + policy `yaml`; `R/simulation.R` e `R/projections.R` comentários stale de "168" corrigidos.

**Acceptance Criteria:**
- Dado o repo após a mudança, quando `make test`, então passa com os 8 blocos de story OK e os blocos novos OK, sobre a fixture sintética, sem rede.
- Dado o repo após a mudança, quando `make simulate`, então as 3 estratégias completam com 12 rosters de **15** jogadores cada, todos válidos.
- Dado `grep -rn "168\|14L" R/ scripts/ app.R config.R`, quando inspecionado, então nenhum resultado é uma contagem de rounds/picks hardcoded (só constantes não relacionadas).
- Dado um `state/draft.rds` com `projection_created_at` diferente do snapshot em disco, quando `Rscript scripts/draft.R`, então aborta com erro explicando o descasamento e não entra no loop.
- Dado `data/projections.rds` presente, quando `Rscript scripts/prepare.R` sem `--force`, então recusa e não toca o arquivo.
- Dado um ensaio de terminal com 12 times, quando conduzido além do overall 168 com um stop/resume no meio, então chega a "DRAFT COMPLETO -- 180 picks".

## Spec Change Log

- **Review (wave 1), routed as patches — no loopback.** Blind-hunter +
  edge-case + verification-gap raised, and the following were fixed in place:
  - **Derived-`rounds` had a hole:** `.warroom_slot_counts()` in
    `recommendation.R` carries per-position defaults, so a slot missing/misspelled
    in `league.yml` would feed the default into starter math while contributing 0
    to `rounds` — the very AV-2 bug, relocated. Fix: `.warroom_shape_league()` now
    rejects unknown slots always, requires the full slot set for the YAML path
    (`require_all_slots = TRUE` in `load_league`), fills absent known slots with 0
    for an explicit `league` arg, and validates `flex_positions` (non-empty when
    FLEX>0, drawn from RB/WR/TE, each backed by a roster slot). The resolved
    roster therefore always carries all 8 keys, so the defaults never fire.
  - **Completed draft was flagged `off_turn = TRUE`** (`team_on_clock` is NA at
    the end). Fix: `on_clock <- isTRUE(view$is_complete) || identical(...)`.
  - **Binding check was copy-pasted into two adapters** (AGENTS.md forbids it).
    Fix: extracted `.warroom_assert_snapshot_binding(state, snapshot)` into
    `R/core.R`, with explicit NA / length-0 handling and `all.equal` instead of
    float `==`; Shiny raises it outside the load/create `tryCatch` so its own
    message survives.
  - **`load_league()` ran unconditionally at adapter startup**, making a
    missing/edited `league.yml` a new failure mode for a resume that uses
    `state$league` anyway. Fix: `load_league()` moved into the new-draft branch
    only, in both adapters; adapters call it with no argument (walk-up), matching
    how `config.R` is found and how the simulation core re-resolves.
  - **`prepare.R --force` write hardened:** the `.bak` is taken at the
    immutability guard (before any scrape), its `file.copy` return is checked,
    and the snapshot write is atomic (`.tmp` + `file.rename`).
  - **`.warroom_validate_state()` roster check** now also asserts integrality /
    non-negativity before comparing `rounds` to `sum(roster)` (a fractional slot
    could otherwise false-match through `as.integer` truncation).
  - Roxygen / companion docs updated: `new_draft` / `simulate_draft` /
    `make_snake_schedule` `@param`s, `recommend_players` `@return` (off_turn),
    `rds-contracts.md` invariants 10-11, `functional-core.md`,
    `recommendation-algorithm.md` "Off-turn use", `AGENTS.md` `--force`.
  - Deferred (in `deferred-work.md`): an offline `--force` end-to-end / `.bak`
    test (needs a ~40s ffanalytics-loading subprocess); the lack of a migration
    path for a pre-wave-1 `state/draft.rds` (no real draft in flight, stale dev
    state file deleted).

## Design Notes

`rounds` derivado, não armazenado: o resolver faz `rounds <- sum(roster)` (com
`roster` já coagido a inteiro nomeado). Isso vale tanto para o caminho YAML quanto
para uma `league` passada explicitamente — um `rounds` na lista de entrada é
descartado. É o que torna a inconsistência AV-2 impossível de reaparecer.

`state$league` continua carregando `rounds` (derivado) porque `derive_draft_view`,
o simulador e o validador de persistência já o consomem; a diferença é que agora
ele é sempre `sum(roster)` e o validador cobra isso.

Aviso de "fora da vez": preferir um atributo no data frame de retorno
(`attr(out, "off_turn_warning")`) mais uma linha em `reason` da primeira
recomendação, ou uma coluna booleana — o que os testes e `scripts/draft.R` /
`app.R` conseguem exibir sem duplicar regra. O adapter do terminal já só
auto-exibe na vez; o alvo é o `/rec` manual.

## Verification

**Commands:**
- `make test` -- expected: exit 0, "smoke OK", todos os blocos de story + novos OK. (rodado: verde, ~2min nesta máquina — a lentidão é o AV-4 pré-existente.)
- `make simulate` -- expected: exit 0, "todas as estrategias completaram com os 12 rosters validos", 15 jogadores por roster. (rodado: verde.)
- `grep -rn "\b168\b\|\b14L\b" R/ scripts/ app.R config.R` -- expected: nenhuma contagem de rounds/picks. (rodado: limpo — só comentários, corrigidos.)
- Ensaio de terminal com stop/resume -- rodado: 40 picks -> resume -> "DRAFT COMPLETO -- 180 picks"; binding assert e banner "fora da vez" confirmados; `app.R` sobe e serve.

## Suggested Review Order

**Formato de liga (a espinha)**

- Ponto de entrada: o resolver de YAML e a derivação de `rounds`.
  [`core.R:83`](../../R/core.R#L83)
- Validação forte pós-review: slot set exato, unknowns rejeitados, absent = 0 (ou erro no caminho YAML), `flex_positions` conferido.
  [`core.R:120`](../../R/core.R#L120)
- `config/league.yml` -- a fonte única no caminho ao vivo, sem `rounds`.
  [`league.yml:14`](../../config/league.yml#L14)
- `config.R` perde a lista `league`, ganha `paths$league`.
  [`config.R:5`](../../config.R#L5)

**Guardas de dia de draft**

- Helper de binding draft↔snapshot compartilhado (mata a duplicação entre adapters).
  [`core.R:218`](../../R/core.R#L218)
- Terminal: binding no resume; `load_league()` só no ramo de novo draft.
  [`draft.R:162`](../../scripts/draft.R#L162)
- Shiny: binding fora do `tryCatch` de load/create; `load_league()` só no ramo novo.
  [`app.R:125`](../../app.R#L125)
- `prepare.R`: `.bak` no guard (antes de qualquer scrape), retorno checado, escrita atômica.
  [`prepare.R:64`](../../scripts/prepare.R#L64)

**Recomendação fora da vez**

- `on_clock` inclui draft completo; `.warroom_recs_result()` marca o frame e prefixa a `reason` do topo.
  [`recommendation.R:431`](../../R/recommendation.R#L431)
- Banner no terminal e nota vermelha no Shiny lendo `attr(., "off_turn")`.
  [`draft.R:96`](../../scripts/draft.R#L96)

**Persistência**

- `.warroom_validate_state()`: integralidade do roster antes de comparar `rounds == sum(roster)`.
  [`persistence.R:68`](../../R/persistence.R#L68)

**Testes**

- Bloco novo do resolver de liga (feliz + 10 casos de erro).
  [`smoke.R:392`](../../tests/smoke.R#L392)
- Binding (terminal + Shiny), guarda "na vez", guarda `--force`, migração 168->180.
  [`smoke.R:1332`](../../tests/smoke.R#L1332)
