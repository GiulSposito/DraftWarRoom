---
title: 'Layout em grade de painéis (story 17, B1)'
type: 'feature'
created: '2026-09-03'
status: 'done'
review_loop_iteration: 0
baseline_commit: 'b588d60e7ae776c418bc1cdcce7fbb9be34e70f0'
context:
  - '/Users/gsposito/Projects/football/DraftWarRoom/_bmad-output/specs/spec-fantasy-warroom/SPEC.md'
  - '/Users/gsposito/Projects/football/DraftWarRoom/AGENTS.md'
  - '/Users/gsposito/Projects/football/DraftWarRoom/docs/design/DESIGN.md'
  - '/Users/gsposito/Projects/football/DraftWarRoom/docs/design/EXPERIENCE.md'
  - '/Users/gsposito/Projects/football/DraftWarRoom/_bmad-output/specs/spec-fantasy-warroom/stories/15-all-team-rosters-panel.md'
---

<frozen-after-approval reason="human-owned intent — do not modify unless human renegotiates">

## Intent

**Problem:** `app.R` empilha todo o conteúdo numa coluna vertical de `fluidRow`s.
DESIGN.md §"Layout & Spacing" e EXPERIENCE.md §"Information Architecture" /
§"Responsive & Platform" pedem regiões em painéis com `{spacing.gutter}` entre
elas — lado a lado numa janela ampla, colapsando para uma coluna linear numa
janela estreita ao lado da ESPN.

**Approach:** Reestruturar a árvore `ui` de `app.R` em regiões que espelham o
mockup — `.region--search` (campo dominante), `.workspace`
(recomendações | disponíveis), `.wide` (picks recentes | roster do operador) e
`.region--audit` (rosters dos times) — dentro de um `tags$main.warroom-main`.
`.workspace` / `.wide` são CSS grid de duas colunas numa janela ampla e uma
coluna abaixo de 900px (o mesmo limiar da story 15). Só mudam a árvore `ui` de
`app.R` e um bloco novo em `www/styles.css`; nenhum output, reactive, função core
ou contrato RDS muda. É o padrão de layout que as stories B/C seguintes preenchem
(board na `.wide`, inspeção na `.workspace`, auditoria na `.region--audit`).

## Boundaries & Constraints

**Always:**
- Só apresentação: `server()` inalterado; nenhuma chamada core nova; sem
  `tags$script` novo. Todos os outputs/inputs das stories 8–16 permanecem na `ui`
  com os mesmos id, cada função core (`recommend_players`, `derive_draft_view`,
  `resolve_player`, `record_pick`, `undo_pick`) ainda chamada 1× em `app.R`.
- `status_strip` e `draft_feedback` seguem filhos diretos de `fluidPage` antes de
  qualquer `.row`, nessa ordem (s10, s13). A região de busca é `fluidRow(column(12,
  div(class = "region region--search", ...)))` — mantém um `class="row"` (s10) e
  dá largura dominante ao campo.
- Strings acentuadas que a s13 fixa seguem literais: `h4("Recomendações")`,
  `h4("Disponíveis")`, `"Filtrar disponíveis por posição"`, `"buscar jogador
  disponível..."`, `actionButton("draft_btn", "Registrar"`.
- Mapa das regiões (detalhe e id no Code Map): busca (`player_query` +
  `search_results` + `.region-actions` com `draft_btn` e `undo_btn`);
  `.workspace` = Recomendações | Disponíveis (com `pos_filter` acima de
  `available_table`); `.wide` = Picks recentes | Seu roster; `.region--audit` = o
  `tags$details.all-rosters` da story 15 movido sem alteração.
- CSS novo só num bloco "panel-grid layout (story 17, B1)" em `www/styles.css`,
  inserido depois da seção all-rosters. Só tokens DESIGN.md para cor/espaço/raio.
  O `@media (max-width: 900px)` novo colapsa `.workspace`/`.wide` para
  `grid-template-columns: 1fr` e fica DEPOIS do `@media` da story 15 (a s15 usa a
  1ª ocorrência de `@media` para provar a posição do cap do grid de rosters).
- `app.R` adapter fino: sem pacote novo; sem `bslib` / `sass` / `includeCSS` /
  `shinyjs` / `Shiny.setInputValue`; sem símbolo de rede ou RNG; sem `@import` /
  `url(http...)` no CSS.

**Ask First:**
- Ocupação interina das colunas. Proposta: `.workspace` direita = Disponíveis,
  `.wide` esquerda = Picks recentes, `.region--audit` = rosters dos times.
  Alternativa a decidir no checkpoint: mover os rosters dos times para a `.wide`
  (o mockup aponta rosters de oponentes para o board) e deixar `.region--audit`
  vazia até a story 21. Recomendação: manter a proposta — nenhuma região fica
  vazia e a story 18/21 reorganiza quando o conteúdo real chegar.

**Never:**
- Grade do board (story 18); painel de inspeção (story 19); redesenho do Undo —
  contador, próximo-a-desfazer (story 20); linhas "Registrado" de auditoria
  (story 21); abas que preservam foco / navegação por teclado / roles ARIA de
  landmark (stories 22–23; Sprint Change de 2026-08-31 = colapso simples).
- Remover/renomear/mover-para-servidor qualquer output; recomputar campo na view;
  segundo caminho de pick.
- Rede, `ffanalytics`, `yaml` novo, mudança em `state/draft.rds` /
  `data/projections.rds`, Shiny modules, mudança no núcleo em `R/`.

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|---|---|---|---|
| UI estática renderiza | `htmltools::renderTags(ui)$html` | contém `class="workspace"`, `class="wide"`, `region--search`, `region--audit`; todos os id das stories 8–16 presentes; `status_strip` e `draft_feedback` antes do 1º `class="row"`, nessa ordem | N/A |
| Regras de grid presentes | `www/styles.css` | `.workspace` e `.wide` com `display: grid` e 2 colunas; um `@media (max-width: 900px)` que as põe em `1fr`, depois do `@media` da story 15 | N/A |
| Janela estreita (≤900px) | viewport 800px (manual) | busca, workspace e wide empilham em uma coluna linear; faixa de estado e busca seguem visíveis; sem scroll horizontal do body | N/A |
| Equivalência de recomendação | blocos s8c / s8e do smoke | `recs()` ↔ `recommend_players()` idênticos; nenhuma lógica tocada | N/A |
| `www/styles.css` ausente em runtime | arquivo removido, `app.R` re-carregado | `ui` monta, `shinyApp()` é `shiny.appobj`, sem erro (swap-and-restore das stories 9/11/12/15/16) | página funcional |
| Blocos 1–16 do smoke | `make test` sem rede | status 0; "story 8..16 offline checks OK" seguem; nova "story 17 offline checks OK" | N/A |

</frozen-after-approval>

## Code Map

- `app.R:37-118` — árvore `ui = fluidPage(...)`. **Reestruturar** os `fluidRow` de
  conteúdo (~71–117). `tags$head` (38–56, com o `tags$script` do Enter),
  `div(class = "app-header")` (57), `uiOutput("status_strip")` (63),
  `uiOutput("draft_feedback")` (69) **inalterados**, nessa ordem.
- `app.R:71-83` — `fluidRow` da busca. **Virar** `fluidRow(column(12, div(class =
  "region region--search", textInput("player_query", "Jogador", placeholder =
  "buscar jogador disponível..."), uiOutput("search_results"), div(class =
  "region-actions", actionButton("draft_btn", "Registrar", class = "btn-primary"),
  actionButton("undo_btn", "Undo")))))`. O `selectInput("pos_filter", ...)` **sai
  daqui**.
- `app.R:85-94` — `fluidRow` de Recomendações. **Mover** para a coluna esquerda da
  `.workspace`, markup interno idêntico (`h4("Recomendações")`, `.recs-note`,
  `.recs-filters` com `radioButtons("recs_pos_filter")`, `uiOutput("recs_table")`).
- `app.R:96-99` — `fluidRow(column(6, roster), column(6, recent_picks))`.
  **Dividir**: `h4("Picks recentes")` + `tableOutput("recent_picks_table")` -> à
  esquerda da `.wide`; `h4("Seu roster")` + `uiOutput("roster_table")` -> à
  direita da `.wide`.
- `app.R:101-103` — `fluidRow` de Disponíveis. **Mover** para a coluna direita da
  `.workspace`: `h4("Disponíveis")`, `selectInput("pos_filter", "Filtrar
  disponíveis por posição", choices = c("ALL", .warroom_pos_levels), selected =
  "ALL")`, `tableOutput("available_table")`.
- `app.R:112-117` — `fluidRow` dos rosters dos times (story 15). **Mover** o
  `tags$details(class = "all-rosters", open = NA, tags$summary(tags$h4("Rosters
  dos times")), uiOutput("all_rosters_table"))` inteiro para `div(class = "region
  region--audit", ...)` — sem tocar em `open = NA`, `<summary>`, nem no
  `uiOutput`. s15 checa `<details class="all-rosters" open>`, o `uiOutput` dentro
  dele e `<h4>Rosters dos times</h4>`.
- `app.R` — **Envolver** `.workspace`, `.wide` e `.region--audit` num
  `tags$main(class = "warroom-main", ...)`; a `fluidRow` da busca fica antes do
  `tags$main`, ainda filha de `fluidPage`. Colunas da `.workspace`/`.wide` são
  `div(...)` simples (o CSS mira `.workspace > div` / `.wide > div`).
- `www/styles.css:658-767` — seção all-rosters (story 15), termina no `@media
  (max-width: 900px)` (760–767). **Inserir** logo depois (antes de "section
  headings" na 769) o bloco "panel-grid layout (story 17, B1)": `.warroom-main`
  (grid, `gap: var(--gutter)`, `margin-top`), `.region--search` (padding +
  `var(--surface-raised)` + `1px solid var(--border)` + `var(--radius-sm)`),
  `.region-actions` (flex, `gap: var(--space-2)`, `margin-top`), `.workspace` /
  `.wide` (`display: grid`, 2 colunas via `minmax`, `gap: var(--gutter)`;
  `.workspace > div, .wide > div { min-width: 0 }`;
  `.workspace > div > h4:first-child, .wide > div > h4:first-child { margin-top: 0
  }`), e um `@media (max-width: 900px)` colapsando ambas para `1fr`.
- `www/styles.css:1-78` — comentário de cabeçalho. **Acrescentar** a nota da story
  17 (regiões `.warroom-main` / `.workspace` / `.wide` / `.region--*`; wide/narrow
  com colapso simples a 900px).
- `www/styles.css:706-709` — `.all-rosters[open] .all-rosters-grid { max-height …
  overflow-y: auto }`. **Não tocar**: continua antes da 1ª ocorrência de `@media
  (max-width: 900px)` (asserção s15) — por isso o novo `@media` entra depois do
  bloco da story 15.
- `tests/smoke.R:3952` — fim do bloco story 16. **Inserir** `## --- story 17`
  entre a 3952 e o guard de `prepare.R` (3954). Reusa `fail`, `ui`,
  `.s8_bake_server`, `.strip_html`.
- `tests/smoke.R` — asserções de estrutura estática já existentes a manter verdes:
  `2045-2048` (s10: `status_strip` antes do 1º `class="row"`), `3013-3018` (s13:
  `draft_feedback` depois de `status_strip`), `3541-3556` (s15: `<details>` +
  ids), `3568-3578` (s15: cap antes do 1º `@media`), `1990-1996` (s9), `2416-2420`
  (s11).
- `docs/design/mockups/live-war-room.html:31,47,67,96` — `main { display:grid;
  gap }`, `.workspace` (`minmax(0,1.35fr) minmax(185px,.9fr)`), `.wide`
  (`minmax(0,1.45fr) minmax(175px,.8fr)`), `@media` — referência de composição.
  Os spines vencem: limiar 900px (não 560), sem `.window`.

## Tasks & Acceptance

**Execution:**
- [x] `app.R` — reestruturar a árvore `ui`: `tags$main(class = "warroom-main")`
  com `.workspace` (Recomendações | Disponíveis), `.wide` (Picks recentes | Seu
  roster) e `.region--audit` (rosters dos times); busca como `fluidRow(column(12,
  .region--search))` antes do `main`, `draft_btn` + `undo_btn` em
  `.region-actions`, `pos_filter` realocado para o painel Disponíveis.
  `tags$head`, `.app-header`, `status_strip`, `draft_feedback` e todo o `server()`
  inalterados.
- [x] `www/styles.css` — bloco "panel-grid layout (story 17, B1)" depois da seção
  all-rosters: `.warroom-main`, `.region--search`, `.region-actions`,
  `.workspace`, `.wide` (grid 2 colunas) + `@media (max-width: 900px)` colapsando
  para `1fr`; atualizar o comentário de cabeçalho. Só tokens DESIGN.md; sem
  `@import` / `url(http`.
- [x] `tests/smoke.R` — bloco `## --- story 17`: `ui17` contém `class="workspace"`,
  `class="wide"`, `region--search`, `region--audit`; loop de id das stories 8–16
  presente; `status_strip`/`draft_feedback` antes do 1º `class="row"`, nessa
  ordem. `css17_code` (comentários removidos): `.workspace` e `.wide` com
  `display: grid`; um `@media (max-width: 900px)` com `grid-template-columns: 1fr`
  para `.workspace`/`.wide`, posição `>` a do `@media` da story 15. Estática de
  `app.R`: cada função core 1×; um `tags$script`; nenhum
  `bslib|sass|includeCSS|shinyjs|Shiny.setInputValue`; nenhum símbolo de rede/RNG.
  `www/styles.css` ausente -> `ui` monta e `shinyApp()` é `shiny.appobj`
  (swap-and-restore). Encerrar com `cat("story 17 offline checks OK ...\n")`.

**Acceptance Criteria:**
- Given `make test` sem rede, when executado, then status 0, com "story 8..16
  offline checks OK" e "story 17 offline checks OK"; os asserts de equivalência
  `recs()` ↔ `recommend_players()` (s8c/s8e) passam sem edição de lógica.
- Given `Rscript -e 'source("app.R"); cat(as.character(htmltools::renderTags(ui)$html))'`,
  when revisado, then os id `status_strip`, `draft_feedback`, `recs_note`,
  `recs_table`, `recs_pos_filter`, `pos_filter`, `roster_table`,
  `recent_picks_table`, `available_table`, `player_query`, `search_results`,
  `draft_btn`, `undo_btn`, `all_rosters_table` presentes; `class="workspace"` e
  `class="wide"` presentes; sem erro.
- Given `grep -cE "recommend_players\(|derive_draft_view\(|resolve_player\(|record_pick\(|undo_pick\(" app.R`,
  when revisado, then 1 para cada.
- Given `git diff app.R`, when revisado, then só rearranjo da árvore `ui`
  (regiões, `tags$main`, `.region-actions`, realocação do `pos_filter`); nada em
  `server()`, nos `render*`, nos reactives ou nos observers.
- Given `git diff www/styles.css`, when revisado, then só o bloco novo de layout +
  a nota de cabeçalho; `.all-rosters[open] .all-rosters-grid` e o `@media` da
  story 15 intactos e ainda antes do novo `@media`.

## Spec Change Log

## Design Notes

- **CSS grid, não o grid do Bootstrap.** `.row` / `.col-*` trazem margens
  negativas e flexbox que brigam com o gutter de painel do DESIGN.md; o mockup já
  é CSS grid explícito. Mantém-se um único `fluidRow` (a busca) só porque a s10
  prova o sticky da faixa de estado exigindo um `class="row"` depois dela.
- **Um só limiar wide/narrow.** A story 15 introduziu `@media (max-width: 900px)`
  para o grid de rosters; a story 17 reusa exatamente 900px para
  `.workspace`/`.wide`, para a página inteira ter um estado wide e um narrow.
- **Regiões nomeadas pelo destino.** `.workspace` / `.wide` / `.region--audit`
  recebem os nomes que as stories 18–21 preenchem (board na `.wide`, inspeção na
  `.workspace`, auditoria na `.region--audit`); a story 17 só cria os contêineres
  e coloca como ocupantes interinos os outputs que já existem.

## Verification

**Commands:**
- `make test` — status 0; inclui "story 17 offline checks OK" e mantém "story
  8..16 offline checks OK".
- `Rscript -e 'source("app.R"); cat(as.character(htmltools::renderTags(ui)$html))'`
  — `class="workspace"` / `class="wide"` / `region--search` / `region--audit`
  presentes; ids das stories 8–16 presentes; sem erro.
- `grep -cE "recommend_players\(|derive_draft_view\(|resolve_player\(" app.R` — 1
  cada.
- `grep -nE "bslib|sass|includeCSS|shinyjs|Shiny\.setInputValue" app.R` — vazio.
- `grep -c "tags\$script" app.R` — 1.

**Manual checks:**
- `make app` numa janela larga: Recomendações e Disponíveis lado a lado; Picks
  recentes e Seu roster lado a lado; rosters dos times ao pé. Estreitar para
  ~800px: tudo colapsa para uma coluna, faixa de estado e busca seguem visíveis,
  sem scroll horizontal.
- Registrar um pick e um Undo seguem funcionando pelos mesmos botões; a lista de
  recomendações recompõe.

## Suggested Review Order

**A árvore de regiões (o design)**

- Ponto de entrada: `div.warroom-main` — o contêiner que troca a pilha de `fluidRow` pelas regiões; plain div, não `<main>` (landmark é da story 23).
  [`app.R:101`](../../../../app.R#L101)

- Região de busca: o único `fluidRow` sobrevivente (só por causa das asserções s10/s17), campo dominante + `.region-actions`.
  [`app.R:78`](../../../../app.R#L78)

- `.workspace` = Recomendações | Disponíveis; `pos_filter` realocado para cá, acima de `available_table`.
  [`app.R:103`](../../../../app.R#L103)

- `.wide` = Picks recentes | Seu roster; `.region--audit` = o `tags$details.all-rosters` da story 15 movido sem alteração.
  [`app.R:122`](../../../../app.R#L122)

**Layout CSS (wide/narrow)**

- O bloco novo: `.warroom-main` (stack), `.workspace` / `.wide` (grid 2 colunas com razões do mockup), colapso a 900px.
  [`styles.css:778`](../../../../www/styles.css#L778)

- Alinhamento: `:has(> .region--search)` zera o padding da coluna Bootstrap para a busca casar com `.warroom-main`.
  [`styles.css:818`](../../../../www/styles.css#L818)

- Overflow: `#available_table, #recent_picks_table { overflow-x: auto }` dá scroll próprio às tabelas largas numa faixa estreita (sem scroll horizontal do body).
  [`styles.css:848`](../../../../www/styles.css#L848)

- O `@media` novo fica depois do da story 15 para não deslocar a 1ª ocorrência de `@media` (cap do grid de rosters).
  [`styles.css:861`](../../../../www/styles.css#L861)

**Testes**

- Bloco `## --- story 17`: regiões presentes, ids das stories 8–16 preservados, ordem status/feedback/`.row`, grid + `@media` tolerante a merge, swap-and-restore de `styles.css`.
  [`smoke.R:3954`](../../../../tests/smoke.R#L3954)
