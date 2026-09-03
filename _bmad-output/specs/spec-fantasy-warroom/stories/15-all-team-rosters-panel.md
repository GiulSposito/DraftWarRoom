---
title: 'Painel de rosters de todos os times (story 15)'
type: 'feature'
created: '2026-09-03'
status: 'done'
review_loop_iteration: 1
baseline_commit: '28dfed48bf0d5ec1a4e0cb4322e78f8fa17557ca'
context:
  - '/Users/gsposito/Projects/football/DraftWarRoom/_bmad-output/specs/spec-fantasy-warroom/SPEC.md'
  - '/Users/gsposito/Projects/football/DraftWarRoom/_bmad-output/specs/spec-fantasy-warroom/functional-core.md'
  - '/Users/gsposito/Projects/football/DraftWarRoom/AGENTS.md'
  - '/Users/gsposito/Projects/football/DraftWarRoom/docs/design/DESIGN.md'
  - '/Users/gsposito/Projects/football/DraftWarRoom/docs/design/EXPERIENCE.md'
  - '/Users/gsposito/Projects/football/DraftWarRoom/_bmad-output/specs/spec-fantasy-warroom/stories/12-grouped-roster-panel.md'
---

<frozen-after-approval reason="human-owned intent — do not modify unless human renegotiates">

## Intent

**Problem:** O terminal tem o comando `/teams`, que imprime o roster de todos os
12 times do draft; `app.R` só mostra o roster do operador (story 12). Durante o
draft ao vivo o operador não consegue conferir, na war room Shiny, o que os
adversários já montaram — informação que a `EXPERIENCE.md` (§Information
Architecture) descreve como "outros rosters são acessíveis no board" e que
`scripts/draft.R` já expõe.

**Approach:** Fatorar o corpo do `renderUI` de `output$roster_table` (story 12)
para uma função local `roster_panel_ui(roster, league, aria_label)` no escopo do
`server`, sem mudar o markup do painel do operador. Adicionar
`output$all_rosters_table` — um `renderUI` que, para cada time em
`state()$team_order`, monta um cartão `.team-roster` (cabeçalho com o nome do
time + a tag textual "VOCÊ" no time do operador) contendo o mesmo painel de três
grupos (Titulares / FLEX / Banco) produzido por `roster_panel_ui()` a partir de
`derive_draft_view()$rosters[[time]]`. O conjunto vai dentro de um
`<details class="all-rosters" open>` nativo (colapsável sem JavaScript) numa
`fluidRow` de largura total no fim da página. Somente leitura, derivado a cada
render. CSS novo em `www/styles.css`, tokens verbatim de `DESIGN.md`, incluindo
a primeira media query do arquivo para o layout estreito ao lado da ESPN.

## Boundaries & Constraints

**Always:**
- **Um só caminho de slotting.** `roster_panel_ui()` é a única função que compõe
  um painel de roster; ela usa `roster_slots()` de `R/recommendation.R`
  exatamente como a story 12 (fonte única para QB/RB/WR/TE/FLEX; K e DST puxados
  do `BENCH` para as vagas dedicadas por identidade de `pos`, maior `val` —
  `vor`, fallback `points` — primeiro; excedente fica no banco). Nenhuma segunda
  lógica de slot em `app.R`. `roster_slots` / `recommend_players` não são
  redefinidos.
- **Markup do painel do operador inalterado.** Após a fatoração,
  `output$roster_table` chama `roster_panel_ui(view()$rosters[[st$user_team]],
  st$league, "Roster do operador")` e produz HTML byte-a-byte igual ao atual: os
  blocos de teste da story 8 (`(8e)`, cross-check `class="roster-panel"`) e da
  story 12 continuam passando sem edição.
- **Ordem e nomes dos times** vêm de `state()$team_order` — a mesma sequência
  que `derive_draft_view()$rosters` nomeia e que o `/teams` do terminal percorre.
  Um time sem picks renderiza o painel todo em "— aberto" / "—".
- **Derivação por render, zero recomputação.** Todos os rosters vêm da única
  chamada de `derive_draft_view()` já no `reactive` `view`. `recommend_players(`
  continua aparecendo exatamente 1× no código de `app.R`. O painel não lê
  `recs()` nem recalcula `vor` / lineup / recomendação.
- **Marcação do time do operador** por rótulo textual ("VOCÊ") além de qualquer
  estilo — `DESIGN.md` §Colors: estado nunca só por cor. `identical(time,
  st$user_team)` decide.
- **Colapso.** O `<details class="all-rosters" open>` abre por padrão; o
  operador colapsa manualmente para recuperar altura ao lado da ESPN (sem
  JavaScript, sem `shinyjs`). Em largura estreita o CSS passa a grade para uma
  coluna e limita a altura com rolagem vertical interna. Este é o padrão de
  colapso que a story 15 fixa; a reestruturação em regiões workspace/wide é da
  story 17 (B1).
- **Posição no layout:** uma `fluidRow(column(12, ...))` nova, depois da linha
  "Disponíveis" — o tier de board/rosters adversários fica abaixo do núcleo
  operacional (estado, recomendações, roster do operador), conforme `DESIGN.md`
  §Layout & Spacing.
- `app.R` segue adapter fino: sem pacote novo no `renv.lock`, sem
  `bslib`/`sass`/`includeCSS`/`shinyjs`/`tags$script`/`Shiny.setInputValue`, sem
  símbolo de rede ou RNG. CSS só em `www/styles.css`, sem `@import` / asset
  remoto. Os `outputId` / `inputId` das stories 8–14 permanecem; o novo é
  `all_rosters_table`.

**Ask First:**
- Colocar o painel em outro lugar que não uma `fluidRow` de largura total no fim
  (ex.: coluna lateral, aba) — isso antecipa a story 17.
- Mostrar números (pontos / vor / ocupação "2/9") ou o melhor lineup nos painéis
  dos adversários — story 19.
- Introduzir uma dependência ou um segundo `<details>` por time (um accordion
  por time) em vez do único `<details>` do painel inteiro.

**Never:**
- Board em grade, painel de inspeção, undo redesenhado, combobox de busca,
  atalhos de teclado, `aria-live` reativo (stories 16, 18–23).
- Re-chamar `recommend_players()` ou `derive_draft_view()` por time / por
  render extra.
- Rede, `ffanalytics`, leitura de `yaml` nova, mudança em `state/draft.rds` /
  `data/projections.rds`, Shiny modules, JavaScript próprio, nova função em
  `R/`.
- Mudar `roster_slots()` / `derive_draft_view()` ou qualquer coisa no core `R/`.

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| Meio de draft, vários times com picks | `state()$picks` não vazio, 12 times em `team_order` | 12 cartões `.team-roster` na ordem de `team_order`, cada um com um `.roster-panel` de 3 grupos; total de `.roster-row` por cartão = `sum(state$league$roster)` (mais excedente de banco) | N/A |
| Time do operador | `st$user_team` = "Team 01" | o cartão do "Team 01" traz a tag textual "VOCÊ" no cabeçalho e a classe `team-roster--you`; os outros 11 não | N/A |
| Draft não iniciado | `nrow(state()$picks) == 0` | 12 cartões, cada painel todo em "— aberto" (titulares/FLEX) e "—" (banco); nenhuma linha `.name` preenchida; sem erro | página funcional |
| Roster adversário parcial | um time com QB + 2 RB + 1 K | painel daquele time: `QB`/`RB1`/`RB2`/`K` preenchidos, resto "— aberto"; Banco 6 linhas "—" (mesma regra da story 12) | N/A |
| `nfl_team` ausente do snapshot | `snapshot$players$nfl_team` `NULL` | meta das linhas preenchidas = `pos` puro, nunca a string `"NA"` | N/A |
| Operador colapsa o painel | clique no `<summary>` | `<details>` fecha, os cartões somem da vista, o resto da página intacto (comportamento nativo, sem reativo) | N/A |
| `www/styles.css` ausente em runtime | arquivo removido | `output$all_rosters_table` ainda monta os 12 cartões, sem erro de servidor | página funcional |

</frozen-after-approval>

## Code Map

- `app.R:82` — `fluidRow(column(6, h4("Seu roster"), uiOutput("roster_table")),
  column(6, h4("Picks recentes"), tableOutput("recent_picks_table")))`. **Não
  mudar.**
- `app.R:86-88` — `fluidRow(column(12, h4("Disponíveis"),
  tableOutput("available_table")))`. **Adicionar depois** uma `fluidRow` de
  largura total cujo `column(12, ...)` contém um
  `tags$details(class = "all-rosters", open = NA,
  tags$summary(tags$h4("Rosters dos times")), uiOutput("all_rosters_table"))`.
  O `<h4>` fica **dentro** do `<summary>` — o `<summary>` é ao mesmo tempo o
  controle de disclosure e o título da seção (sem `h4` solto duplicando o
  rótulo). O `<details>` / `<summary>` ficam na árvore estática do `ui` (não no
  `renderUI`), para que o estado aberto/fechado do DOM sobreviva a cada
  re-render do output — o operador colapsa uma vez e fica colapsado durante o
  draft. `open = NA` renderiza `<details … open>` (aberto por padrão).
- `app.R:161` — `view <- reactive({ derive_draft_view(state(), snapshot) })`.
  Única fonte dos rosters — reusar `view()$rosters`. **Não mudar.**
- `app.R:448-541` — `output$roster_table <- renderUI({...})` (story 12).
  **Fatorar** o corpo (de `rc <- league$roster` até o `tags$div(class =
  "roster-panel", ...)`) para uma função local `roster_panel_ui <-
  function(roster, league, aria_label) {...}` definida no escopo do `server`
  (ex.: logo acima de `output$roster_table`). O `renderUI` vira
  `output$roster_table <- renderUI({ st <- state();
  roster_panel_ui(view()$rosters[[st$user_team]], st$league, "Roster do
  operador") })`. O `aria-label` do `<div class="roster-panel">` passa a vir do
  parâmetro (default preserva "Roster do operador"). Helpers internos
  (`slot_labels`, `filled_row`, `empty_row`, `fill_rows`, `group`) e o laço de
  K/DST ficam dentro de `roster_panel_ui()`, sem alteração de comportamento.
- `app.R` (novo) — `output$all_rosters_table <- renderUI` que faz `ros <-
  view()$rosters` e `lapply(seq_along(st$team_order), function(i) {...})`: para
  cada `i`, `tm <- st$team_order[i]`; `nm <- if (is.na(tm) || !nzchar(tm))
  sprintf("Time %d", i) else tm` (fallback — nunca imprime `NA`); `you <-
  !is.na(tm) && identical(tm, st$user_team)`; monta `<div class="team-roster[
  team-roster--you]">` com um `.team-roster-head` (`<span class="team-roster-name">nm</span>`
  + `<span class="team-roster-you">VOCÊ</span>` quando `you`) e
  `roster_panel_ui(ros[[i]], st$league, paste("Roster", nm))`. O `renderUI`
  devolve **apenas** `tags$div(class = "all-rosters-grid", cards)` — o
  `<details>` que a envolve vive no `ui`. `ros` é indexado por **posição**
  (`ros[[i]]`), não por nome (`ros[[tm]]`): `derive_draft_view()` monta
  `$rosters` com `lapply(seq_along(state$team_order), …)`, então a ordem casa
  `team_order` 1-a-1 e um nome de time em branco / `NA` (state legado) não
  quebra o painel inteiro. Sem chamada de core além de ler `view()$rosters`.
- `app.R:21` — `%||%` disponível.
- `R/recommendation.R:177-202` — `roster_slots(roster, league)` →
  `data.frame(player_id, slot)`, `slot` ∈ `QB RB WR TE FLEX BENCH`; K/DST voltam
  `BENCH`. 0 linhas para roster `NULL`/0 linhas. **Não alterar** — reusada como
  na story 12.
- `R/core.R:410-419` — `derive_draft_view()` monta `$rosters` nomeado por
  `state$team_order`, cada um as linhas do snapshot dos jogadores draftados
  pelo time, em ordem de pick; time sem picks → data.frame de 0 linhas (não
  `NULL`).
- `scripts/draft.R:228-229` — `else if (cmd == "/teams") { for (tm in
  state$team_order) .warroom_print_roster(view$rosters[[tm]], tm, say) }` — o
  comando de terminal que este painel espelha (mesma iteração de
  `team_order`).
- `www/styles.css:484-562` — bloco `.roster-panel` / `.roster-group` /
  `.roster-row` (story 12). **Reusado como está** pelos cartões. **Inserir
  depois** o bloco da story 15: `.all-rosters` (contêiner do `<details>`),
  `.all-rosters > summary` (só `padding` + `cursor: pointer`),
  `.all-rosters > summary > h4` (`display: inline`, `margin: 0`,
  `typography.label` / `--ink-muted` — o rótulo real), `.all-rosters > summary:focus-visible`
  (anel `2px var(--focus)`, como `button.candidate:focus-visible`),
  `.all-rosters-grid` (grade `repeat(auto-fill, minmax(220px, 1fr))` com
  `gap: var(--space-2)`), `.team-roster`, `.team-roster-head` (só `border-bottom`
  — **sem** `background: var(--surface-raised)`: essa cor sinaliza superfície
  ativa/elevada, não deve virar chrome permanente em 12 cabeçalhos),
  `.team-roster-name` (`typography.data`), `.team-roster-you` (pílula invertida:
  `background: var(--ink)`, `color: var(--surface)`, `border-radius:
  var(--radius-full)` — `DESIGN.md`: pílulas só para badges pequenos; afordância
  real, não texto solto), `.team-roster--you` (`border-color: var(--ink)` — a
  borda é o par não textual da tag), `.team-roster .roster-panel` (zera a
  borda/raio externa da story 12). **Adicionar** ao `:root` o token
  `--radius-full: 9999px` (`DESIGN.md` `rounded.full`, ainda não usado no
  arquivo). A **marca do operador** nunca usa `var(--focus)`: `DESIGN.md`
  §Colors reserva o azul para foco de teclado / resultado selecionado. O cap de
  altura da grade aberta — `.all-rosters[open] .all-rosters-grid { max-height:
  80vh; overflow-y: auto; }` — fica **fora** de qualquer media query (aplica em
  qualquer largura). **Adicionar** a primeira `@media (max-width: 900px)` do
  arquivo com só `.all-rosters-grid { grid-template-columns: 1fr; }` e um cap
  mais apertado (`max-height: 60vh`). Tokens de cor / spacing / radius / type
  verbatim de `DESIGN.md`; dimensões de layout cruas (`220px`, `900px`, `vh`)
  seguem a prática já existente no arquivo.
- `www/styles.css:1-55` — comentário de cabeçalho: **atualizar** com o parágrafo
  da story 15 (painel de todos os rosters; primeira media query).
- `tests/smoke.R:1760-1913` — bloco story 8; `:1782` faz o cross-check de
  `output$roster_table` casando `class="roster-panel"`. **Segue válido** (markup
  do operador inalterado).
- `tests/smoke.R:2446-2760` — bloco story 12 (`.s12_state`, `.s12_render`,
  `.s12_group`, `.s12_filled`, `.s12_empty`, `s12_name`, `s12_nfl`,
  `s12_open`/`s12_dash`/`s12_mid`). **Reusar** os helpers; `.s12_state` fabrica
  o roster do "Team 01" e preenche os demais times com fillers — serve de
  fixture multi-time. Para o caso `user_team != "Team 01"`, montar o state
  direto: `new_draft(snap, team_order, "Team 07", league = league)` +
  ~20 `record_pick()` sequenciais (o snake dá a "Team 07" os overalls 7 e 18).
- `R/core.R` — `derive_draft_view()` monta `$rosters` por
  `lapply(seq_along(state$team_order), …)`; ordem = `team_order`. `.s15_card()`
  no teste fatia um cartão pela abertura da `<div class="team-roster…">` (não
  pelo `<span class="team-roster-name">`, senão a classe `--you` do `<div>` fica
  fora da fatia e o check negativo do cartão vira vácuo).
- `tests/smoke.R:3300` — `cat("story 14 offline checks OK ...")`. **Inserir** o
  bloco `## --- story 15` logo depois, antes do guard de `prepare.R` (`:3302`).
- `tests/smoke.R:1634-1657` — `.s8_bake_server`, `.strip_html`, `.html_count`,
  `.s11_count` (reusar).

## Tasks & Acceptance

**Execution:**
- [x] `app.R` — (1) fatorar `roster_panel_ui(roster, league, aria_label =
  "Roster do operador")` do `renderUI` de `roster_table` (corpo idêntico, só o
  `aria-label` do `<div class="roster-panel">` passa a vir do parâmetro);
  reapontar `output$roster_table` para `roster_panel_ui(view()$rosters[[st$user_team]],
  st$league, "Roster do operador")`. (2) `output$all_rosters_table <- renderUI`
  que percorre `seq_along(state()$team_order)`, monta um `.team-roster` por time
  (cabeçalho com nome + tag "VOCÊ" quando `identical(tm, st$user_team)`), chama
  `roster_panel_ui(view()$rosters[[i]], st$league, paste("Roster", tm))` —
  indexação **por posição** — e devolve **só** `tags$div(class =
  "all-rosters-grid", cards)`. (3) na UI, depois da linha "Disponíveis", uma
  `fluidRow(column(12, h4("Rosters dos times"), tags$details(class =
  "all-rosters", open = NA, tags$summary("Todos os rosters"),
  uiOutput("all_rosters_table"))))` — o `<details>` fica na árvore estática do
  `ui`. Nada mais no `server` muda; `recommend_players(` segue 1×;
  `derive_draft_view(` segue 1× (o `view` reactive).
- [x] `www/styles.css` — atualizar o comentário de cabeçalho; adicionar o bloco
  `.all-rosters` / `.all-rosters > summary` / `.all-rosters-grid` /
  `.team-roster` / `.team-roster-head` / `.team-roster-name` /
  `.team-roster-you` / `.team-roster--you` / `.team-roster .roster-panel`. A
  marca do operador usa `var(--ink)` (nunca `var(--focus)`). O cap
  `.all-rosters[open] .all-rosters-grid { max-height: 80vh; overflow-y: auto; }`
  fica **fora** de media query; a primeira `@media (max-width: 900px)` do
  arquivo tem só `grid-template-columns: 1fr` + `max-height: 60vh`. Tokens de
  cor/spacing/radius/type verbatim de `DESIGN.md`, sem `@import` / `url(http`.
- [x] `tests/smoke.R` — bloco `## --- story 15` (via `.s8_bake_server` +
  `shiny::testServer` + `.strip_html`), um teste por linha da matriz de I/O,
  mais: `.s15_card()` fatia o cartão pela abertura da `<div class="team-roster…">`
  (para o check negativo do `--you` não ser vácuo); a asserção do `<details>` é
  feita no `ui` estático e casa `<details class="all-rosters" open>` **com** o
  ` open>` (uma troca `open = NA` → `open = NULL` tem que falhar); caso extra com
  `user_team = "Team 07"` — a tag "VOCÊ" cai no cartão do "Team 07", a grade
  segue com 12 cartões em ordem de `team_order`. Estática: `id="all_rosters_table"`
  e `<details class="all-rosters" open>` no `ui`; ids das stories 8–14 intactos;
  `app.R` sem `bslib|sass|includeCSS|shinyjs|tags$script|Shiny.setInputValue`
  novo, sem símbolo de rede/RNG, `roster_slots`/`recommend_players`/
  `derive_draft_view` não redefinidos, `recommend_players(` 1×,
  `derive_draft_view(` 1×, `roster_slots(` ≤ 1×; `www/styles.css` com
  `.all-rosters` / `.all-rosters-grid` / `.team-roster` / `.team-roster--you`,
  `@media (max-width: 900px)` com `grid-template-columns: 1fr`, sem asset
  remoto, e `.team-roster--you` sem `var(--focus)`.

**Acceptance Criteria:**
- Given `make test` sem rede, when executado, then status 0 com os blocos das
  stories 1–15; as linhas "story 8/9/10/11/12/13/14 offline checks OK"
  continuam e os cross-checks de `output$roster_table` de `(8e)` e o bloco
  story 12 passam sem edição.
- Given `Rscript -e 'source("app.R");
  cat(as.character(htmltools::renderTags(ui)$html))'`, when revisado, then
  `id="all_rosters_table"` está presente e seguem presentes `status_strip`,
  `draft_feedback`, `recs_table`, `recs_pos_filter`, `recs_note`,
  `roster_table`, `recent_picks_table`, `available_table`, `player_choice`,
  `draft_btn`, `undo_btn`, `pos_filter`.
- Given `git diff app.R`, when revisado, then as mudanças são só: a extração de
  `roster_panel_ui` + o reaponte de `output$roster_table`, o novo
  `output$all_rosters_table` e a nova `fluidRow` (`h4` + `<details>` +
  `uiOutput`); nada em
  `recs`/`view`/`recs_view`/`do_pick`/`commit_state`/`record_pick`/`undo_pick`/
  `save_state` ou nos demais `render*`.
- Given `grep -c "roster_slots(" app.R`, when comparado ao estado anterior,
  then a contagem não aumenta além de uma chamada dentro de
  `roster_panel_ui()` (a mesma que a story 12 já fazia).
- Given o `ui` renderizado, when inspecionado, then contém
  `<details class="all-rosters" open>` (o `<details>` é estático, aberto por
  padrão) e o `uiOutput("all_rosters_table")` está dentro dele.
- Given um pick registrado com o painel colapsado pelo operador, when o
  `output$all_rosters_table` re-renderiza, then só o conteúdo da
  `.all-rosters-grid` troca — o `<details>` (e seu estado fechado) permanece,
  porque vive no `ui`, não no `renderUI`.
- Given `.team-roster--you` em `www/styles.css`, when inspecionado, then não usa
  `var(--focus)` (o azul de foco fica reservado para foco de teclado).

## Spec Change Log

- **2026-09-03 — loopback 1 (bad_spec).** Revisão em 3 camadas (blind-hunter,
  edge-case-hunter, verification-gap) sobre o código já implementado.
  - **Colapso perdido a cada pick (blind-hunter, verification-gap).** O Code Map
    e a Task mandavam o `renderUI` de `output$all_rosters_table` emitir o
    `tags$details(...)`. Como o Shiny recria o DOM do output a cada re-render, o
    `<details>` reabria em todo pick e o "operador colapsa manualmente" da
    intent frozen ficava inútil no draft. Nenhum teste checava o atributo
    `open`. Amendado: o `<details>` / `<summary>` movem para a árvore estática
    do `ui` (com `h4("Rosters dos times")` como título da seção, como toda seção
    irmã); o `renderUI` monta só a `.all-rosters-grid`. Novo AC + teste casando
    `<details class="all-rosters" open>` **com** o ` open>` e um AC sobre o
    estado colapsado sobreviver a um pick. Known-bad evitado: painel de scouting
    que reabre sozinho a cada pick durante o draft ao vivo.
  - **`ros[[tm]]` quebra com nome de time em branco/`NA` (edge-case-hunter).**
    Amendado: indexar `view()$rosters` por posição (`[[i]]` sobre
    `seq_along(team_order)`), já que `derive_draft_view()` monta a lista na
    mesma ordem. Known-bad evitado: um `state/draft.rds` legado com um único
    `""`/`NA` em `team_order` (que passa o `.warroom_validate_state()`)
    derrubava o painel inteiro com "subscript out of bounds".
  - **`.team-roster--you` usava `var(--focus)` (blind-hunter).** O Code Map
    permitia `var(--focus)` na borda de destaque; `DESIGN.md` §Colors reserva o
    azul para foco de teclado / resultado selecionado, e uma borda azul
    permanente lê como foco preso. Amendado para `var(--ink)` (borda e tag), com
    AC de teste.
  - **Cap de altura só no layout estreito (blind-hunter).** Amendado: o cap
    `max-height` + `overflow-y: auto` na grade aberta sai da `@media` e vale em
    qualquer largura (viewport larga e baixa também precisa); a `@media` fica só
    com a troca para uma coluna.
  - **Testes fracos (blind-hunter, verification-gap).** `.s15_card()` fatiava a
    partir do `<span class="team-roster-name">`, deixando a classe `--you` do
    `<div>` fora da fatia (check negativo do cartão virava vácuo); nenhum
    fixture usava `user_team != "Team 01"`. Amendado: `.s15_card()` fatia pela
    abertura da `<div class="team-roster…">`; caso extra com `user_team =
    "Team 07"`; asserções de contagem para `derive_draft_view(` (== 1) e
    `roster_slots(` (≤ 1) em `app.R`.
  - **KEEP (sobrevive à re-derivação):** a extração de `roster_panel_ui(roster,
    league, aria_label)` do corpo do `renderUI` da story 12, markup do operador
    byte-a-byte idêntico (testes das stories 8/12 como rede); um único
    `<details>` para o painel todo (não um por time); iterar `team_order` e
    espelhar o `/teams` do terminal; um só `derive_draft_view()` (reusar o
    `view` reactive); a estrutura de cartão `.team-roster` / `.team-roster-head`
    / `.team-roster-name` / `.team-roster-you` e a tag textual "VOCÊ"; o bloco
    CSS `.all-rosters` / `.all-rosters-grid` e a primeira `@media` do arquivo
    para a coluna única; o comentário de cabeçalho do CSS; a estrutura do bloco
    de teste (`.s15_render`, `.s15_card`, casos 15a–15i) reusando os helpers da
    story 12 e `.s12_state` como fixture multi-time; o swap-and-restore de CSS
    ausente; a `fluidRow` de largura total no fim, abaixo de "Disponíveis".
  - **Registrado em `deferred-work.md`:** empurrar a colocação de K/DST nas
    vagas dedicadas de Titulares para dentro de `roster_slots()` no core, para
    haver de fato um único caminho de slotting (hoje a regra K/DST vive só em
    `app.R` e agora roda para os 12 times).

## Design Notes

- **Por que fatorar em vez de duplicar.** A story 12 construiu toda a lógica de
  slot/rótulo/ordenação dentro do `renderUI` de `roster_table`. Reusar aquele
  markup para 12 times sem uma função comum significaria um segundo caminho de
  slotting — proibido por `AGENTS.md` e pela própria story 12. A extração é uma
  refatoração de formatação no adapter, reduz duplicação e mantém o painel do
  operador byte-a-byte idêntico (os testes das stories 8 e 12 são a rede de
  segurança).
- **Por que `<details>` nativo e por que ele fica no `ui`.** Dá colapso com
  `Enter`/clique e teclado nativos, zero JavaScript, sem antecipar o modelo de
  interação da story 22 nem a reestruturação de regiões da story 17. Mas o
  estado aberto/fechado de um `<details>` é DOM que o Shiny descarta a cada
  re-render do output que o contém — se o `<details>` fosse emitido pelo
  `renderUI`, todo pick reabriria o painel e o colapso manual seria inútil
  durante o draft. Por isso o `<details>` / `<summary>` vivem na árvore
  estática do `ui` e o `renderUI` monta só a `.all-rosters-grid` interna: o
  operador colapsa uma vez e fica colapsado dentro da sessão. Persistir a
  preferência entre reloads exigiria `localStorage` / JavaScript (proibido
  aqui); fica para a story 22 se necessário — o padrão da story 15 é abrir por
  padrão a cada sessão.
- **Um `<details>` para o painel inteiro, não um por time.** Doze accordions
  seriam ruído; a `EXPERIENCE.md` trata os rosters adversários como consulta
  ocasional, não fluxo principal. Grade multi-coluna quando há largura, uma
  coluna com rolagem quando estreito.
- **Marca do time do operador em `--ink`, não `--focus`.** Tag "VOCÊ" no
  cabeçalho como pílula invertida (`background: var(--ink)`, `color:
  var(--surface)`, `rounded.full`) — afordância de badge real, não texto solto —
  mais a borda `team-roster--you` em `var(--ink)` como par não textual (nunca o
  único sinal, `DESIGN.md` §Colors). Nada usa `var(--focus)`: uma borda azul
  permanente lê como anel de foco de teclado preso, e o `DESIGN.md` reserva o
  azul para foco / resultado selecionado. O `<summary>` ganha seu próprio anel
  `:focus-visible` de `2px var(--focus)`, como os controles das stories 11–14.
- **Custo por render.** 12 × `roster_slots()` (2 chamadas de
  `.warroom_sim_starter_ids()` cada) só re-dispara quando `state()` muda (um
  pick), não por foco/tecla — fora do guardrail de `recommend_players()` por
  keystroke da `RETROSPECTIVE.md` AV-4. Rosters mid-draft têm ≤ 15 jogadores;
  `roster_slots()` não varre o snapshot. Não cacheado: um pick por vez, custo
  baixo, sem ganho real em `bindCache`.
- **Indexação por posição.** `derive_draft_view()` monta `$rosters` com
  `lapply(seq_along(state$team_order), …)`, então `view()$rosters[[i]]` casa
  `state()$team_order[i]` 1-a-1. Usar `[[i]]` em vez de `[[tm]]` evita que um
  nome de time em branco ou `NA` num `state/draft.rds` legado (o
  `.warroom_validate_state()` só pega duplicatas, não um único `""`/`NA`)
  quebre o painel inteiro com "subscript out of bounds".
- Exemplo de cartão (adversário, meio de draft):
  `<div class="team-roster"><div class="team-roster-head"><span class="team-roster-name">Team 07</span></div><div class="roster-panel" role="group" aria-label="Roster Team 07">…3 grupos…</div></div>`

## Verification

**Commands:**
- `make test` — status 0; inclui uma linha "story 15" e mantém as linhas
  "story 8/9/10/11/12/13/14 offline checks OK".
- `Rscript -e 'source("app.R"); cat(as.character(htmltools::renderTags(ui)$html))'`
  — contém `id="all_rosters_table"`; todos os ids das stories 8–14 presentes;
  sem erro.
- `grep -nE "bslib|sass|includeCSS|shinyjs|tags\$script|Shiny\.setInputValue" app.R`
  — nenhuma ocorrência.
- `grep -c "recommend_players(" app.R` — 1.
- `Rscript -e 'source("app.R"); h <- as.character(htmltools::renderTags(ui)$html);
  cat(grepl("<details class=\"all-rosters\" open>", h, fixed = TRUE))'` — `TRUE`.

**Manual checks:**
- `make app`: uma seção "Rosters dos times" no fim da página com 12 cartões
  compactos (Titulares / FLEX / Banco), o do operador marcado "VOCÊ"; clicar no
  `<summary>` colapsa a seção; **registrar um pick com a seção colapsada — ela
  continua colapsada** (o `<details>` está no `ui`); estreitar a janela passa a
  grade para uma coluna com rolagem interna; registrar um pick atualiza o cartão
  do time que escolheu sem piscar o resto; remover `www/styles.css` e recarregar —
  sem erro de servidor.

## Suggested Review Order

**A função compartilhada de painel**

- Ponto de entrada: o corpo do `renderUI` da story 12 vira `roster_panel_ui(roster, league, aria_label)` — um só caminho de slotting/markup.
  [`app.R:465`](../../../../app.R#L465)

- `output$roster_table` reaponta para a função nova; markup do operador byte-a-byte idêntico (rede: testes 8/12).
  [`app.R:558`](../../../../app.R#L558)

**O painel de todos os times**

- `output$all_rosters_table`: um cartão por time em `team_order`, indexado por **posição** (`ros[[i]]`), devolve só a `.all-rosters-grid`.
  [`app.R:581`](../../../../app.R#L581)

- Fallback de nome em branco/`NA` → `"Time <i>"` (nunca imprime `NA` no cabeçalho nem no `aria-label`).
  [`app.R:586`](../../../../app.R#L586)

- O `<details open>` / `<summary><h4>` ficam na árvore estática do `ui` — o colapso manual sobrevive a cada re-render de pick.
  [`app.R:99`](../../../../app.R#L99)

**Estilo (tokens de DESIGN.md)**

- Bloco `.all-rosters`: `<details>`, grade `auto-fill`, cap de altura `[open]` fora da `@media`, primeira `@media` do arquivo (coluna única).
  [`styles.css:574`](../../../../www/styles.css#L574)

- Tag "VOCÊ" como pílula invertida (`--ink` / `--surface` / `rounded.full`); nada usa `--focus` (reservado a foco de teclado).
  [`styles.css:658`](../../../../www/styles.css#L658)

**Testes (offline)**

- Bloco `story 15`: helper `.s15_card` fatia um cartão pela abertura da `<div>`.
  [`smoke.R:3325`](../../../../tests/smoke.R#L3325)

- 15d: um adversário mostra os **próprios** jogadores (não os do operador) — mata a regressão de indexar por `user_team`; contagem de linhas por cartão.
  [`smoke.R:3383`](../../../../tests/smoke.R#L3383)

- 15i: `user_team = "Team 07"` — tag "VOCÊ" no cartão certo, K do adversário na vaga K de Titulares.
  [`smoke.R:3477`](../../../../tests/smoke.R#L3477)

- 15l: `team_order` com uma entrada em branco (passa a validação) — 12 cartões montam, sem "NA".
  [`smoke.R:3602`](../../../../tests/smoke.R#L3602)
