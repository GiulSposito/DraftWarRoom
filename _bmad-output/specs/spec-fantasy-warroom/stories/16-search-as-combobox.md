---
title: 'Busca como combobox customizado (story 16)'
type: 'feature'
created: '2026-09-03'
status: 'done'
review_loop_iteration: 0
baseline_commit: 'c74c80c5dc10e3d27914272df278e757110ac85c'
context:
  - '/Users/gsposito/Projects/football/DraftWarRoom/_bmad-output/specs/spec-fantasy-warroom/SPEC.md'
  - '/Users/gsposito/Projects/football/DraftWarRoom/AGENTS.md'
  - '/Users/gsposito/Projects/football/DraftWarRoom/docs/design/DESIGN.md'
  - '/Users/gsposito/Projects/football/DraftWarRoom/docs/design/EXPERIENCE.md'
  - '/Users/gsposito/Projects/football/DraftWarRoom/_bmad-output/specs/spec-fantasy-warroom/stories/14-candidate-list-readability-and-click-to-pick.md'
---

<frozen-after-approval reason="human-owned intent — do not modify unless human renegotiates">

## Intent

**Problem:** A busca de jogador em `app.R` é um `selectizeInput("player_choice")`:
o casamento de nome é o do selectize (client-side), não o `resolve_player()`
tolerante (exato / prefixo / substring / fuzzy) que o terminal usa, e as opções
são rótulos únicos sem posição / time NFL destacados. DESIGN.md §"Campo de busca
+ autocomplete" e EXPERIENCE.md pedem um campo dominante com resultados
imediatamente abaixo — cada linha com nome, posição e time NFL — e o resultado
destacado sendo a ação de `Enter`.

**Approach:** Trocar `selectizeInput("player_choice")` por
`textInput("player_query")` + um `uiOutput("search_results")` renderizado no
servidor a partir de `resolve_player(input$player_query, view()$available,
snapshot$players)`. Cada resultado é um `tags$button` (o mesmo padrão nativo da
linha-candidato da story 14) que chama o `do_pick()` único; a 1ª linha recebe
`--active` e é o que o botão **Registrar** (e `Enter`) registra. Nenhuma tecla
re-chama `recommend_players()`.

## Boundaries & Constraints

**Always:**
- Casamento de nome = só `resolve_player()` (R/core.R). Nenhum segundo matcher em
  `app.R`; `resolve_player(` aparece exatamente uma vez em `app.R` (no reactive
  `search_hits`).
- Caminho de pick único: `do_pick()` continua a única função que chama
  `record_pick()` / `commit_state()` / escreve `feedback()`. `record_pick(` e
  `undo_pick(` continuam aparecendo uma vez cada em `app.R`. Ordem inalterada:
  `record_pick()` -> `save_state()` -> `state(new_st)` (AGENTS.md).
- `recommend_players(` continua chamado exatamente uma vez (reactive `recs`). Uma
  tecla na busca recomputa só `search_hits` (`resolve_player` + `view()$available`),
  nunca `recs()` / `recommend_players()` (guardrail de performance da
  `stories.yaml` / `RETROSPECTIVE.md` AV-4).
- `search_hits <- reactive(resolve_player(input$player_query %||% "",
  view()$available, snapshot$players))`. Query vazia ou status `"none"` -> nenhuma
  linha. Exibe no máximo 8 linhas de `res$players` (já ordenadas por `points`
  desc, `player_id`).
- Cada linha: `tags$button(type = "button", id = "search_row_<k>", class =
  "search-result action-button[ search-result--active]", `aria-label` =
  "Registrar <jogador>")`, com spans nome / pos / time NFL (`nfl_team` ausente ou
  `NA` -> sem separador, sem a string `"NA"`). `k` de 1 a 8.
- `draft_btn` "Registrar" repontado para `do_pick(<1º player_id de
  search_hits()$players ou NA>, "Selecione um jogador na busca antes de
  registrar.")`. Os observers `search_row_<k>` chamam `do_pick(<k-ésimo player_id
  ou NA>, "Resultado de busca indisponível — refaça a busca.")`, registrados por
  `lapply(seq_len(8L), …, ignoreInit = TRUE)` com `force()` no índice.
- `do_pick()` no sucesso limpa o campo: `updateTextInput(session, "player_query",
  value = "")` no lugar do antigo `updateSelectizeInput(…, selected = "")`.
- O placeholder segue a string acentuada exata `"buscar jogador disponível..."`
  (asserção da story 13). `actionButton("draft_btn", "Registrar")` e
  `actionButton("undo_btn", "Undo")` seguem.
- `app.R` adapter fino: sem pacote novo no `renv.lock`; sem `bslib` / `sass` /
  `includeCSS` / `shinyjs` / `Shiny.setInputValue`; sem símbolo de rede ou RNG.
  CSS só em `www/styles.css`, sem asset remoto.
- Afeto de hover / foco de `.search-result` em `--surface-raised` (DESIGN.md
  `components.search-autocomplete.background` / `candidate-active.background`); o
  anel de foco azul vem da regra global `button:focus` — não duplicar. Só tokens
  de `DESIGN.md`, nenhum token de cor novo.
- **Wiring de `Enter` (resolvido no checkpoint — Opção A).** Um único
  `tags$script(HTML(...))` no `tags$head`, ≤ 8 linhas, `keydown` puro no DOM (sem
  `Shiny.setInputValue`, sem input binding próprio, sem `shinyjs`): num `Enter`
  dentro de `#player_query`, `.click()` na `.search-result--active` (ou, se não
  houver, na primeira `.search-result`). É a única exceção ao veto de `tags$script`
  — `tests/smoke.R:3021` é afrouxado só para tolerar esse script vetado, mantendo
  o veto a `Shiny.setInputValue` / `shinyjs` / `bslib` / `sass` / `includeCSS`. A
  story 22 (C1) expande esse mesmo script.

**Ask First:**
- Remover os seletores `.selectize-*` de `www/styles.css` (não há mais selectize)
  vs. deixá-los mortos.
- Introduzir `debounce()` no `search_hits` — não recomendado: `resolve_player` é
  sub-ms sobre ≤ ~320 disponíveis e o debounce acrescenta timing não
  determinístico ao `testServer`.

**Never:**
- Re-chamar `recommend_players()` numa tecla ou num clique de resultado.
- Segundo caminho de registro de pick; segundo matcher de nome.
- Navegação por setas / `role="combobox"` / `"listbox"` / `"option"` /
  `aria-expanded` / `aria-activedescendant` / roving tabindex — stories 22 (C1) e
  23 (C3).
- Painel de inspeção, board em grade, undo redesenhado, histórico de eventos
  (stories 17–21).
- Rede, `ffanalytics`, leitura de `yaml` nova, mudança em `state/draft.rds` /
  `data/projections.rds`, Shiny modules, mudança no núcleo em `R/`.

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| Prefixo único, na vez | `player_query` = nome que `resolve_player` case unique; `search_row_1 = 1` | linha 1 = esse jogador; clique -> `record_pick()`; `state()$picks` +1; `feedback()` `list(kind="ok", text="Registrado: <j>")`; estado salvo; `player_query` limpo | N/A |
| **Registrar** com query de 1 hit | `player_query` resolve unique, `draft_btn = 1` | mesmo `do_pick` do clique; registra `search_hits()$players$player_id[1]` | N/A |
| Query ambígua | `player_query = "williams"` | várias `.search-result`; a 1ª com `--active`; nenhum pick até clique / **Registrar**; `identical(recs(), <antes>)` | N/A |
| Query sem resultado | `player_query = "zzzz"` | `<p class="search-empty">Nenhum jogador disponível corresponde à busca.</p>`; `state()` intacto | persistente, sem crash |
| Query vazia | `player_query = ""` | `search_results` = container vazio, nenhuma linha | N/A |
| **Registrar** sem query | `player_query = ""`, `draft_btn = 1` | `feedback()` erro `"Selecione um jogador na busca antes de registrar."`; `state()` intacto | persistente |
| Clique fora de alcance | `search_row_5 = 1` com 3 resultados | `do_pick(NA, …)` -> `feedback()` erro `"Resultado de busca indisponível — refaça a busca."`; `state()` intacto | página funcional |
| `Enter` no campo com resultados | `player_query` resolve ≥ 1 hit, `keydown` Enter | `.click()` na `.search-result--active` -> mesmo `do_pick` do clique de linha 1 | N/A |
| Tecla na busca não recomputa recs | qualquer `player_query` | `identical(recs(), <antes>)`; `recommend_players(` 1× no arquivo | N/A |
| `www/styles.css` ausente | arquivo removido | lista de resultados monta, clique registra, sem erro de servidor | página funcional |

</frozen-after-approval>

## Code Map

- `app.R:56-63` — `column(5, selectizeInput("player_choice", "Jogador", choices =
  NULL, options = list(placeholder = "buscar jogador disponível...")),
  actionButton("draft_btn", …), actionButton("undo_btn", …))`. **Trocar** o
  `selectizeInput` por `textInput("player_query", "Jogador", placeholder =
  "buscar jogador disponível...")` seguido de `uiOutput("search_results")`. Os
  dois `actionButton` inalterados.
- `app.R:191-211` — bloco `observe({ av <- view()$available; …
  updateSelectizeInput(session, "player_choice", choices = choices, server =
  TRUE) })` que populava as opções pela available board. **Remover** inteiro —
  substituído pelo reactive `search_hits`.
- `app.R:175-189` — reactives `view` / `recs` / `recs_view`. **Adicionar** logo
  abaixo: `search_hits <- reactive({ resolve_player(input$player_query %||% "",
  view()$available, snapshot$players) })`.
- `app.R:225-248` — `do_pick(pid, empty_msg)`. **Trocar** a linha
  `updateSelectizeInput(session, "player_choice", selected = "")` por
  `updateTextInput(session, "player_query", value = "")`. Todo o resto (guarda de
  id vazio, `tryCatch`, derivação de `N` para "já escolhido") idêntico.
- `app.R:250-253` — `observeEvent(input$draft_btn, { do_pick(input$player_choice,
  "Selecione um jogador na busca antes de registrar.") })`. **Trocar** o 1º
  argumento por `{ h <- search_hits()$players; if (nrow(h) >= 1L) h$player_id[1]
  else NA_character_ }`.
- `app.R:255-270` — `lapply(seq_len(10L), … pick_row_%d …)` (story 14). **Não
  tocar.** **Adicionar** ao lado: `lapply(seq_len(8L), function(k) { force(k);
  observeEvent(input[[sprintf("search_row_%d", k)]], { h <- search_hits()$players;
  pid <- if (k <= nrow(h)) h$player_id[k] else NA_character_; do_pick(pid,
  "Resultado de busca indisponível — refaça a busca.") }, ignoreInit = TRUE) })`.
- `app.R` (junto aos demais `output$… <- renderUI`) — **Adicionar**
  `output$search_results <- renderUI({...})`: `res <- search_hits()`;
  `q <- input$player_query %||% ""`; `res$players` limitado a 8;
  `k == 1` -> classe `search-result action-button search-result--active`, senão
  `search-result action-button`; join de `nfl_team` a partir de `snapshot$players`
  como o status strip / `recs_table` fazem (coluna ausente -> só pos, sem
  separador); `res$status == "none" && nzchar(q)` -> `tags$p(class =
  "search-empty", "Nenhum jogador disponível corresponde à busca.")`;
  `!nzchar(q)` -> `tags$div(class = "search-results")` vazio.
- `app.R:21` — `%||%` disponível. `R/core.R:505` —
  `resolve_player(query, available, all_players = available)`; `available` precisa
  de `player_id` / `player` / `points` (satisfeito por `view()$available`);
  devolve `list(status, players, query)` com `players` ordenado por `points` desc,
  `player_id` asc. `scripts/draft.R:243` — uso de referência (status / ramo
  ambíguo).
- `www/styles.css:789-856, 901` — bloco `form fields + selectize`. **Manter**
  `.form-control` / `.form-control::placeholder` / a regra global `button:focus`
  (o `textInput` usa `.form-control`). Decisão de checkpoint sobre remover os
  seletores `.selectize-*` (`:801` só a parte `.selectize-input`, `:816-856`,
  `:901`). **Adicionar** um bloco `.search-results` / `.search-result` (reset de
  `<button>` no mesmo molde de `button.candidate`, `:358-368` / `:420-427`) /
  `.search-result--active` (fundo `var(--surface-raised)`) / `.search-empty`
  (texto `var(--ink)`).
- `www/styles.css:1-60` — comentário de cabeçalho: **acrescentar** a nota da story
  16 (campo `textInput` + lista `.search-result` server-rendered, casamento por
  `resolve_player()`).
- `tests/smoke.R:1982, 2039, 2405, 2708, 3005, 3532` — listas de `id` esperados na
  UI estática. **Trocar** `"player_choice"` por `"player_query"` (e adicionar
  `"search_results"` onde fizer sentido).
- `tests/smoke.R:1707, 1716, 1735` (s8), `2768, 2792, 2821, 2825, 2841, 2877,
  2909, 2979` (s13), `3184` (s14) — `session$setInputs(player_choice = <pid|"">)`.
  **Migrar** cada um: definir `player_query` com um nome que `resolve_player` case
  de forma única para aquele jogador (`snap$players$player[match(pid, …$player_id)]`)
  e então `session$setInputs(draft_btn = 1)` (ou `search_row_1 = 1`). O caso
  `"SYN-NOT-A-REAL-ID"` (s13e2, `:2877`) vira uma query sem match (`"zzzz"`),
  exercitando o mesmo ramo "sem seleção". O caso vazio (s14d, `:3184`) vira
  `player_query = ""`.
- `tests/smoke.R:3013` — asserção de que `app.R` contém a string acentuada
  `"buscar jogador disponível..."`: segue satisfeita (placeholder do `textInput`).
  `:3014` — `actionButton("draft_btn", "Registrar"`: inalterado.
- `tests/smoke.R:3021` — grep anti-JS
  (`bslib|sass|includeCSS|shinyjs|tags$script|Shiny.setInputValue`). **Afrouxar**:
  tirar `tags\$script` do padrão e, em troca, asseverar que existe exatamente um
  `tags$script` em `app.R` e que seu corpo não contém `Shiny.setInputValue` /
  `Shiny.` / `fetch(` / `http`. `shinyjs` / `bslib` / `sass` / `includeCSS` /
  `Shiny.setInputValue` seguem vetados.
- `tests/smoke.R:3623` / `:3625` — fim do bloco story 15 / início do guard de
  `prepare.R`. **Inserir** o bloco `## --- story 16` entre eles.
- `tests/smoke.R:1634-1653` — `.s8_bake_server`, `.strip_html`, `.html_count`
  (reusar).

## Tasks & Acceptance

**Execution:**
- [x] `app.R` — trocar `selectizeInput("player_choice")` por
  `textInput("player_query")` + `uiOutput("search_results")`; remover o `observe`
  de `updateSelectizeInput`; adicionar o reactive `search_hits` (`resolve_player`);
  repontar `draft_btn` para o 1º hit; adicionar o `lapply(seq_len(8L), …)` dos
  `observeEvent(input$search_row_<k>)` chamando `do_pick`; no `do_pick`, trocar
  `updateSelectizeInput` por `updateTextInput`; adicionar `output$search_results
  <- renderUI`. `undo_btn` e o resto do server inalterados.
- [x] `www/styles.css` — bloco `.search-results` / `.search-result` /
  `.search-result--active` / `.search-empty` (reset de botão + fundo ativo
  `var(--surface-raised)`, só tokens de `DESIGN.md`); manter `.form-control`;
  atualizar o comentário de cabeçalho. Seletores `.selectize-*` deixados mortos
  (decisão de checkpoint pendente — ver Dev Notes). Sem `@import` / `url(http`.
- [x] `app.R` `tags$head` — `tags$script(HTML(...))` de ≤ 8 linhas: `keydown` em
  `#player_query`, `Enter` -> `.click()` na `.search-result--active` (fallback: 1ª
  `.search-result`). Nenhum `Shiny.*`. Gates anti-JS de `tests/smoke.R`
  afrouxados (removido `tags$script` do padrão; `Shiny.setInputValue` / `shinyjs`
  / `bslib` / `sass` / `includeCSS` seguem vetados).
- [x] `tests/smoke.R` — bloco `## --- story 16` (via `.s8_bake_server` +
  `shiny::testServer`): cada cenário da matriz. Migrar os call-sites de
  `player_choice` das stories 8 / 13 / 14 para `player_query`; trocar
  `"player_choice"` -> `"player_query"` nas listas de id. HTML de
  `search_results`: contém `<button`, `id="search_row_1"`, `class="search-result
  action-button`, `search-result--active` na 1ª linha, `aria-label="Registrar `;
  query sem match -> `class="search-empty"`. Estática de `app.R`: `resolve_player(`
  / `record_pick(` / `undo_pick(` / `recommend_players(` uma vez cada; nenhum
  `selectizeInput` / `updateSelectizeInput` / `player_choice`; nenhum
  `bslib|sass|includeCSS|shinyjs|Shiny.setInputValue`; exatamente um `tags$script`
  e seu corpo sem `Shiny.` / `fetch(` / `http`; nenhum símbolo de rede / RNG.
  `www/styles.css` ausente -> a
  lista de resultados ainda monta e o clique ainda registra (mesmo padrão
  swap-and-restore das stories 9 / 11 / 12 / 15).

**Acceptance Criteria:**
- Given `make test` sem rede, when executado, then status 0 com os blocos das
  stories 1–16; as linhas "story 8/9/10/11/12/13/14/15 offline checks OK"
  continuam e os asserts de equivalência `recs()` ↔ `recommend_players()`
  (8c / 8e) passam sem edição de lógica.
- Given `Rscript -e 'source("app.R"); cat(as.character(htmltools::renderTags(ui)$html))'`,
  when revisado, then os `id` `status_strip`, `draft_feedback`, `recs_note`,
  `recs_table`, `recs_pos_filter`, `roster_table`, `recent_picks_table`,
  `available_table`, `player_query`, `search_results`, `draft_btn`, `undo_btn`,
  `pos_filter` presentes; `player_choice` ausente; sem erro.
- Given `grep -cE "resolve_player\(|record_pick\(|undo_pick\(|recommend_players\(" app.R`,
  when revisado, then `resolve_player` 1, `record_pick` 1, `undo_pick` 1,
  `recommend_players` 1.
- Given `grep -nE "selectize|player_choice" app.R`, when revisado, then vazio.
- Given `git diff app.R`, when revisado, then as mudanças são só: swap do input,
  remoção do `observe` de selectize, reactive `search_hits`, `draft_btn`
  repontado, `lapply` dos `search_row_<k>`, `renderUI` `search_results`,
  `updateTextInput` no `do_pick`, e o `tags$script` do `Enter` no `tags$head`;
  nada em `recs` / `recs_view` / `view` / `undo_btn` / `commit_state` /
  `record_pick` / `undo_pick` / `save_state` ou nos demais `render*`.

## Spec Change Log

- 2026-09-03, checkpoint 1 (aprovação): a decisão "Wiring de `Enter`" foi
  resolvida pelo humano como **Opção A** — um `tags$script` `keydown` mínimo (≤ 8
  linhas, sem `Shiny.*`) no `tags$head` e o afrouxamento pontual do gate anti-JS
  `tests/smoke.R:3021`. O item saiu de "Ask First" para "Always"; a matriz ganhou
  a linha do `Enter`; a task do script deixou de ser condicional. Estado ruim
  evitado: implementar sem `Enter` (contra a `stories.yaml`, que pede "mouse +
  type-to-filter + Enter now") ou implementar `Enter` com um input binding
  custom / `Shiny.setInputValue` (contra o adapter fino). KEEP: o script é a única
  exceção ao veto de `tags$script`; `Shiny.setInputValue` / `shinyjs` seguem
  vetados e a story 22 reusa esse mesmo script.

## Design Notes

- **Por que `textInput` + `renderUI` de `<button>` e não um input binding
  próprio.** O binding de `action-button` do Shiny já entrega o clique via
  `input$search_row_<k>` sem `Shiny.setInputValue`; o `<button>` também dá
  `Enter` / `Espaço` nativos quando a linha está focada. É exatamente o padrão
  que a story 14 usou na linha-candidato — nenhum matcher, fórmula ou binding
  novo. A promoção para `role="combobox"/"listbox"/"option"` e a navegação por
  setas são explicitamente das stories 22 (C1) e 23 (C3).
- **`resolve_player` server-side por tecla é aceitável.** O
  `selectizeInput(server = TRUE)` atual já fazia um round-trip por tecla;
  `resolve_player` é O(n) de operações de string sobre ≤ ~320 disponíveis
  (sub-ms). O guardrail de performance mira `recommend_players()` (~286 ms), que
  `search_hits` nunca toca.
- **`Enter`.** DESIGN.md §"Campo de busca + autocomplete": "o resultado que
  `Enter` registrará usa `{components.candidate-active.background}` e contorno de
  foco". EXPERIENCE.md §Interaction Primitives coloca ↑/↓/`Enter`/`Esc` no
  autocomplete. A story 16 entrega o `Enter` no resultado destacado (Opção A do
  checkpoint: um `tags$script` `keydown` de ≤ 8 linhas, sem `Shiny.*`); ↑/↓ e as
  roles ARIA ficam para as stories 22/23, que expandem esse mesmo script.
- Exemplo de linha renderizada (topo):
  `<button type="button" id="search_row_1" class="search-result action-button search-result--active" aria-label="Registrar Nico Collins"> <span class="name">Nico Collins</span> <span class="pos">WR HOU</span> </button>`

## Verification

**Commands:**
- `make test` — status 0; inclui uma linha "story 16" e mantém as linhas
  "story 8/9/10/11/12/13/14/15 offline checks OK".
- `Rscript -e 'source("app.R"); cat(as.character(htmltools::renderTags(ui)$html))'`
  — `player_query` e `search_results` presentes, `player_choice` ausente, sem erro.
- `grep -cE "resolve_player\(|recommend_players\(" app.R` — 1 cada.
- `grep -nE "\.selectize|selectizeInput" app.R www/styles.css` — nada em `app.R`
  (em `styles.css` conforme a decisão do checkpoint).
- `grep -c "tags\$script" app.R` — 1; e `grep -nE "Shiny\.|fetch\(|http" app.R`
  não casa dentro do corpo do script.

**Manual checks:**
- `make app`: digitar parte de um nome mostra resultados com nome / posição /
  time NFL; a 1ª linha tem fundo elevado; clicar em qualquer linha registra o
  jogador e limpa o campo; **Registrar** com uma query de 1 resultado registra
  esse jogador; query sem match mostra "Nenhum jogador disponível corresponde à
  busca."; (Opção A) `Enter` no campo registra o 1º resultado; remover
  `www/styles.css` e recarregar — sem erro de servidor, clique ainda funciona.
- **Reset do valor do campo após o pick** é verificação manual: `shiny::testServer`
  não reflete `updateTextInput` de volta em `input$player_query`, então o smoke
  só pina a posição da chamada em `do_pick` (entre `commit_state(st)` e o
  `feedback()` de sucesso). No `make app`, registrar um jogador deve esvaziar o
  campo de busca.
- Query só com espaços (`"   "`) mostra o container vazio, não a linha
  "Nenhum jogador disponível corresponde à busca.".

## Dev Notes

- **`.selectize-*` em `www/styles.css`: deixados mortos** (não removidos). Era um
  item "Ask First" sem checkpoint registrado; a opção conservadora e reversível
  é não tocar CSS que ainda funciona. O comentário de cabeçalho os marca como
  história. Decisão de humano ainda pendente se devem ser removidos.
- **Gates anti-JS de `tests/smoke.R`: os seis foram afrouxados, não só o um.** O
  Code Map cita `:3021` (bloco s13), mas `tags$script` também é vetado nos gates
  idênticos dos blocos s10/s11/s12/s14/s15 sobre o mesmo `app.R` — todos
  falhariam em `make test` assim que o script do `Enter` entrasse. Removido
  `tags$script` do padrão nos seis; `Shiny.setInputValue` / `shinyjs` / `bslib` /
  `sass` / `includeCSS` seguem vetados em todos. A asserção positiva (exatamente
  um `tags$script`, corpo sem `Shiny.` / `fetch(` / rede) fica no bloco s16.
- **`s13c` (já-escolhido) e `s13e2` (id inválido) migrados por semântica, não só
  call-site.** Com a busca, digitar o nome de um jogador já draftado devolve
  `resolve_player()` `"none"` e um id inexistente nunca chega a `record_pick()`.
  `s13c` agora exercita o ramo "já escolhido" de `do_pick()` por chamada direta
  (como `s14d` já fazia) e lê `feedback()` em vez da região renderizada (uma
  chamada nua de `do_pick` não dispara flush do `renderUI` no `testServer`).
  `s13e2` vira uma query sem match exercitando o ramo de seleção vazia; o ramo
  genérico "Pick não registrado:" de `do_pick` segue coberto por `s13e3`
  (falha de `save_state()`).
- **`output$search_results`** faz o join de `nfl_team` a partir de
  `snapshot$players` (equivalente a ler `res$players$nfl_team`, que já é um
  subconjunto de `snapshot$players`) para casar o padrão do status strip /
  `recs_table` e o caso "coluna ausente -> só pos".

### Patches da revisão adversarial (2026-09-03, sem loopback de spec)

1. Query só-espaços: `search_hits` e o guard de container vazio do `renderUI`
   usam `trimws(input$player_query %||% "")`, então `"   "` -> container vazio.
2. Script `keydown`: guardas `if (e.isComposing || e.keyCode === 229 || e.repeat)
   return;` no topo (Enter de composição IME; auto-repeat de tecla presa).
   Continua DOM puro, sem `Shiny.*`.
3. `.search-results` ganhou `max-height: 13rem` + `overflow-y: auto` (≈ 8 linhas)
   — a lista cheia não empurra **Registrar** / **Undo**.
4. `tests/smoke.R`: 16h pina o corpo do script (`player_query`,
   `.search-result--active`, `.search-result`, `.click(`, `preventDefault`,
   `isComposing`, `e.repeat`) e a posição do clear do campo; 16g2 exercita
   `search_row_4` sob query ambígua (lado in-range do guard `k <= nrow(h)`); 16e
   cobre query só-espaços.
5. `app.R`: `search_result_cap <- 8L` local em `server()`, usado por
   `seq_len(search_result_cap)` e `min(search_result_cap, nrow(...))`.

## Suggested Review Order

**Matcher e reactive (o design)**

- Ponto de entrada: o único `resolve_player()` do `app.R`, sobre `view()$available` + snapshot, `trimws()` na query; nenhum segundo matcher.
  [`app.R:223`](../../../../app.R#L223)

- `search_result_cap <- 8L`: uma constante para a contagem de observers e o cap de render — não podem divergir.
  [`app.R:222`](../../../../app.R#L222)

**Caminho de pick único**

- `draft_btn` repontado: registra o 1º hit de `search_hits()` pelo mesmo `do_pick()`.
  [`app.R:268`](../../../../app.R#L268)

- Os 8 observers `search_row_<k>` resolvem o jogador por rank e caem no mesmo `do_pick()`; `lapply` + `force()`.
  [`app.R:281`](../../../../app.R#L281)

- `do_pick()` no sucesso limpa o campo via `updateTextInput` (era `updateSelectizeInput`).
  [`app.R:248`](../../../../app.R#L248)

**A lista de resultados (a view)**

- `renderUI` puro sobre `search_hits()`: query vazia/só-espaços -> container vazio; `"none"` -> uma linha `.search-empty`; senão ≤ 8 `<button>` com nome / pos / time NFL, linha 1 `--active`.
  [`app.R:417`](../../../../app.R#L417)

**Wiring de `Enter` (checkpoint Opção A)**

- `tags$script` de keydown puro (sem `Shiny.*`): guardas IME/repeat, e `Enter` em `#player_query` -> `.click()` na `.search-result--active`.
  [`app.R:46`](../../../../app.R#L46)

**CSS**

- Bloco `.search-result*`: reset de `<button>` como `button.candidate`, `--active`/hover/foco em `--surface-raised`, `max-height` + scroll para não empurrar os botões.
  [`styles.css:510`](../../../../www/styles.css#L510)

**Testes**

- Bloco `## --- story 16` (16a–16i): unique/ambígua/sem-match/vazia, clique in-range e fora de alcance, `recs()` intacto por tecla, pins do script Enter, `styles.css` ausente.
  [`smoke.R:3644`](../../../../tests/smoke.R#L3644)

- Migração dos call-sites de `player_choice` das stories 8 / 13 / 14 para `player_query` + helper `.s16_query_for()`.
  [`smoke.R:1656`](../../../../tests/smoke.R#L1656)
