---
title: 'Shell de terminal escuro (A1)'
type: 'feature'
created: '2026-09-02'
status: 'done'
review_loop_iteration: 0
baseline_commit: '0be889cf9feb3136156f83b572089061897aa62c'
context:
  - '/Users/gsposito/Projects/football/DraftWarRoom/_bmad-output/specs/spec-fantasy-warroom/SPEC.md'
  - '/Users/gsposito/Projects/football/DraftWarRoom/AGENTS.md'
  - '/Users/gsposito/Projects/football/DraftWarRoom/docs/design/DESIGN.md'
---

<frozen-after-approval reason="human-owned intent — do not modify unless human renegotiates">

## Intent

**Problem:** `app.R` (story 8) roda com o tema Bootstrap claro default do
`fluidPage` e um `titlePanel` grande — o oposto do shell de terminal escuro e
denso que `docs/design/DESIGN.md` define como fonte visual. Nenhum design token
(cor, fonte mono, espaçamento) chega à interface hoje.

**Approach:** Criar `www/styles.css` a partir dos tokens de `DESIGN.md` e
carregá-lo em `app.R` via `tags$head(tags$link(...))`, restilizando as
superfícies do Bootstrap para o shell escuro; trocar o `titlePanel` por um
cabeçalho enxuto. Só aparência: nenhum output, reactive, função de core ou
contrato RDS muda.

## Boundaries & Constraints

**Always:**
- Somente CSS + o cabeçalho. Zero mudança no **conteúdo** renderizado: mesmos
  `outputId` (`banner`, `recs_note`, `recs_table`, `roster_table`,
  `recent_picks_table`, `available_table`), mesmas colunas e linhas, mesmos
  `inputId` (`player_choice`, `draft_btn`, `undo_btn`, `pos_filter`), mesma
  árvore `fluidPage`/`fluidRow`/`column`.
- `www/styles.css` usa os valores exatos do frontmatter de `DESIGN.md`
  (`colors`, `typography` — pilha mono do sistema, `rounded.sm = 2px`,
  `spacing`, `components.focus-ring`), com os tokens em `:root` e
  `color-scheme: dark`. O bloco `<style>` de `docs/design/mockups/
  live-war-room.html` é o espelho de referência.
- `app.R` continua adapter fino: nenhuma fórmula, chamada de `R/` core, símbolo
  de RNG ou de rede introduzido — o bloco `(8h)` de `tests/smoke.R` já vigia
  isso e deve seguir passando.
- Sem pacote novo no `renv.lock`: um `.css` estático servido de `www/`. Nada de
  `bslib`/`sass`/`bs_theme`, nem `includeCSS()` inline.

**Ask First:**
- Qualquer mudança no texto, colunas ou nº de linhas de um output, ou que mova
  markup para fora de `fluidPage`/`fluidRow`/`column` (layout em grade é a
  story 14).
- Adicionar qualquer pacote ao `renv.lock`.

**Never:**
- Faixa de estado estruturada, smart-list, painel de inspeção, board em grade,
  undo redesenhado, teclado, roles/`aria-live` (stories 10–21).
- Rede, `ffanalytics`, leitura de `yaml` nova, mudança em `state/draft.rds` ou
  `data/projections.rds`, Shiny modules, JavaScript próprio.

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| App sobe com o CSS | `make app` | `<head>` inclui `<link rel="stylesheet" href="styles.css">`; página em fundo `#0B0F14`, texto `#E7EDF3`, fonte mono, tabelas densas com borda `#293746` | N/A |
| Equivalência de conteúdo | mesmo `state/draft.rds` + snapshot da story 8 | blocos `(8a)`–`(8h)` de `tests/smoke.R` passam sem edição | N/A |
| `styles.css` ausente em runtime | `www/styles.css` removido | página degrada para o Bootstrap default, sem erro de servidor | página funcional, sem tema |

</frozen-after-approval>

## Code Map

- `app.R` — `ui <- fluidPage(...)` em `:37`; `titlePanel("Draft War Room")` em
  `:38` (**trocar** por cabeçalho enxuto em caixa alta, mesmo texto);
  `div(style = "color:#b00; font-weight:bold;", textOutput("recs_note"))` em
  `:60` (**trocar** `style=` por `class = "recs-note"`). **Adicionar**
  `tags$head(tags$link(rel = "stylesheet", href = "styles.css"))` como primeiro
  filho de `fluidPage`. `server()` e todos os `output$*` — **não tocar**.
- `www/styles.css` — **novo**. `:root` com os tokens; restyle de
  `body`/`.container-fluid`, `h1..h4`, `table`/`th`/`td`, `.btn`/`.btn-primary`,
  `.form-control`/`.selectize-input`/`.selectize-dropdown`,
  `.shiny-notification`, `:focus`, `.recs-note`.
- `docs/design/DESIGN.md` — fonte dos valores (frontmatter). Mockup em
  `docs/design/mockups/live-war-room.html` — `<style>` de referência.
- `tests/smoke.R` — bloco de story 8 fecha em `:1878` (`cat("story 8 offline
  checks OK ...")`); guard de `prepare.R` começa em `:1880`. **Inserir** o
  bloco `## --- story 9` entre os dois.

## Tasks & Acceptance

**Execution:**
- [x] `www/styles.css` — shell escuro a partir dos tokens de `DESIGN.md`:
  `:root` + `color-scheme: dark`, fundo/texto/fonte mono, tabelas densas,
  `.btn-primary` em `action` (`#57D68D`), inputs e `selectize`,
  `.shiny-notification`, focus-ring 2px em `focus` (`#67B7FF`) offset 2px,
  `.recs-note` em `danger` (`#FF6B6B`).
- [x] `app.R` — `tags$head(tags$link(...))` no topo do `fluidPage`; cabeçalho
  enxuto no lugar do `titlePanel`; `class = "recs-note"` no lugar do `style=`
  inline. Nenhuma outra mudança.
- [x] `tests/smoke.R` — bloco de story 9: `www/styles.css` existe e é não-vazio;
  contém `#0B0F14`, `#57D68D`, `#67B7FF`, `ui-monospace`, `2px`; `app.R`
  referencia `styles.css` via `tags$head`; `as.character(ui)` contém
  `href="styles.css"` **e** ainda todos os `outputId`/`inputId` da story 8.

**Acceptance Criteria:**
- Given `make test` sem rede, when executado, then status 0 com os blocos das
  stories 1–9; os asserts de conteúdo de output da story 8 (`(8a)`–`(8h)`)
  passam sem edição.
- Given `make app` num navegador, when a página carrega, then fundo `#0B0F14`,
  fonte monoespaçada, tabelas densas com borda `#293746`, botão Draft verde
  `#57D68D`, contorno de foco `#67B7FF` de 2px ao navegar por Tab.
- Given `git diff app.R`, when revisado, then as únicas mudanças são o
  `tags$head`, o cabeçalho no lugar do `titlePanel` e o `class=` no lugar do
  `style=` — nada em `server`, `render*` ou nos ids.
- Given `grep -nE "bslib|sass|bs_theme|includeCSS" app.R`, when comparado ao
  estado anterior, then nenhuma ocorrência nova.

## Design Notes

- **Por que não remover o Bootstrap literalmente.** `fluidPage` é o scaffold que
  injeta `selectizeInput`/`renderTable` e as dependências JS; removê-lo exigiria
  reescrever a página e reestilizar o `selectize` do zero — isso é a story 14
  (layout) e a story 20 (busca). "Replace the default fluidPage Bootstrap
  chrome" aqui = sobrepor um restyle escuro completo que suprime visualmente o
  chrome claro default, sem tocar estrutura nem outputs.
- **Carregamento do CSS.** `tags$head(tags$link(rel = "stylesheet", href =
  "styles.css"))` — o Shiny serve `www/` na raiz da app (`make app` roda
  `shiny::runApp(".")` → `./www/styles.css`). `includeCSS()` não, para não
  embutir inline e poluir o diff do `ui`.
- **Cabeçalho.** `DESIGN.md` §Typography: "Não usar títulos grandes". Um `div`
  de uma linha em `typography.label` (11px, caixa alta, `letter-spacing .06em`,
  `ink-muted`) com "Draft War Room" substitui o `<h2>` do `titlePanel`.

## Verification

**Commands:**
- `make test` — status 0; inclui a linha "story 9" e mantém "story 8 offline
  checks OK".
- `Rscript -e 'source("app.R"); cat(as.character(ui))'` — a saída contém
  `href="styles.css"` e os ids `banner`, `recs_table`, `roster_table`,
  `recent_picks_table`, `available_table`, `player_choice`, `draft_btn`,
  `undo_btn`, `pos_filter`.

**Manual checks:**
- `make app`: fundo `#0B0F14`, fonte mono, tabelas densas com borda fina, botão
  Draft verde, contorno de foco azul ao navegar por Tab; draftar um jogador e
  conferir que as tabelas atualizam igual à story 8 (só o visual mudou).

## Suggested Review Order

**O shell escuro (a folha de estilo)**

- Entrada: tokens exatos de `DESIGN.md` em `:root` + `color-scheme: dark` — a base de tudo.
  [`styles.css:25`](../../../../www/styles.css#L25)
- Comentário de cabeçalho: o que foi copiado verbatim, o que foi adaptado, e o que é escopo das stories 10/11/14.
  [`styles.css:18`](../../../../www/styles.css#L18)
- Restyle das superfícies do Bootstrap: `body`/`.container-fluid` no canvas, `.row` zerando a margem `-15px` (evita scrollbar em janela estreita).
  [`styles.css:71`](../../../../www/styles.css#L71)
- Cabeçalho enxuto em `typography.label` no lugar do `<h2>` do `titlePanel`.
  [`styles.css:80`](../../../../www/styles.css#L80)
- Gaps do restyle fechados na revisão: hover do dropdown do selectize e bloco de erro de render, ambos escuros.
  [`styles.css:253`](../../../../www/styles.css#L253)

**O adapter (app.R) — só chrome**

- 3 edições: `tags$head` com `<title>` (recuperado do `titlePanel`) + `<link>`, `div.app-header`, `class="recs-note"`. `server()` intocado.
  [`app.R:38`](../../../../app.R#L38)

**Testes (offline)**

- Bloco story 9: tokens no CSS, guarda anti-rede (`@import`/`url(http`), `ui` renderizada mantém `<title>`, `.app-header` e os 10 ids da story 8.
  [`smoke.R:1882`](../../../../tests/smoke.R#L1882)
- Matrix row 3 (CSS ausente em runtime): copy + `finally` de restore + assert — `file.rename` cross-filesystem podia perder o `styles.css` do repo.
  [`smoke.R:1953`](../../../../tests/smoke.R#L1953)
