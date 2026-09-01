---
title: 'Snake schedule, estado de draft e persistência RDS'
type: 'feature'
created: '2026-09-01'
status: 'done'
review_loop_iteration: 0
baseline_commit: '94808547962efd7fd6b5614ce96da28989aeb2ed'
context:
  - '/Users/gsposito/Projects/football/DraftWarRoom/_bmad-output/specs/spec-fantasy-warroom/SPEC.md'
  - '/Users/gsposito/Projects/football/DraftWarRoom/_bmad-output/specs/spec-fantasy-warroom/rds-contracts.md'
  - '/Users/gsposito/Projects/football/DraftWarRoom/_bmad-output/specs/spec-fantasy-warroom/functional-core.md'
  - '/Users/gsposito/Projects/football/DraftWarRoom/_bmad-output/specs/spec-fantasy-warroom/operations.md'
  - '/Users/gsposito/Projects/football/DraftWarRoom/AGENTS.md'
---

<frozen-after-approval reason="human-owned intent — do not modify unless human renegotiates">

## Intent

**Problem:** As stories 1–2 entregaram o snapshot de projeção, mas não existe nada
que modele o draft: sem geração de schedule snake, sem criação/recuperação de
`state/draft.rds`, sem derivação de pick atual / rosters / disponíveis, sem
persistência atômica. As stories 4–8 (terminal, recomendação, simulador, Shiny)
não têm base de estado sobre a qual operar.

**Approach:** Implementar o núcleo funcional puro de estado de draft em
`R/core.R` (`make_snake_schedule`, `new_draft`, `record_pick`, `undo_pick`,
`derive_draft_view`, `next_user_pick`) e a persistência em `R/persistence.R`
(`load_state`, `save_state` atômico com `.bak`, checagem de schema). Persistir
somente fatos — os picks ordenados (`overall`, `player_id`, `entered_at`) — e
derivar todo o resto a partir deles mais o schedule e o snapshot. Sem loop de
terminal, sem recomendação, sem simulação, sem Shiny.

## Boundaries & Constraints

**Always:**
- `state/draft.rds` satisfaz `rds-contracts.md:37-64`: keys `schema_version` (=1L),
  `projection_created_at` (o `created_at` do snapshot), `league` (`teams`,
  `rounds`, `roster` vetor inteiro nomeado, `flex_positions`), `team_order`
  (character, ordem de slot), `user_team` (um item de `team_order`), `seed`
  (inteiro), `picks` (data frame ordenado).
- `picks` tem exatamente as colunas `overall` (integer), `player_id` (character),
  `entered_at` (POSIXct); `overall` igual ao número da linha; `player_id` único.
- Nunca persistir campos derivados: pick atual, time na vez, rosters, disponíveis,
  lineup, posição-no-round, recomendações. O próximo `overall` é sempre
  `nrow(picks) + 1`.
- Schedule snake: 12 slots × 14 rounds = 168 turnos; rounds ímpares slot 1→12,
  pares 12→1. Pick 13 → slot 12, pick 24 → slot 1, pick 25 → slot 1.
- Time na vez = `team_order[slot_do_schedule]`.
- Save atômico: escrever `<path>.tmp`; se `<path>` existe, copiar para
  `<path>.bak`; renomear `.tmp` por cima. Criar o diretório de destino se ausente.
- Funções puras em `R/`, nenhuma depende de `shiny`, nenhuma faz chamada de rede.
  `record_pick`/`undo_pick` só validam e retornam novo estado — não salvam (isso
  é do adapter da story 4).
- `record_pick` rejeita: `player_id` ausente do snapshot, `player_id` já em
  `picks`, `picks` já com `teams * rounds` linhas — cada um com `stop()`
  explicativo. `undo_pick` com `picks` vazio → `stop()`.
- `load_core()` carrega `R/*.R` em ordem alfabética; `core.R` antes de
  `persistence.R`. Sem dependência entre elas em tempo de `source()`.

**Ask First:**
- Alterar qualquer contrato de `rds-contracts.md`, os nomes/assinaturas do
  catálogo em `functional-core.md`, ou os alvos do `Makefile`.
- Adicionar arquivo em `R/` além de `core.R` e `persistence.R`.
- Adicionar a `derive_draft_view` o campo de melhor lineup (precisa de
  `lineup_value`, que é da story 5) — nesta story a view cobre pick atual, time
  na vez, rosters e disponíveis apenas.

**Never:**
- Loop de terminal (`scripts/draft.R`), recomendação (`R/recommendation.R`),
  simulação (`R/simulation.R`), Shiny (`app.R`) — stories 4–8.
- SQLite ou outro banco, event sourcing, R6, golem, targets, Docker, API,
  autenticação, background workers, injeção de dependência.
- Persistir estado derivado; RNG não-semeado em qualquer caminho; reconciliar
  com `docs/archive/`.

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| Schedule feliz | `make_snake_schedule(12L, 14L)` | data frame 168 linhas, colunas `overall`/`round`/`pick_in_round`/`slot`; `slot[13]==12`, `slot[24]==1`, `slot[25]==1`; `overall` sequencial | N/A |
| `new_draft` feliz | snapshot válido, `team_order` de 12 nomes, `user_team` em `team_order` | lista com todas as keys do contrato; `picks` com 0 linhas e os 3 tipos corretos; `projection_created_at == snapshot$created_at` | N/A |
| `team_order` inválido | comprimento != `league$teams`, ou com nomes duplicados | erro citando o problema | `stop()` |
| `user_team` fora | `user_team` não está em `team_order` | erro citando `user_team` | `stop()` |
| `record_pick` feliz | estado com k picks, `player_id` válido e livre | novo estado com k+1 linhas; `overall` da nova linha == k+1 | N/A |
| `player_id` desconhecido | id ausente do snapshot | erro citando o id | `stop()` |
| `player_id` repetido | id já em `picks` | erro citando o id | `stop()` |
| Draft cheio | `picks` com 168 linhas, novo `record_pick` | erro citando o limite 168 | `stop()` |
| `undo_pick` feliz | estado com k>=1 picks | novo estado com k-1 linhas; só a última removida; jogador volta a `available` na view | N/A |
| `undo_pick` vazio | `picks` com 0 linhas | erro | `stop()` |
| `derive_draft_view` | estado com k picks + snapshot | `current_overall == k+1`; `team_on_clock` == schedule; `rosters` particiona os k jogadores por time; `available` == players do snapshot menos os k drafted; nenhuma key derivada gravada no estado | N/A |
| View no fim | `picks` com 168 linhas | `is_complete == TRUE`; `current_overall == NA`; sem `team_on_clock` | N/A |
| `next_user_pick` | estado, slot do usuário | próximo `overall` cujo slot == slot do usuário e `>= current_overall`; respeita a virada snake | N/A |
| `next_user_pick` esgotado | usuário já fez todos os picks do slot | `NA_integer_` | N/A |
| `save_state` atômico | salvar duas vezes no mesmo path | arquivo legível por `readRDS`; após o 2º save, `<path>.bak` contém o estado anterior; nenhum `.tmp` remanescente | N/A |
| `save_state` dir ausente | `state/` não existe | diretório criado, arquivo escrito | N/A |
| `load_state` feliz | `state/draft.rds` gravado por `save_state` | lista igual; `picks` na mesma ordem | N/A |
| `load_state` ausente | path inexistente | erro citando o path | `stop()` |
| `load_state` schema ruim | `schema_version != 1L` ou key faltando ou `picks` malformado | erro nomeando o defeito | `stop()` |
| Round-trip | `new_draft` → vários `record_pick` → `save_state` → `load_state` → `derive_draft_view` | todos os picks preservados em ordem; view consistente | N/A |

</frozen-after-approval>

## Code Map

- `R/core.R` -- **novo**. `make_snake_schedule(teams, rounds)`, `new_draft(snapshot,
  team_order, user_team, seed = 1L, league = NULL)`, `record_pick(state, player_id,
  snapshot, entered_at = Sys.time())`, `undo_pick(state)`, `derive_draft_view(state,
  snapshot)`, `next_user_pick(state)`. Catálogo e layout:
  `functional-core.md:9-34`. Invariantes: `functional-core.md:40-48`.
- `R/persistence.R` -- **novo**. `load_state(path)`, `save_state(state, path)`,
  helper `.warroom_validate_state(x)`. Save atômico com `.bak`:
  `rds-contracts.md:39`, `AGENTS.md` (seção "Conventions"). Padrão de escrita
  atômica análogo ao `.bak` já usado em `tests/smoke.R:76-79`.
- `R/load_core.R` -- inalterado. `load_core()` já faz `source()` de `R/*.R` em
  ordem alfabética radix (`load_core.R:26-28`); `core.R` < `persistence.R` <
  `projections.R`.
- `config.R` -- `league` (`teams`, `rounds`, `roster`, `flex_positions`) já
  definido (`config.R:6-11`); `user_team`/`user_slot` placeholders
  (`config.R:28-29`); `paths$draft_state` já é `state/draft.rds`
  (`config.R:37`). Adicionar `seed <- 1L` (valor puro, sem lógica) para o
  `new_draft` e a story 7. `team_order` real é entrado imediatamente antes do
  draft (story 4) — não adicionar agora.
- `R/projections.R` -- `load_projections()` (`projections.R:253`) devolve o
  snapshot; `new_draft`/`derive_draft_view` consomem `snapshot$players` e
  `snapshot$created_at`. Não modificar.
- `tests/smoke.R` -- estender com bloco offline de story 3 (helpers `fail()`,
  `expect_error()` já existem em `smoke.R:15-25`). `cfg <- .warroom_load_config()`
  já disponível (`smoke.R:13`).
- Contrato de `state/draft.rds` e `picks`: `rds-contracts.md:37-64`. Roster
  inicial: `rds-contracts.md:53`. Formato da liga: `SPEC.md:80`.

## Tasks & Acceptance

**Execution:**
- [x] `R/core.R` -- criar. `make_snake_schedule(teams, rounds)`: data frame com
  `overall` (1..teams*rounds), `round`, `pick_in_round`, `slot`; round ímpar
  `slot = pick_in_round`, par `slot = teams - pick_in_round + 1`. `new_draft()`:
  resolve `league` (arg ou `config.R` via `.warroom_load_config`/`sys.source`
  — reusar o padrão de `projections.R`), valida `team_order` (comprimento ==
  `league$teams`, sem duplicados) e `user_team` (∈ `team_order`), monta a lista
  do contrato com `picks` vazio (`overall` integer(0), `player_id` character(0),
  `entered_at` como `POSIXct` de comprimento 0), `projection_created_at =
  snapshot$created_at`. `record_pick()`: valida id ∈ `snapshot$players$player_id`,
  id ∉ `state$picks$player_id`, `nrow(picks) < league$teams * league$rounds`;
  anexa linha com `overall = nrow(picks)+1`, `entered_at` coagido a POSIXct;
  retorna novo estado. `undo_pick()`: `stop()` se vazio, senão remove a última
  linha. `derive_draft_view()`: `current_overall = nrow(picks)+1` (ou `NA` se
  completo), `is_complete`, `round`/`slot_on_clock`/`team_on_clock` do schedule
  (`NULL`/`NA` se completo), `drafted_ids`, `available` (`snapshot$players`
  filtrado), `rosters` (lista nomeada por `team_order`, cada uma as linhas de
  `snapshot$players` dos picks daquele time via schedule). Nenhuma escrita em
  `state`. `next_user_pick()`: reconstrói o schedule de `state$league`, slot do
  usuário = `match(state$user_team, state$team_order)`, retorna o menor `overall`
  com esse slot e `>= current_overall`, ou `NA_integer_`.
- [x] `R/persistence.R` -- criar. `.warroom_validate_state(x)`: checa lista, keys
  do contrato, `schema_version == 1L`, `picks` data frame com as 3 colunas e
  tipos, `overall == seq_len(nrow)`, `player_id` único; `stop()` explicativo.
  `save_state(state, path)`: `.warroom_validate_state`; `dir.create` do
  `dirname(path)` se ausente; `saveRDS` em `paste0(path, ".tmp")`; se
  `file.exists(path)`, `file.copy(path, paste0(path, ".bak"), overwrite = TRUE)`;
  `file.rename(tmp, path)`; remover `.tmp` se o rename falhar; `invisible(path)`.
  `load_state(path)`: `stop()` citando o path se ausente; `readRDS`;
  `.warroom_validate_state`; retorna a lista.
- [x] `config.R` -- adicionar `seed <- 1L` (valor puro). Sem outra mudança.
- [x] `tests/smoke.R` -- adicionar bloco **offline** de story 3 cobrindo cada
  linha da matriz I/O: schedule (168, viradas), `new_draft` (keys, tipos de
  `picks`, `projection_created_at`), `team_order`/`user_team` inválidos,
  `record_pick` (feliz, id desconhecido, id repetido, draft cheio), `undo_pick`
  (feliz, vazio), `derive_draft_view` (pick atual, time na vez, rosters,
  disponíveis, sem key derivada no estado, view no fim), `next_user_pick`
  (virada snake, esgotado), `save_state` (atômico + `.bak` + sem `.tmp`, dir
  ausente), `load_state` (feliz, ausente, schema ruim), round-trip completo.
  Usar `file.path(tempdir(), ...)` para não tocar `state/`. Sem rede.

**Acceptance Criteria:**
- Given `make test` sem rede, when executado, then status 0 e o bloco de story 3
  passa junto com os de stories 1–2.
- Given um schedule de 12×14, when inspeciono qualquer fronteira de round, then a
  ordem serpentina está correta e há 168 picks.
- Given um estado após N `record_pick` seguido de `save_state` e `load_state`,
  when comparo `picks`, then são idênticos e na mesma ordem, e `state/draft.rds`
  nunca contém pick atual, rosters ou disponíveis.
- Given `derive_draft_view` para qualquer N de picks, when leio `current_overall`,
  then é `nrow(picks) + 1` e `team_on_clock` casa com o schedule gerado.
- Given `grep -RIn "shiny\|recommend\|simulate_draft\|scrape\|http" R/core.R R/persistence.R`,
  then não há resultado.

## Spec Change Log

## Design Notes

- Fórmula snake, `r` 1-based: `overall = (r-1)*teams + pick_in_round`;
  `slot = if (r %% 2 == 1) pick_in_round else teams - pick_in_round + 1`.
  Verificação: `r=2, pick_in_round=1 → overall 13, slot 12`; `r=3,
  pick_in_round=1 → overall 25, slot 1`.
- `picks` vazio precisa dos tipos certos para o round-trip e o `rbind` incremental
  não promover colunas: `data.frame(overall = integer(0), player_id =
  character(0), entered_at = as.POSIXct(character(0)), stringsAsFactors = FALSE)`.
- `rosters` é derivado assim: para cada pick `i`, `slot = schedule$slot[i]`,
  `team = team_order[slot]`; agrupar `snapshot$players[match(picks$player_id,
  players$player_id), ]` por `team`. Times sem picks aparecem como data frame de
  0 linhas.
- `derive_draft_view` recebe o snapshot porque `available` e `rosters` são
  projeções sobre `snapshot$players`; o estado sozinho só tem `player_id`.
- Atomicidade "suficiente para uso local" (`intent`): não há `fsync`; a garantia
  é `.tmp` + `.bak` + `rename`, então uma falha no meio nunca deixa o
  `draft.rds` principal corrompido — pior caso o `.tmp` fica para trás.
- `entered_at` é um fato persistido, não derivado; `Sys.time()` como default é
  aceitável (o contrato só exige POSIXct) e não afeta determinismo de
  recomendação (essa preocupação é das stories 5–6).

## Verification

**Commands:**
- `make test` -- expected: status 0, sem rede; bloco de story 3 + stories 1–2.
- `Rscript -e 'source("R/load_core.R"); load_core(); s <- make_snake_schedule(12L,14L); stopifnot(nrow(s)==168L, s$slot[13]==12L, s$slot[24]==1L, s$slot[25]==1L)'`
  -- expected: sem erro.
- `Rscript -e 'source("R/load_core.R"); load_core(); snap <- build_synthetic_projections(); d <- new_draft(snap, sprintf("Team %02d", 1:12), "Team 01"); p <- file.path(tempdir(),"d.rds"); save_state(d, p); save_state(record_pick(d, snap$players$player_id[1], snap), p); stopifnot(file.exists(paste0(p,".bak")), nrow(load_state(p)$picks)==1L)'`
  -- expected: sem erro.
- `grep -RIn "shiny\|recommend\|simulate_draft\|scrape\|http" R/core.R R/persistence.R` -- expected: vazio.

## Suggested Review Order

**Schedule serpentino (a mecânica central)**

- Ponto de entrada: fórmula de virada `slot` por paridade do round; 168 turnos.
  [`core.R:50`](../../../../R/core.R#L50)
- Guarda compartilhada — rejeita `teams`/`rounds` NA, não-escalar, fracionário, `< 1`.
  [`core.R:31`](../../../../R/core.R#L31)

**Criação e validação do estado (persistir fatos)**

- `new_draft` monta as 7 keys do contrato com `picks` vazio tipado; valida snapshot, `team_order`, `user_team`, `seed`.
  [`core.R:126`](../../../../R/core.R#L126)
- `picks` vazio com os tipos exatos — o `rbind` incremental não promove colunas e o round-trip RDS não altera nada.
  [`core.R:19`](../../../../R/core.R#L19)
- Resolução da liga: guarda `is.list` antes da checagem de keys; `roster` rejeita valores não-inteiros.
  [`core.R:71`](../../../../R/core.R#L71)
- Gate de schema de `state/draft.rds` — usado no save (antes de escrever) e no load (depois de ler).
  [`persistence.R:32`](../../../../R/persistence.R#L32)
- Bloco de invariantes de `picks`: `overall == 1:n`, `player_id` único, teto `teams * rounds`.
  [`persistence.R:107`](../../../../R/persistence.R#L107)

**Derivação de views (nunca persistida)**

- `derive_draft_view` — pick atual, round/slot/time na vez pelo schedule, `available`, `rosters` particionados por slot.
  [`core.R:260`](../../../../R/core.R#L260)
- `record_pick` valida id (no snapshot, não repetido), teto de picks, e coage/valida `entered_at`; não salva.
  [`core.R:183`](../../../../R/core.R#L183)
- `next_user_pick` — menor `overall` do slot do usuário `>= current_overall`, ou `NA`.
  [`core.R:318`](../../../../R/core.R#L318)

**Escrita atômica**

- `save_state` — `.tmp` (com limpeza em falha de `saveRDS`), `.bak` do estado anterior, `rename` por cima; cria o diretório.
  [`persistence.R:137`](../../../../R/persistence.R#L137)
- `load_state` — `readRDS` em `tryCatch` (arquivo corrompido nomeia o path), depois o gate de schema.
  [`persistence.R:179`](../../../../R/persistence.R#L179)

**Periféricos**

- Bloco offline de story 3: cada linha da matriz I/O, `tempdir()` apenas, sem rede.
  [`smoke.R:389`](../../../../tests/smoke.R#L389)
- Cobertura serpentina além do round 1: estados de 12/13/14 picks, `team_on_clock` `Team 12` → `Team 11`, pick 13 no roster certo.
  [`smoke.R:555`](../../../../tests/smoke.R#L555)
- `undo_pick` devolve o jogador a `available` na view; renumera `overall` após undo.
  [`smoke.R:512`](../../../../tests/smoke.R#L512)
- Validação pré-escrita de `save_state` e `load_state` com schema/arquivo ruim.
  [`smoke.R:621`](../../../../tests/smoke.R#L621)
- `config.R`: `seed` como valor puro (consumido também pelo simulador da story 7).
  [`config.R:34`](../../../../config.R#L34)
