---
title: 'Legibilidade da lista de candidatos e clicar para draftar (story 14)'
type: 'feature'
created: '2026-09-03'
status: 'done'
review_loop_iteration: 0
baseline_commit: 'b10994fdb1bfbe440dceafa045c8559404c7b893'
context:
  - '/Users/gsposito/Projects/football/DraftWarRoom/_bmad-output/specs/spec-fantasy-warroom/SPEC.md'
  - '/Users/gsposito/Projects/football/DraftWarRoom/AGENTS.md'
  - '/Users/gsposito/Projects/football/DraftWarRoom/docs/design/DESIGN.md'
  - '/Users/gsposito/Projects/football/DraftWarRoom/docs/design/EXPERIENCE.md'
  - '/Users/gsposito/Projects/football/DraftWarRoom/_bmad-output/specs/spec-fantasy-warroom/stories/11-candidate-smart-list.md'
---

<frozen-after-approval reason="human-owned intent — do not modify unless human renegotiates">

## Intent

**Problem:** Uma sessão de teste com dados reais expôs dois atritos de operação
na lista inteligente da story 11: (1) `motivo`, `tier` e `score` de cada
candidato são renderizados em `--ink-muted`, então o conteúdo que decide o pick
compete visualmente com a decoração (dígitos de rank, cabeçalhos de coluna) em
vez de saltar na varredura; (2) registrar um jogador da lista exige ir até a
busca, selecionar o nome e clicar em **Registrar** — não há como agir direto
sobre a linha recomendada.

**Approach:** (1) Promover o conteúdo da `.candidate` (`reason`, `tier`, `score`)
de `--ink-muted` para `--ink` em `www/styles.css`; `--ink-muted` fica só na
decoração (`.candidate .rank`, `.smart-list-head`, e o badge posicional
`.candidate .pos`, que é metadado não crítico — `DESIGN.md` §Roster). Nenhum
token de cor novo. (2) Cada linha `.candidate` passa a ser um
`tags$button(class = "candidate action-button …")` (binding nativo de
`actionButton` do Shiny — sem JavaScript próprio). Um clique em qualquer ponto
da linha registra o jogador daquela posição na frame filtrada, chamando **o
mesmo** caminho de `record_pick()` que o botão **Registrar** usa: o corpo do
`observeEvent(input$draft_btn)` é extraído para uma função local `do_pick(pid,
empty_msg)` reusada pelos dois gatilhos. O registro é **imediato** (sem diálogo
de confirmação) — o undo da story 13 cobre um clique errado.

## Boundaries & Constraints

**Always:**
- Um só caminho de pick: `do_pick()` é a única função que chama `record_pick()`
  / `commit_state()` / escreve `feedback()`. `record_pick(` e `undo_pick(`
  continuam aparecendo exatamente uma vez cada em `app.R`. Ordem inalterada:
  `record_pick()` -> `save_state()` -> `state(new_st)` (AGENTS.md).
- `recommend_players()` continua chamado exatamente uma vez em `app.R` (no
  `reactive` `recs`). Um clique de linha **nunca** re-chama `recommend_players()`
  (guardrail de performance da `stories.yaml` / `RETROSPECTIVE.md` AV-4). O
  jogador clicado vem de um `reactive` `recs_view()` que só subconjunta `recs()`
  pelo badge `input$recs_pos_filter` — a mesma lógica de filtro que a story 11
  já aplica no `renderUI`, agora fatorada para o `reactive` e reusada pela view
  e pelos observers.
- A ordem e o conteúdo das linhas seguem `recommend_players()` — nada é
  reordenado ou recalculado na view. Rank exibido = posição na frame filtrada
  (`01`, `02`, …). Todos os contratos da story 11 seguem: `.candidate--top` só
  na lista sem filtro, `.candidate--first` sob badge, `tier`/`score`/`reason`
  ausentes ou `NA` viram `—` (nunca a string `"NA"`), `nfl_team` opcional
  dropado quando ausente.
- Cada linha-botão tem `type = "button"`, a classe começa em `candidate`
  (`class = "candidate action-button …"`), e um `aria-label` textual
  (`Registrar <jogador>`). O afeto de hover/press usa `--surface-raised`
  (`DESIGN.md` `components.candidate-active.background`); o anel de foco de
  teclado azul já vem da regra global `button:focus` — não duplicar.
- Contraste: só `.candidate .reason` / `.candidate .tier` / `.candidate .score`
  mudam para `var(--ink)`. `.roster-row .slot`, `.smart-list-head`,
  `.candidate .rank` permanecem `var(--ink-muted)`. Nenhuma regra de `.btn`
  vaza para a linha (o botão não recebe `class="btn"`).
- `app.R` segue adapter fino: sem pacote novo no `renv.lock`, sem `bslib` /
  `sass` / `includeCSS` / `shinyjs` / `tags$script` / `Shiny.setInputValue`,
  sem símbolo de rede ou RNG. CSS só em `www/styles.css`, sem asset remoto. Os
  `outputId` / `inputId` das stories 8–13 permanecem; o `id` das linhas-botão é
  `pick_row_<k>` (`k` de 1 a 10, casando o `n = 10L` default de
  `recommend_players()`).

**Ask First:**
- Introduzir um token de cor secundário novo (ex.: `--ink-secondary`) em vez de
  promover o conteúdo para `--ink` cheio.
- Promover também os nomes de jogador do roster / da tabela de disponíveis (a
  investigação achou que eles já herdam `--ink`; ver Design Notes).
- Qualquer forma de confirmação antes de registrar o clique.
- Navegação por setas / `role="listbox"` / `role="option"` / `aria-selected`
  reativo / roving tabindex — stories 22 (C1) e 23 (C3).

**Never:**
- Re-chamar `recommend_players()` num clique de linha ou numa troca de badge.
- Segundo caminho de registro de pick (duplicar o corpo do `observeEvent`).
- Painel de inspeção, board em grade, undo redesenhado, combobox de busca,
  atalhos de teclado, `aria-live` (stories 16, 19–23).
- Rede, `ffanalytics`, leitura de `yaml` nova, mudança em `state/draft.rds` /
  `data/projections.rds`, Shiny modules, JavaScript próprio.
- Mudar `record_pick()` / `undo_pick()` / `save_state()` ou o núcleo em `R/`.

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| Clique na linha 1, na vez, meio de draft | `recs()` com ≥5 linhas, badge `Todos`, `session$setInputs(pick_row_1 = 1)` | `record_pick()` do `recs_view()$player_id[1]`; `state()$picks` cresce 1; `feedback()` = `list(kind="ok", text="Registrado: <jogador>")`; estado salvo em disco | N/A |
| Clique numa linha sob filtro de posição | badge `RB` selecionado, `pick_row_2 = 1` | registra o 2º `RB` de `recs_view()` (a frame já subconjuntada); `recommend_players()` não é re-chamado; `identical(recs(), <antes>)` | N/A |
| Clique numa linha de jogador já draftado | `pick_row_k` aponta para um `player_id` já em `picks` (corrida rara) | `feedback()` = `list(kind="error", text="Já escolhido no pick <N>. Busque outro jogador.")`; `state()` intacto | mensagem persistente, sem crash |
| Clique fora de alcance | `pick_row_9 = 1` mas `recs_view()` tem 6 linhas | `do_pick(NA, …)` -> `feedback()` erro `"Recomendação indisponível — atualize a lista."`; `state()` intacto | página funcional |
| Botão **Registrar** (regressão) | `player_choice` = id, `draft_btn = 1` | comportamento idêntico ao anterior (mesma mensagem de seleção vazia, mesmo caminho `do_pick`) | inalterado |
| Contraste renderizado | qualquer estado com `recs()` não vazio | `reason` / `tier` / `score` das `.candidate` computados em `--ink`; `rank` e `.smart-list-head` seguem `--ink-muted` | N/A |
| `www/styles.css` ausente em runtime | arquivo removido | lista-botão ainda monta, clique ainda registra, sem erro de servidor | página funcional |

</frozen-after-approval>

## Code Map

- `app.R:193-218` — `observeEvent(input$draft_btn, {...})`. **Extrair** o corpo
  (guarda de seleção vazia + `tryCatch` com `record_pick` / `commit_state` /
  `updateSelectizeInput` / `feedback`) para `do_pick <- function(pid, empty_msg)
  {...}` definida logo acima do observer. O observer vira
  `observeEvent(input$draft_btn, { do_pick(input$player_choice, "Selecione um
  jogador na busca antes de registrar.") })`. A mensagem de "já escolhido"
  continua derivando `N` de `state()$picks$overall`.
- `app.R:162` — `recs <- reactive({ recommend_players(state(), snapshot) })`.
  **Não mudar.** **Adicionar** logo abaixo `recs_view <- reactive({ r <-
  recs(); pos <- input$recs_pos_filter %||% "Todos"; if (!identical(pos,
  "Todos")) r <- r[!is.na(r$pos) & r$pos == pos, , drop = FALSE]; r })`.
- `app.R:220-238` — `observeEvent(input$undo_btn, …)`. **Não tocar.**
- `app.R` (após os dois observers de pick) — **adicionar** o registro dos
  gatilhos de linha: `lapply(seq_len(10L), function(k) observeEvent(input[[
  sprintf("pick_row_%d", k)]], { rv <- recs_view(); pid <- if (k <= nrow(rv))
  rv$player_id[k] else NA_character_; do_pick(pid, "Recomendação indisponível —
  atualize a lista.") }, ignoreInit = TRUE))`.
- `app.R:329-388` — `output$recs_table <- renderUI({...})`. **Trocar** a leitura
  `r <- recs()` + filtro inline por `r <- recs_view()` (o caso `nrow(recs()) ==
  0` -> `"Nenhum candidato disponível."` e o caso `nrow(recs_view()) == 0` com
  `recs()` não vazio -> `"Nenhum candidato <POS> nas recomendações."` seguem
  distintos). **Trocar** `tags$div(class = row_cls, role = "listitem", …)` por
  `tags$button(type = "button", id = sprintf("pick_row_%d", i), class =
  paste("candidate action-button", <sufixo --top/--first>), role = "listitem",
  `aria-label` = paste("Registrar", r$player[i]), …spans…)`. `role = "listitem"`
  fica no `<button>` (mantém a contagem de item da `.smart-list`, que segue
  `role = "list"`). Spans `rank`/`name`/`name-text`/`pos`/`tier`/`score`/`reason`
  inalterados.
- `app.R:21` — `%||%` disponível.
- `R/recommendation.R` — `recommend_players(state, snapshot, weights, n = 10L)`;
  frame de saída com `player_id`, `pos`, `tier`, `decision_score`, `reason`.
  Fonte do `n = 10L` que fixa o range de `pick_row_<k>`.
- `www/styles.css:397-409` — `.candidate .tier, .candidate .score { color:
  var(--ink-muted); … }` e `.candidate .reason { … color: var(--ink-muted); …
  }`. **Trocar** as três para `var(--ink)`. **Não** mexer em
  `.candidate .rank` (`:370-372`), `.smart-list-head` (`:341-349`),
  `.candidate .pos` (`:390-395`).
- `www/styles.css:358-368` — bloco `.candidate` (grid, `min-height`, borda). O
  seletor `.candidate` continua alcançando o `<button>` (classe vence tipo).
  **Adicionar** depois do bloco `.candidate--top` (`:420-427`) um reset de botão
  + afeto de interação: `button.candidate { width: 100%; border: 0;
  border-bottom: 1px solid var(--border); background: transparent; text-align:
  left; font: inherit; color: var(--ink); cursor: pointer; appearance: none; }`
  e `button.candidate:hover, button.candidate:active { background:
  var(--surface-raised); }`. `button.candidate:last-child { border-bottom: 0; }`.
- `www/styles.css:1-55` — comentário de cabeçalho: **atualizar** a nota da story
  11 para registrar que a story 14 promove `reason`/`tier`/`score` da
  `.candidate` para `--ink` e torna a linha um `<button>` clicável.
- `tests/smoke.R:1634-1653` — `.s8_bake_server`, `.strip_html`, `.html_count`
  (reusar). `:2196` — `.s11_count`.
- `tests/smoke.R:2444` — fim do bloco story 11. `:3045` — fim do bloco story 13.
  `:3047` — início do guard de `prepare.R`. **Inserir** o bloco `## --- story
  14` entre `:3045` e `:3047`.
- `tests/smoke.R:2416-2418` — lista de tokens que a story 11 exige em
  `styles.css` (inclui `.candidate`, `name-text`); segue satisfeita.
- `tests/smoke.R:2226,2234,2237,2242,2320` — asserts da story 11 sobre o HTML da
  `.candidate` (`class="candidate`, `class="pos">`, `>01<`, `>NN.N<`). Todos
  seguem válidos com a classe começando em `candidate` e os spans inalterados.

## Tasks & Acceptance

**Execution:**
- [x] `app.R` — extrair `do_pick(pid, empty_msg)` do `observeEvent(input$draft_btn)`
  (guarda de seleção vazia usa `empty_msg`; resto idêntico, incluindo a
  derivação de `N` para a mensagem "já escolhido"). Reapontar `draft_btn` para
  `do_pick`. Adicionar o `reactive` `recs_view()` (subconjunto de `recs()` pelo
  badge). Adicionar `lapply(seq_len(10L), …)` registrando
  `observeEvent(input[["pick_row_<k>"]], …, ignoreInit = TRUE)` que chama
  `do_pick(recs_view()$player_id[k] | NA, "Recomendação indisponível — atualize
  a lista.")`. No `renderUI` de `recs_table`: ler `recs_view()`, render cada
  linha como `tags$button(type="button", id="pick_row_<i>", class="candidate
  action-button[ --top| --first]", aria-label="Registrar <jogador>", …spans…)`,
  sem `role` no botão. `undo_btn` e todo o resto do server inalterados.
- [x] `www/styles.css` — `.candidate .tier` / `.candidate .score` / `.candidate
  .reason` para `var(--ink)`. Adicionar o reset `button.candidate` (largura
  total, sem chrome de botão, `font: inherit`, `cursor: pointer`) e
  `button.candidate:hover, button.candidate:active { background:
  var(--surface-raised); }` + `button.candidate:last-child { border-bottom: 0; }`.
  Atualizar o comentário de cabeçalho. Só tokens de `DESIGN.md`, sem `@import` /
  `url(http`.
- [x] `tests/smoke.R` — bloco `## --- story 14` (via `.s8_bake_server` +
  `shiny::testServer`): cada cenário da matriz. Estado meio de draft na vez ->
  `session$setInputs(pick_row_1 = 1)` cresce `state()$picks` em 1 com o
  `player_id` de `recommend_players()[1]`, `feedback()` `kind == "ok"`, e o
  arquivo de estado recarregado tem o pick; sob `recs_pos_filter = "RB"`,
  `pick_row_1 = 1` registra o 1º RB e a badge não altera `recs()`; um clique numa
  linha > 1 (`pick_row_3`) registra o jogador daquela linha; um índice além da
  frame filtrada -> `feedback()` erro e `nrow(state()$picks)` inalterado;
  `draft_btn` sem seleção mantém a mensagem antiga. HTML de `recs_table`:
  contém `<button`, `id="pick_row_1"`, `class="candidate action-button`,
  `aria-label="Registrar `, e mantém `role="listitem"`. CSS: as três regras
  `.candidate .reason|.tier|.score` casam `var(--ink)` e **não** `var(--ink-muted)`;
  `.candidate .rank` e `.smart-list-head` seguem `var(--ink-muted)`; existe
  `button.candidate` com `:hover` e `:focus-visible`. Estática de `app.R`: `record_pick(` e
  `undo_pick(` uma vez cada; `recommend_players(` uma vez; nenhum
  `bslib|sass|includeCSS|shinyjs|tags$script|Shiny.setInputValue`; nenhum
  símbolo de rede/RNG. `www/styles.css` ausente -> a lista-botão ainda monta e o
  clique ainda registra (mesmo padrão swap-and-restore das stories 9/11/12).

**Acceptance Criteria:**
- Given `make test` sem rede, when executado, then status 0 com os blocos das
  stories 1–14; as linhas "story 8/9/10/11/12/13 offline checks OK" continuam e
  os asserts `(8c)`/`(8e)` (equivalência `recs()` ↔ `recommend_players()`)
  passam sem edição.
- Given `Rscript -e 'source("app.R");
  cat(as.character(htmltools::renderTags(ui)$html))'`, when revisado, then os
  `id` `status_strip`, `draft_feedback`, `recs_note`, `recs_table`,
  `recs_pos_filter`, `roster_table`, `recent_picks_table`, `available_table`,
  `player_choice`, `draft_btn`, `undo_btn`, `pos_filter` seguem presentes (as
  linhas-botão são server-rendered, não aparecem na UI estática).
- Given `git diff app.R`, when revisado, then as mudanças são só: o `do_pick`
  extraído + `draft_btn` reapontado, o `reactive` `recs_view`, o `lapply` dos
  observers `pick_row_<k>`, e o `renderUI` de `recs_table` (div->button); nada
  em `recs`/`view`/`recs_note`/`undo_btn`/`commit_state`/`record_pick`/
  `undo_pick`/`save_state` ou nos demais `render*`.
- Given `grep -nE "var\(--ink-muted\)" www/styles.css` no bloco `.candidate`,
  when comparado ao estado anterior, then só `.candidate .rank` (e o badge
  `.candidate .pos`) o mantêm — `reason`/`tier`/`score` não.

## Design Notes

- **Por que `<button>` e não um handler de clique próprio.** O binding de
  `action-button` do Shiny já entrega o evento de clique via
  `input[["pick_row_k"]]` sem `Shiny.setInputValue` nem `tags$script` — o
  elemento `<button>` também dá `Enter`/`Espaço` nativos, que é exatamente "o
  mesmo caminho que `Enter` registraria" que a `stories.yaml` pede, sem
  antecipar o modelo de teclado da story 22 (setas, `role="listbox"`, roving
  tabindex, atalho `U`). A classe começa em `candidate` para os `grep` de
  contagem de linha da story 11 continuarem casando.
- **`role="listitem"` fica no `<button>`.** Um `<button role="listitem">` perde
  parte da semântica nativa de botão para AT, mas mantém a contagem / o índice
  de item da `.smart-list` (`role="list"`, testado pela story 11) enquanto as
  stories 22/23 miram o combobox de busca e não a lista de recomendações. O
  `aria-label="Registrar <jogador>"` (verbo) mais o foco de teclado com `Enter`
  sinalizam a ação; a promoção da lista para listbox/option é da story 23.
  (Revisão 2026-09-03: dois revisores marcaram a lista/listitem incoerente
  quando o `role` era omitido — reintroduzido.)
- **Contraste: promover para `--ink`, sem token novo.** Todo comentário de CSS
  do projeto afirma "tokens verbatim de `DESIGN.md`"; o `change_log` de
  2026-08-31 aceita os pares "como estão". `--ink` sobre `--surface` é uma
  combinação permitida (`DESIGN.md` §Colors, 4.5:1). Um `--ink-secondary` novo
  daria uma hierarquia de três níveis mais limpa mas quebra a convenção — fica
  como decisão de checkpoint (Ask First).
- **Nomes de jogador do roster / disponíveis.** A investigação encontrou
  `.roster-row .name` herdando `color: var(--ink)` de `.roster-row`, e as
  células `td` da tabela de disponíveis já em `var(--ink)` (`.table > tbody >
  tr > td`). A story cita "nomes de jogador" como conteúdo em `--ink-muted`,
  mas eles já renderizam em `--ink` — nenhuma mudança necessária ali. Sinalizado
  para o checkpoint.
- **Registro imediato, sem confirmação.** A story pede clique direto; o painel
  de feedback persistente da story 13 já mostra `Registrado: X` e o undo
  multinível está a uma tecla/clique. Um diálogo de confirmação anularia a
  velocidade que motivou a mudança.
- Exemplo de linha renderizada (topo, sem filtro):
  `<button type="button" id="pick_row_1" class="candidate action-button candidate--top" role="listitem" aria-label="Registrar Nico Collins"> <span class="rank">01</span> <span class="name"><span class="name-text">Nico Collins</span><span class="pos">WR HOU</span></span> <span class="tier">2</span> <span class="score">84.2</span> <span class="reason">Valor + necessidade WR</span> </button>`

## Verification

**Commands:**
- `make test` — status 0; inclui uma linha "story 14" e mantém as linhas
  "story 8/9/10/11/12/13 offline checks OK".
- `Rscript -e 'source("app.R"); cat(as.character(htmltools::renderTags(ui)$html))'`
  — todos os `id` das stories 8–13 presentes; sem erro.
- `grep -nE "\.candidate \.(reason|tier|score)" www/styles.css` — as três em
  `var(--ink)`.
- `grep -cE "record_pick\(|undo_pick\(|recommend_players\(" app.R` por símbolo —
  1 cada.

**Manual checks:**
- `make app`: `motivo`/`tier`/`score` de cada candidato legíveis na varredura
  (não mais cinza apagado); passar o mouse sobre uma linha da lista mostra o
  fundo elevado e o cursor de ponteiro; clicar em qualquer ponto da linha
  registra o jogador e recompõe a lista; clicar num jogador que outro time já
  pegou mostra o erro persistente; `U` / **Undo** reverte um clique errado;
  remover `www/styles.css` e recarregar — sem erro de servidor, clique ainda
  funciona.

## Suggested Review Order

**Caminho único de pick (o design)**

- Ponto de entrada: o corpo do antigo `observeEvent(draft_btn)` vira `do_pick(pid, empty_msg)` — única chamada de `record_pick()`.
  [`app.R:211`](../../../../app.R#L211)

- Os dez observers `pick_row_<k>` resolvem o jogador por rank em `recs_view()` e chamam `do_pick`; `lapply` + `force` para o índice não vazar nem virar promise diferida.
  [`app.R:248`](../../../../app.R#L248)

- `recs_view()`: subconjunto de `recs()` pelo badge — nenhuma re-chamada de `recommend_players()` num clique ou filtro.
  [`app.R:168`](../../../../app.R#L168)

**Lista clicável (a view)**

- `renderUI` lê `recs_view()`; cada linha é `tags$button` com `role="listitem"` e `aria-label="Registrar <jogador>"`.
  [`app.R:369`](../../../../app.R#L369)

- A linha-botão em si (classe começa em `candidate` para os contadores da story 11).
  [`app.R:417`](../../../../app.R#L417)

**Legibilidade + chrome do botão (o CSS)**

- `reason` / `tier` / `score` sobem para `var(--ink)`; `rank` e cabeçalho seguem `--ink-muted`.
  [`styles.css:441`](../../../../www/styles.css#L441)

- Reset de `<button>` + afeto de hover/press/foco-visível em `--surface-raised`.
  [`styles.css:383`](../../../../www/styles.css#L383)

- `.candidate--top` reescopado para `.smart-list .candidate--top` (vence o fundo transparente do botão).
  [`styles.css:465`](../../../../www/styles.css#L465)

**Testes**

- Bloco `## --- story 14`: clique linha 1 e linha 3, sob filtro, fora de alcance, já draftado, regressão do botão, contraste no CSS, estática de `app.R`, `styles.css` ausente.
  [`smoke.R:3047`](../../../../tests/smoke.R#L3047)
