---
title: 'Faixa de estado fixa (A2)'
type: 'feature'
created: '2026-09-03'
status: 'done'
review_loop_iteration: 1
baseline_commit: 'f8cd5c1a662aec774a149239d8006133f5083d9b'
context:
  - '/Users/gsposito/Projects/football/DraftWarRoom/_bmad-output/specs/spec-fantasy-warroom/SPEC.md'
  - '/Users/gsposito/Projects/football/DraftWarRoom/AGENTS.md'
  - '/Users/gsposito/Projects/football/DraftWarRoom/docs/design/DESIGN.md'
  - '/Users/gsposito/Projects/football/DraftWarRoom/docs/design/EXPERIENCE.md'
---

<frozen-after-approval reason="human-owned intent — do not modify unless human renegotiates">

## Intent

**Problem:** `app.R` mostra o estado do draft como uma linha de texto
(`textOutput("banner")` num `h3`) que rola com a página. `DESIGN.md` pede uma
**Faixa de estado** fixa com o overall pick em `typography.display`, time no
relógio e próximo pick do operador sempre visíveis antes de qualquer ranking;
`EXPERIENCE.md` põe o último pick registrado nessa faixa.

**Approach:** Trocar `h3(textOutput("banner"))` por `uiOutput("status_strip")`,
posicionado como **filho direto de `fluidPage()`**, logo após `div.app-header` —
o `fluidRow(column(12, ...))` que continha o `h3` é removido. Um `renderUI`
compõe: `PICK N` em display type (verde `action` no pick vivo), `Round NN · no
relógio` + time, `Próximo: seu pick M`, a linha `Último: overall · jogador —
pos · time NFL · time` derivada de `state()$picks` + snapshot, e o texto
estático `sessão local · salva`. CSS `.status-strip { position: sticky; top: 0 }`
fixa a faixa no topo do conteúdo enquanto se rola. Só apresentação sobre views
já derivadas — nenhuma função de core, reactive de dados, contrato RDS ou
persistência muda. Atualiza os asserts das stories 8–9 que liam o formato
textual antigo de `output$banner`.

## Boundaries & Constraints

**Always:**
- A faixa é um **filho direto de `fluidPage()`**, no mesmo nível de
  `div.app-header` (introduzido pela story 9). O `fluidRow`/`column(12)` que
  continha o `h3` sai. Isso **não** é a grade de layout da story 14 — é um
  elemento de cabeçalho, exatamente como `.app-header` já é hoje. Só a faixa
  muda de lugar; toda a árvore `fluidRow`/`column` das outras seções fica
  intocada.
- Renderização pura sobre as mesmas chamadas de core que `output$banner` já
  faz: `derive_draft_view(state(), snapshot)`, `next_user_pick(state())`, e
  `state()$picks` + `snapshot$players` para o último pick. Nenhuma fórmula,
  símbolo de RNG ou de rede novo (o bloco `(8h)` de `tests/smoke.R` vigia).
- O último pick é derivado a cada render de `state()$picks[nrow, ]` +
  `make_snake_schedule()` + `state$team_order` + `snapshot$players` (mesma
  lógica de `output$recent_picks_table`); nunca persistido nem posto em
  reactiveVal.
- `PICK N` usa `typography.display` (18px/700 mono); no pick vivo,
  `components.status-strip.current-pick` (fundo `action` `#57D68D`, texto
  `action-ink`). Estado concluído usa um tratamento visual distinto do fundo
  `surface` da própria faixa (borda ou `ink-muted`), não o mesmo fundo.
- `.status-strip` é `position: sticky; top: 0` com fundo opaco `surface`; o
  scroll-container (`body` / `.container-fluid`) recebe `scroll-padding-top`
  igual à altura aproximada da faixa, para o foco de Tab não ficar escondido
  atrás dela.
- Em janela estreita (o caso docado ao lado da ESPN), a faixa não pode
  provocar scroll horizontal: filhos flex com `min-width: 0` e a linha do
  último pick com `overflow-wrap`.
- Estado concluído e "não está na vez" comunicados por texto além de cor. A
  faixa carrega um `aria-label` estático (ex.: `"Estado do draft"`) — rótulo,
  não `role` nem região `aria-live` (isso é a story 21). Microcopy segue a
  tabela Voice and Tone de `EXPERIENCE.md` (`Pick 73 — Team Rocket`, `Próximo:
  seu pick 76`): factual, sem celebração nem alarmismo. Quando o operador não
  tem mais picks, a linha lê `Próximo: —` (sem "seu pick").
- `app.R` continua adapter fino; sem pacote novo no `renv.lock`, sem JavaScript
  próprio. CSS só em `www/styles.css`, tokens verbatim de `DESIGN.md`, sem
  asset remoto.

**Ask First:**
- Reestruturar as outras seções em regiões workspace/wide/audit, ou tornar
  qualquer painel colapsável — é a story 14.
- Adicionar pacote ao `renv.lock`.
- Persistir o último pick, indicador dinâmico de "salvando…", ou log de eventos
  — fora de escopo (stories 13/18/25 e restrições de persistência).

**Never:**
- Smart-list de candidatos, painel de inspeção, board em grade, undo
  redesenhado, teclado, `aria-live` / `role` (stories 11–21).
- Rede, `ffanalytics`, leitura de `yaml` nova, mudança em `state/draft.rds` /
  `data/projections.rds`, Shiny modules.
- Recalcular round, time ou próximo pick na view — já vêm de
  `derive_draft_view()` / `next_user_pick()`.

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| Draft novo | `state/draft.rds` ausente (0 picks) | `PICK 1` display verde, `Round 01 · no relógio` + `Team 01`, `Próximo: seu pick <M>`, `Último: —`, `sessão local · salva` | N/A |
| Meio de draft, oponente na vez | 15 picks | `PICK 16`, round/time do schedule, `Próximo: seu pick <M>`, `Último: 15 · <jogador> — <pos> · <time NFL> · <time>` do pick 15 | N/A |
| Operador na vez | próximo overall é do operador | `Próximo: seu pick <overall atual>`, sem contradição com o pick vivo | N/A |
| Usuário sem picks restantes | picks além do último slot do operador | linha `Próximo: —` | N/A |
| Draft completo | 180 picks | `DRAFT COMPLETO · 180 picks` em texto com tratamento distinto, sem `Round`/`no relógio`; `Último` = pick 180 | N/A |
| Rolagem da página | qualquer estado, conteúdo abaixo da faixa | a faixa permanece colada no topo do conteúdo (`.container-fluid` é o bloco contêiner do sticky) | N/A |
| `styles.css` ausente em runtime | `www/styles.css` removido | faixa sem estilo (não fixa), sem erro de servidor | página funcional |

</frozen-after-approval>

## Code Map

- `app.R:37-46` — `fluidPage(tags$head(...), div(class="app-header", ...),
  fluidRow(column(12, h3(textOutput("banner")))), fluidRow(...))`. **Remover** o
  `fluidRow(column(12, h3(textOutput("banner"))))` e **inserir**
  `uiOutput("status_strip")` como filho direto de `fluidPage`, imediatamente
  após `div(class="app-header", ...)`.
- `app.R:193-203` — `output$banner <- renderText({...})` usa `view()`,
  `next_user_pick(state())`, `v$round_on_clock`, `v$current_overall`,
  `v$team_on_clock`, `v$is_complete` → **substituir** por
  `output$status_strip <- renderUI({...})` com os mesmos dados + a linha do
  último pick (incl. `nfl_team`).
- `app.R:241-261` — `output$recent_picks_table` já deriva overall/jogador/pos/
  time de `picks` + `make_snake_schedule()` + `team_order` + `snapshot$players`;
  **reusar o padrão** só para a última linha. Sem novo helper de core; um
  fechamento local dentro de `server()` é aceitável se remover a duplicação.
- `app.R:21` — `%||%` disponível.
- `R/core.R:392-461` — `derive_draft_view()` retorna `current_overall`,
  `is_complete`, `round_on_clock`, `team_on_clock`; `next_user_pick()` → inteiro
  ou `NA_integer_`. `load_state()` (`R/persistence.R:91`) já valida
  `user_team %in% team_order`, então `next_user_pick()` não dá `stop()` no
  caminho da faixa.
- `snapshot$players` — colunas `player_id`, `player`, `nfl_team`, `pos`,
  `points`, ... (ver `rds-contracts.md`).
- `docs/design/DESIGN.md` frontmatter — `components.status-strip`,
  `typography.display`, `typography.label`, `spacing`; `§Components` "Faixa de
  estado".
- `docs/design/EXPERIENCE.md` — "Voice and Tone"; "Component Patterns" / "Faixa
  de estado"; "Accessibility Floor" (foco visível "inclusive abaixo da faixa
  fixa").
- `docs/design/mockups/live-war-room.html:102-108` — espelho de referência
  (`.utility`, `.status`, `.live-pick`, `.clock` `Round 7 · no relógio` /
  `Team Rocket`, `.next`, `.last` `72 · D. Smith` / `WR · PHI · Team Apex`).
- `www/styles.css:1-23` — comentário de cabeçalho marca a faixa como story 10 →
  **atualizar**. `:64-74` zerou as margens de `.row`; `:76-91` bloco
  `.app-header` — **adicionar** `.status-strip` depois dele; adicionar
  `scroll-padding-top` a `body`/`.container-fluid`.
- `tests/smoke.R` — (8a) `:1642-1651`, (8b) `:1660-1678`, (8f) `:1805-1819`,
  (8f2) `:1821-1831`, loop de ids da story 9 `:1947-1951` — **atualizar** os
  asserts sobre `output$banner`/`id="banner"` para `output$status_strip`/
  `status_strip`. Story 9 fecha em `:1981`; guard de `prepare.R` em `:1983` —
  **inserir** o bloco `## --- story 10` entre os dois.

## Tasks & Acceptance

**Execution:**
- [x] `app.R` — mover a faixa: remover `fluidRow(column(12,
  h3(textOutput("banner"))))`; `uiOutput("status_strip")` como filho direto de
  `fluidPage`, após `div.app-header`. `output$status_strip <- renderUI(...)`
  compondo `PICK N` (display / verde no vivo; concluído com tratamento
  distinto), `Round NN · no relógio` + time, `Próximo: seu pick M` /
  `Próximo: —` quando `NA`, `Último: overall · jogador — pos · nfl_team · time`
  (`—` com 0 picks), `DRAFT COMPLETO · N picks` quando completo, texto estático
  `sessão local · salva`, e `aria-label` na `div` da faixa. Nada em `server` /
  outros `output$*` / ids muda.
- [x] `www/styles.css` — atualizar o comentário de cabeçalho; adicionar
  `.status-strip` (`position: sticky; top: 0`, `z-index` acima das tabelas,
  fundo `surface`, borda `border`, `border-radius: var(--radius-sm)`, padding
  `--space-2`/`--space-3`), `.status-strip .live-pick` (display type; `action` /
  `action-ink` no `--current`; borda `border` no estado concluído),
  `.status-strip-main` (flex com `min-width: 0` nos filhos), a linha do último
  pick com `overflow-wrap`, rótulos em `typography.label` / `ink-muted`,
  `.status-strip-saved` em `ink-muted`, e `scroll-padding-top` no scroll-
  container. Só tokens de `DESIGN.md`.
- [x] `tests/smoke.R` — atualizar (8a)/(8b)/(8f)/(8f2) e o loop de ids da story
  9 para `output$status_strip` / id `status_strip`; adicionar o bloco
  `## --- story 10`: em cada cenário da matriz a faixa renderiza `PICK <n>` (ou
  `DRAFT COMPLETO · <n> picks`), contém o time no relógio e o `seu pick` /
  `Próximo: —` de `next_user_pick()`, a linha do último pick bate com `picks` +
  schedule + snapshot **incluindo `nfl_team`**, e a classe `live-pick--current`
  aparece só no pick vivo (ausente no concluído);
  `as.character(htmltools::renderTags(ui)$html)` contém `id="status_strip"` como
  filho de `.container-fluid` fora de qualquer `.row`, não contém `id="banner"`,
  e mantém os outros ids da story 8; `www/styles.css` contém `.status-strip`,
  `sticky` e `scroll-padding-top`, sem `@import` / `url(http` novo.

**Acceptance Criteria:**
- Given `make test` sem rede, when executado, then status 0 com os blocos das
  stories 1–10; os asserts de conteúdo das stories 5–8 fora do `banner` passam
  sem edição e as linhas "story 8 offline checks OK" / "story 9 offline checks
  OK" continuam aparecendo.
- Given `Rscript -e 'source("app.R"); cat(as.character(htmltools::renderTags(ui)$html))'`,
  when revisado, then há `id="status_strip"` como filho direto de
  `.container-fluid` (não dentro de um `.row`), nenhum `id="banner"`, e os ids
  `recs_table`, `roster_table`, `recent_picks_table`, `available_table`,
  `player_choice`, `draft_btn`, `undo_btn`, `pos_filter` seguem presentes.
- Given `git diff app.R`, when revisado, then as mudanças são só: a faixa
  movida para fora do `fluidRow` e o `renderUI` no lugar do `renderText`; nada
  em `record_pick`/`undo_pick`/`save_state`/`commit_state`/`view`/`recs` ou nos
  outros `render*`.
- Given `grep -nE "bslib|sass|includeCSS|shinyjs|tags\\$script|Shiny\\.setInputValue" app.R`,
  when comparado ao estado anterior, then nenhuma ocorrência nova.

## Spec Change Log

- **2026-09-03 — loop 1 (intent_gap: `position: sticky` não colava).** O
  revisor apontou que a faixa dentro de `fluidRow(column(12, ...))` tem
  `.col-sm-12` (altura da faixa) como bloco contêiner do sticky, então ela
  descola já no primeiro pixel de rolagem — o requisito central da story
  ("faixa fixa") ficava não atendido. **Renegociado com o humano:** a faixa
  passa a ser filho direto de `fluidPage()` (irmão de `div.app-header`), o
  `fluidRow`/`column` vazio é removido; `.container-fluid` vira o bloco
  contêiner e o sticky funciona. Estado-ruim evitado: entregar a story com uma
  "faixa fixa" que não fixa. **KEEP da tentativa revertida:** o `renderUI`
  único ("atualiza como uma unidade"); a derivação do último pick reusando o
  padrão de `output$recent_picks_table`; o bloco de teste dirigido pela matriz;
  os retargets de (8a)/(8b)/(8f)/(8f2); a classe `live-pick--current` para o
  verde. **Dobrado neste loop** (achados válidos da revisão): `nfl_team` na
  linha do último pick (paridade com o mockup); `Próximo: —` no caso `NA` em
  vez de `Próximo: seu pick —`; `aria-label` estático na faixa; guarda de
  overflow para janela estreita; tratamento visual distinto do estado
  concluído; `scroll-padding-top` para o foco de Tab não sumir atrás da faixa.

## Design Notes

- **Por que filho direto de `fluidPage`.** Um elemento `position: sticky` só
  fica preso enquanto seu bloco contêiner (o pai) está visível. Dentro de
  `column(12)`, o pai tem a altura da faixa e sai de vista imediatamente. Como
  filho direto de `fluidPage`, o pai é `.container-fluid`, que contém todo o
  conteúdo rolável — a faixa fica presa a página inteira. `div.app-header` já é
  um filho direto assim; a faixa segue o mesmo padrão, não é a grade da story
  14.
- **Por que `renderUI` e não vários `textOutput`.** A faixa "atualiza como uma
  unidade" (`EXPERIENCE.md`) e precisa de markup semântico com classes
  distintas para display type vs rótulos. Um `renderUI` único mantém `app.R`
  legível e o teste assevera sobre uma string de HTML — formatação pura, como
  os `renderTable` vizinhos.
- **Último pick.** `p <- state()$picks; last <- p[nrow(p), ]` e então
  `st$team_order[make_snake_schedule(...)$slot[last$overall]]` +
  `snapshot$players[match(last$player_id, ...), ]` para `player`, `pos`,
  `nfl_team` — idêntico ao que `output$recent_picks_table` já faz. Um fechamento
  local em `server()` pode compartilhar a derivação de time entre os dois sem
  criar função de core.
- **`sessão local · salva`.** Texto estático: todo pick aceito salva
  atomicamente antes de o reactiveVal atualizar (`AGENTS.md`). Indicador
  dinâmico seria a story 13.
- Exemplo (meio de draft): `PICK 16 · Team 04 · Round 02 · no relógio ·
  Próximo: seu pick 21 · Último: 15 · J. Chase — WR · CIN · Team 03 · sessão
  local · salva`.

## Verification

**Commands:**
- `make test` — status 0; inclui "story 10" e mantém "story 8 offline checks OK"
  e "story 9 offline checks OK".
- `Rscript -e 'source("app.R"); cat(as.character(htmltools::renderTags(ui)$html))'`
  — `id="status_strip"` presente, filho de `.container-fluid` fora de `.row`;
  sem `id="banner"`.
- `grep -n "status-strip\|sticky\|scroll-padding" www/styles.css` — presentes.

**Manual checks:**
- `make app`: faixa no topo, `PICK N` grande em mono, verde no pick vivo; rolar
  a página **mantém a faixa colada** no topo, sobre as tabelas; registrar um
  pick e conferir PICK / relógio / próximo / último mudando juntos; navegar por
  Tab e conferir que o controle focado não fica atrás da faixa; janela estreita
  não gera scroll horizontal; remover `www/styles.css` e recarregar — sem erro
  de servidor.

## Suggested Review Order

**A faixa (o que renderiza e por quê)**

- Ponto de entrada: a faixa saiu do `fluidRow` e virou filho direto de
  `fluidPage`, para `.container-fluid` ser o bloco contêiner do sticky.
  [`app.R:48`](../../../../app.R#L48)
- Um `renderUI` único ("atualiza como uma unidade") sobre `derive_draft_view()`
  + `next_user_pick()` — mesmas chamadas de core que o `output$banner` fazia.
  [`app.R:201`](../../../../app.R#L201)
- Linha do último pick: derivada a cada render de `picks` + schedule + snapshot,
  como `output$recent_picks_table`; nada persistido.
  [`app.R:207`](../../../../app.R#L207)
- Guarda de `nfl_team` (campo opcional do contrato): dropa em vez de imprimir
  `NA`.
  [`app.R:219`](../../../../app.R#L219)
- Ramo concluído vs vivo: `live-pick--done` (cresce/quebra, borda `ink-muted`)
  vs `live-pick--current` (verde `action`); clock/próximo só no ramo vivo.
  [`app.R:232`](../../../../app.R#L232)

**O sticky (CSS, tokens de DESIGN.md)**

- `.status-strip` sticky no topo, fundo/texto opacos, `z-index` acima das
  tabelas.
  [`styles.css:105`](../../../../www/styles.css#L105)
- `scroll-padding-top` para o foco de Tab não cair atrás da faixa fixa.
  [`styles.css:121`](../../../../www/styles.css#L121)
- `.status-strip-next` em `ink` (não `action` — verde não é cor decorativa,
  DESIGN.md §Colors).
  [`styles.css:193`](../../../../www/styles.css#L193)
- `.live-pick--done`: `flex: 1 1 auto` + `white-space: normal` para o texto
  longo não forçar scroll horizontal em janela estreita.
  [`styles.css:161`](../../../../www/styles.css#L161)

**Testes (offline)**

- Bloco story 10: matriz dirigida por `k ∈ {0,15,24,170,179,180}` cobrindo os
  ramos e a fronteira vivo/concluído.
  [`smoke.R:1990`](../../../../tests/smoke.R#L1990)
- Guarda anti-regressão do loop 1: assevera `position: sticky` no corpo da
  regra `.status-strip`, sem contar os comentários.
  [`smoke.R:2031`](../../../../tests/smoke.R#L2031)
- Retargets de (8a)/(8b)/(8f)/(8f2) e do loop de ids da story 9 para
  `status_strip`.
  [`smoke.R:1655`](../../../../tests/smoke.R#L1655)
