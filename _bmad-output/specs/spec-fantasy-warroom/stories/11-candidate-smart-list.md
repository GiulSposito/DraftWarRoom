---
title: 'Lista inteligente de candidatos (A3)'
type: 'feature'
created: '2026-09-03'
status: 'done'
review_loop_iteration: 0
baseline_commit: 'd85b538a54a9448c1b8d743c0474a16ab73dfb87'
context:
  - '/Users/gsposito/Projects/football/DraftWarRoom/_bmad-output/specs/spec-fantasy-warroom/SPEC.md'
  - '/Users/gsposito/Projects/football/DraftWarRoom/_bmad-output/specs/spec-fantasy-warroom/recommendation-algorithm.md'
  - '/Users/gsposito/Projects/football/DraftWarRoom/AGENTS.md'
  - '/Users/gsposito/Projects/football/DraftWarRoom/docs/design/DESIGN.md'
  - '/Users/gsposito/Projects/football/DraftWarRoom/docs/design/EXPERIENCE.md'
---

<frozen-after-approval reason="human-owned intent — do not modify unless human renegotiates">

## Intent

**Problem:** `app.R` mostra as recomendações como um `renderTable` largo com 11
colunas (`player`, `pos`, `points`, `vor`, `tier`, `adp`, `p_next`, `wait_cost`,
`decision_score`, `label`, `reason`). `DESIGN.md` (§Components "Lista
inteligente") e `EXPERIENCE.md` pedem uma **lista curta ranqueada** — rank,
nome + posição, tier, score e um motivo de uma linha — com a recomendação nº 1
destacada por ordem e peso tipográfico (não por card), e filtros de posição como
badges discretos.

**Approach:** Trocar `tableOutput("recs_table")` por `uiOutput("recs_table")` e
`output$recs_table <- renderTable(...)` por um `renderUI` que compõe uma
`.smart-list` (cabeçalho `# · Jogador · Tier · Score` + uma linha `.candidate`
por recomendação, a primeira com `.candidate--top`). Adicionar
`radioButtons("recs_pos_filter", ...)` inline como badges de posição no painel de
recomendações; o filtro **subconjunta o `recs()` já em cache** (o mesmo
`reactive` de hoje), nunca re-chama `recommend_players()`. Nenhuma coluna é
recalculada na view — renderiza só o que `recommend_players()` já retorna. CSS
novo em `www/styles.css`, tokens verbatim de `DESIGN.md`.

## Boundaries & Constraints

**Always:**
- A ordem das linhas é a de `recommend_players()` — nunca reordenar na view. O
  rank exibido é a posição na frame (`01`, `02`, …) após o filtro de posição.
- O filtro de posição opera sobre `recs()` (o `reactive` existente) com um
  `subset` por `pos`; `recommend_players()` continua chamado exatamente uma vez
  por mudança de `state()` (guardrail de performance da `stories.yaml`,
  `RETROSPECTIVE.md` AV-4). `recs()` permanece `identical()` à chamada direta do
  terminal — os asserts `(8c)`/`(8e)` de `tests/smoke.R` passam sem edição.
- Renderização pura: cada `.candidate` usa só `player`, `pos`, `nfl_team`,
  `tier`, `decision_score`, `reason` da frame. Nenhuma fórmula, símbolo de RNG
  ou de rede novo (o bloco `(8h)` de `tests/smoke.R` vigia).
- `nfl_team` é campo opcional do snapshot (`R/projections.R` — só
  `player_id`/`player`/`pos`/`points` são obrigatórios): dropa em vez de
  imprimir `NA`. `tier` e `decision_score` ausentes/`NA` viram `—`, nunca a
  string `"NA"`.
- Mostra ao menos cinco candidatos quando `recs()` tem cinco ou mais linhas
  (padrão `n = 10L` de `recommend_players()` — renderiza todas as retornadas).
- Nº 1 destacado por **ordem e peso tipográfico** (`.candidate--top`: fundo
  `surface-raised`, peso 700, marcador em `action` na coluna de rank — a linha
  nº 1 é a ação que `Enter` registrará, `DESIGN.md` §Colors), nunca por um card
  grande.
- Badges de posição: `Todos` + `.warroom_pos_levels` (`QB RB WR TE K DST`),
  `selected = "Todos"`, `inline = TRUE`. Estado selecionado comunicado por
  texto/contorno além de cor.
- O aviso de off-turn continua em `output$recs_note` (inalterado); o `reason` do
  nº 1 já vem prefixado por `recommend_players()`.
- `app.R` continua adapter fino; sem pacote novo no `renv.lock`, sem JavaScript
  próprio, sem `bslib`/`sass`/`includeCSS`/`shinyjs`. CSS só em
  `www/styles.css`, sem asset remoto.
- `outputId` continua `recs_table` (agora `uiOutput`); `pos_filter` (filtro dos
  Disponíveis) e todos os demais ids das stories 8–10 permanecem.

**Ask First:**
- Reestruturar as seções em regiões workspace/wide/audit ou tornar painéis
  colapsáveis — é a story 14.
- Adicionar pacote ao `renv.lock`.
- Navegação por teclado / setas / `role="listbox"` / `aria-selected` reativos —
  stories 19–21 (um `role`/`aria-label` estático na lista é aceitável).

**Never:**
- Painel de inspeção, board em grade, undo redesenhado, combobox de busca,
  teclado, `aria-live` (stories 12–21).
- Rede, `ffanalytics`, leitura de `yaml` nova, mudança em `state/draft.rds` /
  `data/projections.rds`, Shiny modules.
- Recalcular `vor`, `p_next`, `wait_cost`, `tier_cliff`, `decision_score` ou a
  ordem na view; re-chamar `recommend_players()` na troca de filtro.

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| Meio de draft, ≥5 candidatos | `recs()` com 10 linhas, badge `Todos` | `.smart-list` com 10 `.candidate` ranqueadas `01`–`10`; a primeira tem `.candidate--top`; cada linha traz nome, `pos` (+`nfl_team` quando houver), `tier`, `decision_score` a 1 casa e `reason` de uma linha | N/A |
| Filtro de posição | badge `RB` selecionado | só linhas `pos == "RB"` de `recs()`, re-ranqueadas `01…`; `recommend_players()` não é re-chamado | N/A |
| Filtro sem correspondência | badge `TE`, nenhuma linha `TE` em `recs()` | texto `Nenhum candidato TE nas recomendações.`; badges seguem operáveis | N/A |
| Recomendações vazias | draft completo ou 0 candidatos (`recs()` 0 linhas) | texto `Nenhum candidato disponível.`; sem `.candidate`, sem erro | página funcional |
| Off-turn | `attr(recs(), "off_turn")` é `TRUE` | lista renderiza normal; `output$recs_note` mostra o aviso; `reason` do nº 1 já prefixado | N/A |
| `tier` / `decision_score` / `adp` `NA` | snapshot sintético sem `adp`, `tier` `NA` | célula `tier` e afins mostram `—`; nunca a string `NA` | N/A |
| `nfl_team` ausente | campo opcional fora do snapshot | `pos` sem time NFL (`WR`, não `WR NA`) | N/A |
| `styles.css` ausente em runtime | `www/styles.css` removido | lista sem estilo, sem erro de servidor | página funcional |

</frozen-after-approval>

## Code Map

- `app.R:64-68` — `fluidRow(column(12, h4("Recomendacoes"), div(class =
  "recs-note", textOutput("recs_note")), tableOutput("recs_table")))`.
  **Trocar** `tableOutput("recs_table")` por `uiOutput("recs_table")` e
  **inserir** `radioButtons("recs_pos_filter", NULL, choices = c("Todos",
  .warroom_pos_levels), selected = "Todos", inline = TRUE)` (envolto em
  `div(class = "recs-filters")`) entre a `recs-note` e a lista.
- `app.R:143-144` — `view <- reactive(...)`; `recs <- reactive({
  recommend_players(state(), snapshot) })`. **Não mudar** — a lista lê `recs()`.
- `app.R:254-258` — `output$recs_note <- renderText(...)` (aviso de off-turn).
  **Não tocar.**
- `app.R:260-265` — `output$recs_table <- renderTable({...})`. **Substituir**
  por `output$recs_table <- renderUI({...})`: pega `r <- recs()`, aplica
  `input$recs_pos_filter` (`if (!identical(pos, "Todos")) r <- r[r$pos == pos,
  , drop = FALSE]`), e monta a `.smart-list`. Caminho vazio → parágrafo de
  texto.
- `app.R:21` — `%||%` disponível para os campos opcionais.
- `R/core.R:468` — `.warroom_pos_levels <- c("QB","RB","WR","TE","K","DST")`,
  já em escopo (usado em `app.R:60`). Fonte das badges.
- `R/recommendation.R:472-473` — `recommend_players(state, snapshot, weights,
  n = 10L)`; `:638-659` a frame de saída (`player player_id pos points vor tier
  adp p_next marginal_value wait_cost tier_cliff adp_value decision_score label
  reason`); `:431-439` `.warroom_recs_result()` prefixa o `reason[1]` no
  off-turn.
- `recommendation-algorithm.md` §"Lista inteligente" / §"Recommendation output
  columns" — colunas e o contrato de off-turn.
- `docs/design/DESIGN.md` frontmatter — `components.smart-list`,
  `components.candidate-row`, `components.candidate-active`, `typography.data` /
  `typography.label`, `spacing`, `colors.action` (só ação/pick vivo).
- `docs/design/mockups/live-war-room.html:48-57,127-136` — espelho de
  referência: `.smart-list`, `.table-head`, `.candidate`, `.rank`, `.name`,
  `.pos`, `.score`, `.reason`, `.candidate.active`; grid
  `30px minmax(0,1fr) 38px 42px`.
- `www/styles.css:1-26` — comentário de cabeçalho lista a smart-list como escopo
  da story 11 → **atualizar**. `:96-221` bloco `.status-strip` (story 10) —
  **adicionar** o bloco `.smart-list` depois dele. `:446-449` `.recs-note` já
  existe.
- `tests/smoke.R:1609-1887` — bloco story 8 (`.s8_bake_server`, `.strip_html`,
  `recs()` equivalência em `(8c)`/`(8e)`, `(8h)` estática). `:1954`,`:2012` —
  loops de ids que já incluem `recs_table`. `:2160` fecha story 10; `:2162`
  começa o guard de `prepare.R` — **inserir** o bloco `## --- story 11` entre os
  dois.

## Tasks & Acceptance

**Execution:**
- [x] `app.R` — UI: `uiOutput("recs_table")` no lugar do `tableOutput`;
  `div(class = "recs-filters", radioButtons("recs_pos_filter", NULL, choices =
  c("Todos", .warroom_pos_levels), selected = "Todos", inline = TRUE))` acima da
  lista. Server: `output$recs_table <- renderUI({...})` sobre `recs()` filtrado
  por `input$recs_pos_filter` (subconjunto de `recs()`, **sem** re-chamar
  `recommend_players()`), compondo `.smart-list` (cabeçalho `# / Jogador / Tier
  / Score` + `.candidate` por linha; a primeira `.candidate--top`; rank `%02d`;
  `pos` + `nfl_team` quando presente; `tier` e `decision_score` com guarda de
  `NA` → `—`; `decision_score` a 1 casa; `reason` numa linha). Vazio →
  `Nenhum candidato disponível.`; filtro sem match → `Nenhum candidato <POS>
  nas recomendações.`. `role="list"` + `aria-label` estático na lista.
  `output$recs_note` e todo o resto do `server` inalterados.
- [x] `www/styles.css` — atualizar o comentário de cabeçalho; adicionar
  `.smart-list`, `.smart-list-head`, `.candidate` (grid como o mockup),
  `.candidate .rank` / `.name` / `.pos` / `.score` / `.reason`,
  `.candidate--top` (fundo `surface-raised`, peso 700, marcador `action` no
  rank), `.recs-filters` + estilo de badge para `.recs-filters .radio-inline`
  (borda `border`, `radius-sm`, `typography.label`) e o estado marcado
  (`surface-raised` + contorno `focus`). Só tokens de `DESIGN.md`, sem
  `@import` / `url(http`.
- [x] `tests/smoke.R` — bloco `## --- story 11`: via `.s8_bake_server` +
  `shiny::testServer`, um flatten de `output$recs_table` (como `.strip_html`)
  em cada cenário da matriz — meio de draft mostra `class="smart-list"`, ≥5
  `class="candidate"`, uma `candidate--top`, ranks `01`/`02`, o `player` e o
  `reason` do topo de `recommend_players()`; `session$setInputs(recs_pos_filter
  = "RB")` deixa só `pos` `RB` e não muda `recs()` (mesma frame `identical()`
  antes/depois); filtro sem match e draft completo caem nos textos de vazio;
  `tier`/`nfl_team` ausentes não emitem `"NA"`. UI estática: `id="recs_table"`
  presente e agora **sem** `<table` renderizado nele, `id="recs_pos_filter"`
  presente, demais ids das stories 8–10 intactos. `www/styles.css` contém
  `.smart-list` e `.candidate`, sem asset remoto. Estática de `app.R`: nenhum
  `bslib|sass|includeCSS|shinyjs|tags$script|Shiny.setInputValue` novo, nenhum
  símbolo de rede, `recommend_players` não redefinido nem chamado fora do
  `reactive` existente.

**Acceptance Criteria:**
- Given `make test` sem rede, when executado, then status 0 com os blocos das
  stories 1–11; `(8c)`/`(8e)` (equivalência `recs()` ↔ `recommend_players()`)
  passam sem edição e as linhas "story 8/9/10 offline checks OK" continuam.
- Given `Rscript -e 'source("app.R");
  cat(as.character(htmltools::renderTags(ui)$html))'`, when revisado, then há
  `id="recs_table"` (um `uiOutput`, sem `<table` estático) e
  `id="recs_pos_filter"`, e os ids `status_strip`, `recs_note`, `roster_table`,
  `recent_picks_table`, `available_table`, `player_choice`, `draft_btn`,
  `undo_btn`, `pos_filter` seguem presentes.
- Given `git diff app.R`, when revisado, then as mudanças são só: o
  `tableOutput`→`uiOutput`, o novo `radioButtons("recs_pos_filter", …)`, e o
  `renderTable`→`renderUI` de `recs_table`; nada em `recs`/`view`/`recs_note`/
  `record_pick`/`undo_pick`/`save_state`/`commit_state` ou nos demais `render*`.
- Given `grep -nE "bslib|sass|includeCSS|shinyjs|tags\\$script|Shiny\\.setInputValue" app.R`,
  when comparado ao estado anterior, then nenhuma ocorrência nova.

## Design Notes

- **Por que `renderUI` e não `renderTable`.** A "Lista inteligente" precisa de
  markup semântico com pesos distintos (rank, nome, motivo em `typography.data`
  reduzido) e de uma linha nº 1 destacada — um `renderTable` não expressa isso.
  Segue o mesmo padrão que a story 10 usou para a faixa de estado: formatação
  pura, teste assevera sobre uma string de HTML.
- **Por que filtrar `recs()` e não re-chamar.** `recs()` já é um `reactive`
  cacheado por `state()`. O badge de posição é uma view sobre a mesma frame;
  re-chamar `recommend_players()` (~286 ms mid-draft, `RETROSPECTIVE.md` AV-4)
  numa troca de badge é exatamente o anti-padrão que a `stories.yaml` proíbe
  para as stories seguintes. Subconjunto por `r$pos == input$recs_pos_filter`.
- **Tier.** `recommend_players()` retorna `tier` numérico do `ffanalytics`
  (o mockup usa `A`/`B` ilustrativo); renderiza o número como veio, `—` se `NA`.
- Exemplo de linha (topo): `01 · Nico Collins  WR HOU · T2 · 84.2 · Valor + necessidade WR · cliff após este tier`.

## Verification

**Commands:**
- `make test` — status 0; inclui "story 11" e mantém "story 8/9/10 offline
  checks OK".
- `Rscript -e 'source("app.R"); cat(as.character(htmltools::renderTags(ui)$html))'`
  — `id="recs_table"` e `id="recs_pos_filter"` presentes; sem `<table` dentro de
  `recs_table`.
- `grep -n "smart-list\|candidate\|recs-filters" www/styles.css` — presentes.

**Manual checks:**
- `make app`: recomendações como lista curta ranqueada, nº 1 com peso maior e
  marcador verde no rank; clicar um badge de posição filtra a lista sem
  piscar/recarregar as outras tabelas; badge `TE` sem candidatos mostra o texto
  de vazio; registrar um pick recompõe a lista; remover `www/styles.css` e
  recarregar — sem erro de servidor.

## Suggested Review Order

**A view (o que renderiza e por quê)**

- Ponto de entrada: `renderTable` largo → `renderUI` da `.smart-list`; lê
  `recs()` e nunca reordena as linhas de `recommend_players()`.
  [`app.R:270`](../../../../app.R#L270)
- Filtro de posição: subconjunta o `recs()` já em cache (`all_pos` /
  `r$pos == pos`); `recommend_players()` não é re-chamado numa troca de badge.
  [`app.R:275`](../../../../app.R#L275)
- `nfl_team` vem do snapshot (não da frame de recs) pelo mesmo join que
  `recent_picks_table` e a faixa de estado usam; coluna ausente → só `pos`.
  [`app.R:290`](../../../../app.R#L290)
- Marcador verde do nº 1 só na lista sem filtro (`candidate--top`); sob um badge
  a linha 1 é só "melhor da posição" (`candidate--first`, peso, sem verde).
  [`app.R:308`](../../../../app.R#L308)
- `tier` / `decision_score` / `reason` ausentes ou `NA` → travessão, nunca a
  string `"NA"`.
  [`app.R:296`](../../../../app.R#L296)

**A UI (o controle de badges)**

- `uiOutput("recs_table")` no lugar do `tableOutput`; `radioButtons` inline com
  rótulo acessível (escondido visualmente) acima da lista.
  [`app.R:64`](../../../../app.R#L64)

**O CSS (tokens de DESIGN.md, espelho do mockup)**

- `.smart-list` / `.candidate` em grid `30px minmax(0,1fr) 38px 42px`; nome
  trunca em `.name-text`, `.pos` fica fora do elemento que corta.
  [`styles.css:231`](../../../../www/styles.css#L231)
- Badges: o flex/gap fica em `.recs-filters .shiny-options-group` (onde o Shiny
  põe os `label.radio-inline`); o radio nativo é escondido, a pílula é o
  controle.
  [`styles.css:251`](../../../../www/styles.css#L251)
- Estado selecionado do badge por borda + fundo `surface-raised`, sem `outline`
  — para não colidir com o anel de foco de teclado azul.
  [`styles.css:298`](../../../../www/styles.css#L298)
- `.candidate--top` (verde no rank + fundo elevado) vs `.candidate--first` (só
  peso).
  [`styles.css:399`](../../../../www/styles.css#L399)

**Testes (offline)**

- Bloco story 11: matriz completa via `shiny::testServer` — lista ranqueada,
  filtro RB, filtro sem match, recs vazias, off-turn, `tier`/`nfl_team`
  ausentes, `styles.css` ausente — mais estáticas de UI/CSS/`app.R`.
  [`smoke.R:2162`](../../../../tests/smoke.R#L2162)
