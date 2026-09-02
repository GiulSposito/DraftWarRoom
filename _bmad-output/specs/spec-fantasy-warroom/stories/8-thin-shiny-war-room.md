---
title: 'Thin Shiny War Room'
type: 'feature'
created: '2026-09-02'
status: 'done'
review_loop_iteration: 0
baseline_commit: '43e455de87caf264d0221f6f7fcadc059228ae7b'
context:
  - '/Users/gsposito/Projects/football/DraftWarRoom/_bmad-output/specs/spec-fantasy-warroom/SPEC.md'
  - '/Users/gsposito/Projects/football/DraftWarRoom/_bmad-output/specs/spec-fantasy-warroom/operations.md'
  - '/Users/gsposito/Projects/football/DraftWarRoom/_bmad-output/specs/spec-fantasy-warroom/functional-core.md'
  - '/Users/gsposito/Projects/football/DraftWarRoom/_bmad-output/specs/spec-fantasy-warroom/rds-contracts.md'
  - '/Users/gsposito/Projects/football/DraftWarRoom/AGENTS.md'
---

<frozen-after-approval reason="human-owned intent — do not modify unless human renegotiates">

## Intent

**Problem:** Stories 1-7 entregaram o core completo (schedule, estado, persistência,
recomendação, simulador), mas o único jeito de conduzir um draft é o terminal
(`scripts/draft.R`). CAP-11 exige uma página Shiny fina que opere o mesmo draft
lendo/gravando o mesmo `state/draft.rds`, sem duplicar nenhuma fórmula.

**Approach:** Criar `app.R` como um shell fino: uma única página com banner de
pick/round/time na vez, campo de busca + botão Draft, Undo, tabela de
recomendações, roster do usuário (titulares/FLEX/banco), picks recentes, e
tabela de disponíveis filtrável por posição. `server` chama só as funções já
existentes (`load_state`/`save_state`, `derive_draft_view`, `record_pick`,
`undo_pick`, `recommend_players`, `available_board`, `next_user_pick`,
`resolve_player` não é necessário — seleção é via lista, não texto livre). Uma
única função pública nova e mínima, `roster_slots()`, reaproveita a seleção de
titulares já existente em `R/simulation.R` (nenhuma fórmula nova).

## Boundaries & Constraints

**Always:**
- `app.R` só chama funções de `R/` (via `source("R/load_core.R"); load_core()`,
  mesmo padrão de `scripts/draft.R`); nenhuma fórmula (VOR, wait_cost, p_next,
  tier_cliff, lineup value) recalculada em reactive/observer.
- `server <- function(input, output, session, snapshot = NULL, state_path =
  NULL, config = NULL)` — mesmo padrão de injeção de dependências de
  `run_draft(con, out, snapshot, state_path, config)` (`scripts/draft.R:130`),
  para permitir `shiny::testServer()` com fixtures de `tempdir()` sem tocar
  `data/`/`state/` reais. Sem os args, usa `config.R` e os caminhos reais.
- Um pick por sessão é serializado: `record_pick()`/`undo_pick()` seguidos de
  `save_state()` antes de atualizar o `reactiveVal` do estado (mesma ordem do
  terminal — nunca atualizar a UI antes de o save ter sucesso).
- Nova função pública `roster_slots(roster, league)` em `R/recommendation.R`:
  reusa `.warroom_sim_starter_ids()` (`R/simulation.R:184`, já reusada entre
  arquivos — mesmo padrão da story 7) chamando-a duas vezes (com `FLEX` do
  `league$roster` e com `FLEX = 0L`) para isolar quem ocupa o slot FLEX; devolve
  `data.frame(player_id, slot)` com `slot` em QB/RB/WR/TE/FLEX/BENCH. Não
  reimplementa a seleção de titulares.
- Sem estado em `state/draft.rds`: criar um draft novo via `new_draft()` com
  `team_order = sprintf("Team %02d", seq_len(league$teams))` e
  `user_team = cfg$user_team`, salvo imediatamente — mesma semântica de
  "recovery" do terminal, sem formulário de ordem de times (não listado em
  `operations.md` "Shiny (CAP-11)").
- Seleção de jogador para draftar é uma lista (`selectizeInput`) alimentada por
  `view$available` — sem reimplementar `resolve_player()`/fuzzy match; a lista
  já garante escolha inequívoca.
- `Makefile` já tem o alvo `app`; nenhuma dependência nova além de `shiny`
  (`renv::install("shiny"); renv::snapshot()` — `shiny` só aparece hoje como
  dependência transitiva no `renv.lock`, não como pacote próprio).

**Ask First:**
- Qualquer mudança em `R/core.R`, `R/persistence.R`, `R/simulation.R`, no
  algoritmo de `recommend_players()`/`lineup_value()`, ou nos pesos default.

**Never:**
- Chamada de rede no `server` (`load_projections`/`load_state`/`save_state`
  são as únicas fontes de dado, sem `ffanalytics`).
- Reimplementar `resolve_player()`, matching de nome, ou a seleção de titulares
  em `app.R`.
- Shiny modules, autenticação, múltiplas sessões/drafts simultâneos, DT ou
  outra dependência de tabela além de `shiny::renderTable`/`tableOutput`.

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| Sem `state/draft.rds` | primeira sessão | cria draft via `new_draft()` (times default), salva, banner mostra R01 overall 1 | N/A |
| Estado existente | `state/draft.rds` com N picks | `load_state()` carrega, banner reflete `derive_draft_view()` | N/A |
| Draft de jogador | escolher `player_choice`, clicar Draft | `record_pick()` + `save_state()`; banner e tabelas atualizam; jogador some de disponíveis | erro de `record_pick()` vira `showNotification` de erro, estado não muda |
| Undo | clicar Undo sem picks | `undo_pick()` levanta erro | erro vira `showNotification`, estado não muda |
| Equivalência terminal/Shiny | mesmo `state/draft.rds` + snapshot | `recommend_players()` via `server`'s reactive tem a mesma ordem de `player_id` que a chamada direta usada pelo terminal | N/A |
| Draft completo | `derive_draft_view()$is_complete` | banner mostra "DRAFT COMPLETO", tabela de recomendações vazia | N/A |

</frozen-after-approval>

## Code Map

- `R/core.R` — `load_state`/`save_state` (na verdade em `persistence.R`),
  `derive_draft_view():260`, `record_pick():183`, `undo_pick():238`,
  `next_user_pick():318`, `available_board():438` — **reusar, não modificar**.
- `R/persistence.R` — `load_state():179`, `save_state():137` — reusar.
- `R/recommendation.R` — `recommend_players():409`, `lineup_value():154` —
  reusar; **adicionar** `roster_slots(roster, league)` logo após `lineup_value`.
- `R/simulation.R` — `.warroom_sim_starter_ids():184` — reusado por
  `roster_slots()` (cross-file, mesmo padrão já usado pela própria story 7).
- `R/projections.R` — `load_projections():253`, `.warroom_find_file():40` (para
  o loader de `config.R` local a `app.R`) — reusar.
- `scripts/draft.R` — `run_draft(con, out, snapshot, state_path, config):130` e
  `.warroom_draft_config():21` — modelo do padrão de injeção de dependências a
  replicar em `app.R`'s `server()`.
- `app.R` — **novo**, raiz do repo. `ui` (fluidPage único), `server(input,
  output, session, snapshot=NULL, state_path=NULL, config=NULL)`,
  `shinyApp(ui, server)` no fim.
- `tests/smoke.R` — **estender**, bloco de story 8 antes do `## --- Summary`,
  usando `shiny::testServer()`.
- `renv.lock` — **adicionar** `shiny` (hoje só dependência transitiva).

## Tasks & Acceptance

**Execution:**
- [x] `renv::install("shiny")` + `renv::snapshot()` -- fixa `shiny` como
  dependência própria.
- [x] `R/recommendation.R` -- `roster_slots(roster, league)`.
- [x] `app.R` -- `ui`, `server()` injetável, `shinyApp(ui, server)`.
- [x] `tests/smoke.R` -- bloco de story 8 cobrindo a matriz I/O acima via
  `shiny::testServer()`, mais um `grep` confirmando que `app.R` não redefine
  `recommend_players`/`lineup_value`/`derive_draft_view`/`record_pick` nem usa
  `pnorm(`/`rnorm(`/`runif(`.

**Acceptance Criteria:**
- Given `make test`, when executado sem rede, then status 0 com os blocos de
  stories 1-8.
- Given o mesmo `state/draft.rds` + snapshot, when `recommend_players()` roda
  via terminal e via `server`'s reactive (`shiny::testServer`), then
  `player_id` na mesma ordem (`identical()`).
- Given um pick registrado via `input$draft_btn`, when `state/draft.rds` é
  recarregado fora da sessão Shiny, then o pick está lá (mesmo contrato atômico
  de `save_state()`).
- Given `grep -nE "pnorm\(|rnorm\(|runif\(" app.R`, when inspecionado, then
  nenhuma ocorrência.

## Design Notes

- **`roster_slots()` sem duplicar a seleção.** Chamar
  `.warroom_sim_starter_ids(roster, league)` com o `league$roster` real dá os
  titulares (QB/RB/WR/TE + FLEX); chamar de novo com uma cópia de `league` onde
  `roster[["FLEX"]] <- 0L` dá só os titulares "puros". A diferença entre os dois
  conjuntos é exatamente quem ocupa o FLEX -- zero lógica de seleção nova.
- **`server` injetável, não uma função anônima em `shinyApp()`.** Precisa ser um
  objeto nomeado, com os mesmos três args extras de `run_draft()`, para
  `shiny::testServer(server, args = list(snapshot = snap, state_path = tmp,
  config = cfg))` funcionar sem tocar `data/`/`state/` reais -- mesmo motivo que
  já levou `scripts/draft.R` a expor `con`/`out`/`snapshot`/`state_path`/`config`.
- **Sem `resolve_player()` em `app.R`.** A UI já mostra só jogadores disponíveis
  numa lista pesquisável (`selectizeInput`); escolher da lista não tem
  ambiguidade, então o matching fuzzy do terminal (que existe para texto livre)
  não se aplica aqui -- não é fórmula duplicada, é uma UI diferente para o
  mesmo passo (CAP-7 continua sendo o único dono do matching de texto).

## Verification

**Commands:**
- `make test` -- espera status 0, inclui bloco de story 8.
- `make app` -- sobe a página em `http://127.0.0.1:PORT`; inspecionar
  manualmente banner, draft, undo, recomendações, roster e disponíveis.

**Manual checks:**
- `make app`, draftar um jogador, conferir que ele some de "disponíveis" e
  aparece em "picks recentes"; rodar `make draft` (terminal) apontando pro
  mesmo `state/draft.rds` e conferir que `/rec` mostra a mesma ordem.

## Suggested Review Order

**Server: injeção de dependências + fluxo de estado**

- Entrypoint: mesma assinatura injetável de `run_draft()`, permite `testServer()` sem tocar `data/`/`state/` reais.
  [`app.R:87`](../../../../app.R#L87)

- Sem `state/draft.rds`: cria via `new_draft()` com ordem default de times, salva na hora; startup agora envolto em `tryCatch` com mensagem clara.
  [`app.R:102`](../../../../app.R#L102)

- `commit_state()`: `save_state()` sempre antes de atualizar o `reactiveVal` — nunca UI antes do save confirmado.
  [`app.R:126`](../../../../app.R#L126)

**Roster slotting: reuso sem duplicar fórmula**

- `roster_slots()`: chama `.warroom_sim_starter_ids()` duas vezes (FLEX real vs `FLEX = 0L`) para isolar quem ocupa FLEX — zero seleção nova.
  [`R/recommendation.R:178`](../../../../R/recommendation.R#L178)

- `output$roster_table`: usa `roster_slots()` para renderizar titulares/FLEX/banco, sem recalcular nenhuma fórmula.
  [`app.R:202`](../../../../app.R#L202)

**UI: montagem da página**

- `fluidPage` único: banner, busca+draft, undo, recomendações, roster, picks recentes, disponíveis.
  [`app.R:37`](../../../../app.R#L37)

- `shinyApp(ui, server)`: ponto de entrada real do `make app`.
  [`app.R:256`](../../../../app.R#L256)

**Testes: equivalência terminal/Shiny + cobertura de render**

- Bloco de story 8 completo, reusa `snap`/`cfg`/`team_order` do escopo existente.
  [`tests/smoke.R:1455`](../../../../tests/smoke.R#L1455)

- `.s8_bake_server()`: contorna limitação do `shiny::testServer()` (args só para module server) fixando os argumentos extras como defaults.
  [`tests/smoke.R:1480`](../../../../tests/smoke.R#L1480)

- (8e) Equivalência de recomendação + regressão de `output$roster_table`/`recent_picks_table`/`available_table` (achada na revisão — antes nenhum teste lia esses outputs).
  [`tests/smoke.R:1578`](../../../../tests/smoke.R#L1578)

- (8g) `roster_slots()` isolado: titulares QB/RB/WR/TE, FLEX, e K/DST sempre em BENCH.
  [`tests/smoke.R:1663`](../../../../tests/smoke.R#L1663)

- (8h) Análise estática: sem redefinição de função core, sem símbolo de RNG/rede (grep ampliado na revisão).
  [`tests/smoke.R:1692`](../../../../tests/smoke.R#L1692)
