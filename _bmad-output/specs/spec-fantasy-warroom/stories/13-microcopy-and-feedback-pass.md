---
title: 'Microcopy e feedback pass (A5)'
type: 'feature'
created: '2026-09-03'
status: 'done'
review_loop_iteration: 0
baseline_commit: 'e07fc8f9f03765544aa77d467aa038ae2affda08'
context:
  - '/Users/gsposito/Projects/football/DraftWarRoom/_bmad-output/specs/spec-fantasy-warroom/SPEC.md'
  - '/Users/gsposito/Projects/football/DraftWarRoom/AGENTS.md'
  - '/Users/gsposito/Projects/football/DraftWarRoom/docs/design/DESIGN.md'
  - '/Users/gsposito/Projects/football/DraftWarRoom/docs/design/EXPERIENCE.md'
---

<frozen-after-approval reason="human-owned intent — do not modify unless human renegotiates">

## Intent

**Problem:** O feedback de pick em `app.R` hoje sai por `showNotification()` —
um toast que some sozinho, viola "erros persistem até o operador poder agir"
(`DESIGN.md` §Components "Feedback e erro") e "toasts não podem encobrir busca,
pick atual ou foco". Não há confirmação de registro ("Registrado: X") em lugar
nenhum, e as mensagens ("pick rejeitado:", "nada a desfazer:", "selecione um
jogador...") não seguem a tabela Voice and Tone de `EXPERIENCE.md`. Vários
rótulos estáticos estão sem acento ("Recomendacoes", "Disponiveis", "buscar
jogador disponivel...", "Filtrar disponiveis por posicao").

**Approach:** Substituir os três `showNotification()` por uma **região de
feedback persistente** (`uiOutput("draft_feedback")`) posicionada imediatamente
abaixo de `uiOutput("status_strip")` — alimentada por um `reactiveVal(feedback)`
que guarda o último evento (`kind` = `"ok"` | `"error"`, `text`). Confirmações
usam verde (`components.feedback-error.success` = `action`), erros usam
`danger` e **não** somem — ficam até o próximo evento. Aplicar Voice and Tone a
cada string (`Registrado: <jogador>`, `Já escolhido no pick <N>. Busque outro
jogador.`, `Undo aplicado — pick <N> voltou a aberto.`, `Nada a desfazer —
nenhum pick efetivo.`, `Selecione um jogador na busca antes de registrar.`) e
acentuar os rótulos estáticos. CSS novo em `www/styles.css`, tokens verbatim de
`DESIGN.md`.

## Boundaries & Constraints

**Always:**
- `record_pick()` / `undo_pick()` continuam chamados exatamente como hoje, na
  mesma ordem, dentro do mesmo `tryCatch` de `observeEvent`; `commit_state()`
  (save_state → `state(new_st)`) inalterado. A região de feedback só é escrita
  **depois** de o `commit_state()` ter tido sucesso (no ramo de sucesso) ou no
  `error =` do `tryCatch`. Nenhuma mudança em quando/como o estado é salvo.
- A mensagem "Já escolhido no pick <N>." é derivada de `state()$picks`
  (`overall` da linha cujo `player_id == pid`) **dentro do `error =`**, quando
  `conditionMessage(e)` contém `"already been drafted"` (texto do core,
  `R/core.R:346-347`). Todo outro erro de `record_pick()` cai em
  `Pick não registrado: <conditionMessage(e)>` — inclui draft cheio, id
  desconhecido e falha de `save_state()` (nesse caso `state()` fica intacto e a
  região mostra o erro: o pick não é apresentado como confirmado).
- Seleção vazia (`is.null(pid) || !nzchar(pid)`) continua um pré-check com
  `return()` antes de `record_pick()` — só troca o `showNotification()` por
  `feedback(list(kind = "error", text = "Selecione um jogador na busca antes de registrar."))`.
- Undo: capturar `state()$picks[nrow(picks), ]` **antes** de `undo_pick()`;
  no sucesso → `feedback(list(kind = "ok", text = sprintf("Undo aplicado — pick %d voltou a aberto.", ov)))`.
  Sem picks → o `error =` do `tryCatch` grava
  `Nada a desfazer — nenhum pick efetivo.` (não repassa `conditionMessage`).
- Confirmação de pick: nome do jogador via `snapshot$players$player[match(pid,
  snapshot$players$player_id)]` (mesmo join que a faixa de estado e
  `recent_picks_table` usam) → `Registrado: <jogador>`.
- `feedback` inicia `NULL`; `output$draft_feedback <- renderUI({...})` devolve
  um container vazio (`tags$div(class = "draft-feedback", ...)` sem filho) quando
  `NULL`, uma linha com classe `draft-feedback--ok` / `draft-feedback--error`
  caso contrário. Sem timer / `invalidateLater` / auto-clear: a região só muda
  quando um novo pick ou undo acontece.
- `outputId` novos: só `draft_feedback`. Todos os ids das stories 8–12
  (`status_strip`, `recs_note`, `recs_table`, `recs_pos_filter`, `roster_table`,
  `recent_picks_table`, `available_table`, `player_choice`, `draft_btn`,
  `undo_btn`, `pos_filter`) permanecem.
- Rótulos estáticos acentuados sem mudar sentido: `h4("Recomendações")`,
  `h4("Disponíveis")`, `selectInput` label `"Filtrar disponíveis por posição"`,
  `selectizeInput` placeholder `"buscar jogador disponível..."`. `draft_btn`
  passa a `"Registrar"` (consistente com "Registrado:"). `undo_btn` continua
  `"Undo"` (termo da tabela Voice and Tone).
- `app.R` continua adapter fino: sem pacote novo no `renv.lock`, sem JavaScript
  próprio, sem `bslib` / `sass` / `includeCSS` / `shinyjs` / `tags$script` /
  `Shiny.setInputValue`. Nenhum símbolo de rede / RNG. `recommend_players()`
  chamado 1× no código. CSS só em `www/styles.css`, sem asset remoto.

**Ask First:**
- Região `aria-live` / `aria-atomic` / `role="status"` que anuncia o evento — é
  a story 21 (um `aria-label` estático no contêiner é aceitável; `role` de live
  region não).
- Reestruturar seções em regiões workspace/wide ou painéis colapsáveis — story 14.
- Estado "Registrando" (controle focado + `disabled` + motivo acessível) — é
  interação/a11y das stories 19/21.
- Reescrever o aviso de off-turn em `output$recs_note` — a frase é **duplicada**
  literalmente em `app.R` e `scripts/draft.R:97` (cópia de adapter, não do core);
  um pass de cópia compartilhada é mudança própria. Registrar em
  `deferred-work.md`, não tocar aqui.

**Never:**
- Board em grade, painel de inspeção, undo redesenhado, combobox de busca,
  teclado (stories 14–21).
- Rede, `ffanalytics`, leitura de `yaml` nova, mudança em `state/draft.rds` /
  `data/projections.rds`, Shiny modules, nova função de core, mudança em
  `R/`.
- Recalcular qualquer campo de recomendação/roster na view; re-chamar
  `recommend_players()`; manter qualquer `showNotification()` em `app.R`.
- Mudar texto de mensagem em `R/core.R`, `R/recommendation.R` ou
  `scripts/draft.R`.

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| Pick aceito | `player_choice` = id disponível, clica `draft_btn` | `state()$picks` +1; `output$draft_feedback` = linha `draft-feedback--ok` com texto `Registrado: <jogador>` | N/A |
| Seleção vazia | `player_choice` vazio/`NULL`, clica `draft_btn` | `state()` intacto; região = `draft-feedback--error` `Selecione um jogador na busca antes de registrar.` | pré-check, `return()` antes de `record_pick()` |
| Jogador já escolhido | `player_choice` = id já em `picks`, clica `draft_btn` | `state()` intacto; região = `draft-feedback--error` `Já escolhido no pick <N>. Busque outro jogador.` (`N` = `overall` da linha) | `record_pick()` chamado, erro capturado, `N` derivado de `state()$picks` |
| Draft cheio / id inválido | `record_pick()` lança outro erro | `state()` intacto; região = `Pick não registrado: <conditionMessage>` | erro capturado no `error =` |
| Falha de `save_state()` | `commit_state()` lança em `save_state()` | `state()` intacto (pick não confirmado); região = `Pick não registrado: <conditionMessage>` | erro capturado; região persiste |
| Undo com pick | ≥1 pick, clica `undo_btn` | `state()$picks` −1; região = `draft-feedback--ok` `Undo aplicado — pick <N> voltou a aberto.` (`N` = `overall` do pick removido, capturado antes) | N/A |
| Undo sem pick | 0 picks, clica `undo_btn` | `state()` intacto; região = `draft-feedback--error` `Nada a desfazer — nenhum pick efetivo.` | erro de `undo_pick()` capturado, mensagem própria |
| Persistência do erro | após um erro, outro input não relacionado muda (ex.: `pos_filter`) | `output$draft_feedback` ainda mostra o mesmo erro — sem auto-clear | N/A |
| Estado inicial | sessão recém-aberta, nenhum evento | `output$draft_feedback` = `tags$div(class="draft-feedback")` sem filho (nada visível) | N/A |
| `styles.css` ausente | `www/styles.css` removido em runtime | região monta sem estilo, sem erro de servidor | página funcional |

</frozen-after-approval>

## Code Map

- `app.R:37-48` — `ui <- fluidPage(tags$head(...), div(class="app-header", ...),
  uiOutput("status_strip"), ...)`. **Inserir** `uiOutput("draft_feedback")`
  imediatamente após `uiOutput("status_strip")` (irmão, "próxima à barra de
  estado", `DESIGN.md:171`).
- `app.R:51-62` — `fluidRow` com `selectizeInput("player_choice", "Jogador",
  options=list(placeholder="buscar jogador disponivel..."))`,
  `actionButton("draft_btn", "Draft")`, `actionButton("undo_btn", "Undo")`,
  `selectInput("pos_filter", "Filtrar disponiveis por posicao", ...)`.
  **Acentuar** placeholder e label de `pos_filter`; `draft_btn` → `"Registrar"`.
- `app.R:64-72` — `h4("Recomendacoes")` → `h4("Recomendações")`.
- `app.R:76` — `h4("Seu roster")` e `h4("Picks recentes")` — já corretos, não
  tocar. **`app.R:81`** — `h4("Disponiveis")` → `h4("Disponíveis")`.
- `app.R:137` — `state <- reactiveVal(init_state)`. **Adicionar** logo depois
  `feedback <- reactiveVal(NULL)`.
- `app.R:143-146` — `commit_state <- function(new_st) { save_state(...);
  state(new_st) }`. **Não mudar.** O feedback é escrito pelos `observeEvent`,
  não aqui.
- `app.R:174-187` — `observeEvent(input$draft_btn, {...})`. Hoje: pré-check de
  `pid` com `showNotification(..., "warning")` + `return()`; `tryCatch` com
  `record_pick()` → `commit_state()` → `updateSelectizeInput(selected="")`, e
  `error =` com `showNotification(paste("pick rejeitado:", ...), "error")`.
  **Reescrever**: pré-check → `feedback(list(kind="error", text="Selecione um
  jogador na busca antes de registrar."))`; sucesso → após `commit_state()`,
  `feedback(list(kind="ok", text=sprintf("Registrado: %s", nome)))` (nome via
  `match(pid, snapshot$players$player_id)`); `error =` → deriva
  `"already been drafted"` vs genérico como nas Boundaries.
- `app.R:189-196` — `observeEvent(input$undo_btn, {...})`. Hoje: `tryCatch`
  `undo_pick()` → `commit_state()`, `error =` `showNotification(paste("nada a
  desfazer:", ...))`. **Reescrever**: capturar `pk <- state()$picks`;
  `ov <- if (nrow(pk)) pk$overall[nrow(pk)] else NA`; sucesso →
  `feedback(list(kind="ok", text=sprintf("Undo aplicado — pick %d voltou a aberto.", ov)))`;
  `error =` → `feedback(list(kind="error", text="Nada a desfazer — nenhum pick efetivo."))`.
- `app.R:206-257` — `output$status_strip <- renderUI(...)`. **Não tocar** —
  serve de modelo para o `renderUI` da região de feedback (formatação pura,
  `tags$div` com classe).
- `app.R:259-263` — `output$recs_note <- renderText(...)`. **Não tocar** (ver
  Ask First — a frase é duplicada em `scripts/draft.R:97`).
- `R/core.R:344-348` — `stop("record_pick(): player_id '", player_id, "' has
  already been drafted")`. Fonte do texto que o `grepl("already been drafted")`
  reconhece. **Não alterar.**
- `R/core.R:372-374` — `undo_pick()` `stop("... there are no picks to undo")` —
  capturado e substituído pela mensagem própria.
- `docs/design/DESIGN.md:99-101` — `components.feedback-error` (`success` =
  `{colors.action}`, `error` = `{colors.danger}`). `:171` — regra "confirmação
  breve, textual, próxima à barra de estado; erros persistem". `:132` — verde só
  para pick vivo / **confirmação** / ação (a confirmação de registro É um uso
  legítimo do verde).
- `docs/design/EXPERIENCE.md:46-56` — tabela Voice and Tone (as strings-alvo).
  `:77-101` — State Patterns ("Nome ambíguo, inválido ou já escolhido",
  "Registrando", "Pick confirmado", "Falha local de persistência").
- `www/styles.css:1-43` — header comment (termina na story 12) → **atualizar**
  com o parágrafo da story 13. `:680-699` bloco `.shiny-notification*` — pode
  ficar (inofensivo) ou ser removido junto com os `showNotification`; **manter**
  para não alargar o diff. `:728-733` `.recs-note` — não tocar. **Adicionar** o
  bloco `.draft-feedback` (tokens `DESIGN.md`: `surface`, `border`, `radius-sm`,
  `space-2`; borda-esquerda `--action` no `--ok`, `--danger` no `--error`;
  `typography.data`).
- `tests/smoke.R:1634-1653` — `.s8_bake_server`, `.strip_html`, `.html_count`
  (reusáveis). `:1693-1720` bloco `(8c)` — comentário menciona
  `showNotification`; o teste só checa `state()` intacto, segue válido (mas
  **atualizar** o comentário). `:1642-1647` `.strip_html` serve para
  `output$draft_feedback`.
- `tests/smoke.R:2742` — fim do bloco `story 12`; `:2744` começa o guard do
  `prepare.R`. **Inserir** o bloco `## --- story 13` entre os dois.
- `tests/smoke.R:2699-2740` — `(12j)` estáticas de UI/CSS/`app.R` — modelo para
  as estáticas da story 13 (lista de ids, grep de `bslib|sass|...`, RNG, rede).
- `R/projections.R` `build_synthetic_projections()` — fixture: `player`/`player_id`
  (`SYN-QB-001` …), `points`/`vor` decrescentes, sempre traz `nfl_team`.

## Tasks & Acceptance

**Execution:**
- [x] `app.R` — UI: inserir `uiOutput("draft_feedback")` após
  `uiOutput("status_strip")`; acentuar `h4("Recomendações")`,
  `h4("Disponíveis")`, label de `pos_filter` (`"Filtrar disponíveis por
  posição"`), placeholder de `player_choice` (`"buscar jogador disponível..."`);
  `draft_btn` → `"Registrar"`. Server: `feedback <- reactiveVal(NULL)` após
  `state <- reactiveVal(...)`; `output$draft_feedback <- renderUI({...})`
  (`NULL` → `tags$div(class="draft-feedback")` vazio; senão linha com classe
  `draft-feedback--ok`/`--error` e `aria-label` estático, sem `role` de live
  region).
  Reescrever `observeEvent(input$draft_btn)` e `observeEvent(input$undo_btn)`
  conforme o Code Map — `record_pick()`/`undo_pick()`/`commit_state()` intactos,
  só o `showNotification()` vira `feedback(...)`, com as strings Voice and Tone
  e o `N` derivado de `state()$picks`. Remover os 3 `showNotification()`.
- [x] `www/styles.css` — atualizar o header comment; adicionar `.draft-feedback`
  (contêiner: `surface`, `border` 1px, `radius-sm`, `padding` `space-2`
  `space-3`, `margin-bottom` `space-3`, `typography.data`; container vazio sem
  filho colapsa — `:empty { display: none }`), `.draft-feedback--ok`
  (borda-esquerda 3px `--action`) e `.draft-feedback--error` (borda-esquerda
  3px `--danger`, texto `--danger`). Só tokens de `DESIGN.md`, sem `@import` /
  `url(http`.
- [x] `tests/smoke.R` — bloco `## --- story 13` via `.s8_bake_server` +
  `shiny::testServer` + `.strip_html`, um teste por linha da matriz: pick aceito
  → `class="draft-feedback--ok"` e `Registrado: <player>`; seleção vazia →
  `--error` e a frase, `state()` intacto; jogador já escolhido (setar
  `player_choice` num id já em `picks`) → `Já escolhido no pick <N>.` com o
  `overall` certo, `nrow(picks)` inalterado; undo com pick → `--ok` `Undo
  aplicado — pick <N> voltou a aberto.`; undo sem pick → `--error` `Nada a
  desfazer — nenhum pick efetivo.`, `state()` intacto; persistência do erro →
  após um erro, `session$setInputs(pos_filter="RB")` e re-ler
  `output$draft_feedback` — mesmo texto de erro; estado inicial →
  `output$draft_feedback` é um `div.draft-feedback` sem filho (`.html_count` de
  `draft-feedback--` == 0). Strings não-ASCII construídas por `intToUtf8()`
  (arquivo ASCII-clean, como no bloco story 12). `styles.css` ausente:
  swap-and-restore como `(12i)` — a região monta sem erro. Estáticas: `id=
  "draft_feedback"` presente na UI **após** `id="status_strip"`; ids das stories
  8–12 intactos; `grep("showNotification", app.R)` == 0;
  `grep("bslib|sass|includeCSS|shinyjs|tags\\$script|Shiny\\.setInputValue",
  app.R)` sem ocorrência nova; sem símbolo de RNG/rede; `record_pick` /
  `undo_pick` / `recommend_players` não redefinidos e `recommend_players(`
  chamado 1×; `www/styles.css` contém `.draft-feedback`, sem asset remoto.
  Atualizar o comentário de `(8c)` que menciona `showNotification`.

**Acceptance Criteria:**
- Given `make test` sem rede, when executado, then status 0 com os blocos das
  stories 1–13; as linhas "story 8/9/10/11/12 offline checks OK" continuam e a
  equivalência `recs()` ↔ `recommend_players()` de `(8c)`/`(8e)` passa sem
  edição.
- Given `Rscript -e 'source("app.R"); cat(as.character(htmltools::renderTags(ui)$html))'`,
  when revisado, then há `id="draft_feedback"` e ele aparece **depois** de
  `id="status_strip"` no HTML; seguem presentes `recs_note`, `recs_table`,
  `recs_pos_filter`, `roster_table`, `recent_picks_table`, `available_table`,
  `player_choice`, `draft_btn`, `undo_btn`, `pos_filter`.
- Given `grep -n "showNotification" app.R`, when executado, then zero
  ocorrências.
- Given `git diff app.R`, when revisado, then as mudanças são só: o novo
  `uiOutput("draft_feedback")`, o `feedback` reactiveVal + `output$draft_feedback`,
  os dois `observeEvent` reescritos (troca de `showNotification` por `feedback`,
  derivação de `N`), e os rótulos acentuados / `draft_btn`; nada em
  `commit_state` / `record_pick` / `undo_pick` / `save_state` / `recs` / `view`
  / `recommend_players` / demais `render*` / `output$recs_note`.
- Given `grep -nE "bslib|sass|includeCSS|shinyjs|tags\$script|Shiny\.setInputValue" app.R`,
  when comparado ao estado anterior, then nenhuma ocorrência nova.

## Design Notes

- **Por que uma região, não um toast.** `DESIGN.md:171` é explícito: confirmação
  "próxima à barra de estado", erros "persistem até o operador poder agir",
  toasts não podem encobrir busca/pick/foco. Um `showNotification()` falha nos
  três pontos. A região é um `renderUI` sobre um `reactiveVal` — mesmo padrão
  das stories 10/11/12 (formatação pura, teste assevera sobre string de HTML).
- **Verde na confirmação.** `DESIGN.md:132` reserva `--action` para "pick vivo,
  **confirmação** e ação" — a confirmação de registro é o caso previsto; a borda
  verde aqui não conflita com a regra que barrou o verde no rótulo de slot do
  roster (story 12).
- **`N` derivado, não persistido.** "Já escolhido no pick N" e "pick N voltou a
  aberto" leem `state()$picks$overall` — fato já persistido, nunca um campo
  novo. O `grepl("already been drafted")` acopla ao texto do core
  (`R/core.R:346`); é uma string estável e testada, e a alternativa (pré-check
  que pula `record_pick()`) mudaria quando o core é chamado — o que
  `invoke_dev_with` proíbe.
- **Sem auto-clear.** Nada de `invalidateLater`/timer: a região só troca no
  próximo pick/undo. "Breve" (`DESIGN.md`) é sobre o texto, não sobre duração.
  O anúncio `aria-live` que lê o evento em voz é a story 21.
- Exemplo (ok): `<div class="draft-feedback draft-feedback--ok" aria-label="Feedback do registro">Registrado: Ja'Marr Chase</div>`.
  Exemplo (erro): `<div class="draft-feedback draft-feedback--error" aria-label="Feedback do registro">Já escolhido no pick 42. Busque outro jogador.</div>`.

## Verification

**Commands:**
- `make test` — status 0; inclui "story 13" e mantém "story 8/9/10/11/12 offline
  checks OK".
- `Rscript -e 'source("app.R"); cat(as.character(htmltools::renderTags(ui)$html))'`
  — `id="draft_feedback"` presente, após `id="status_strip"`; ids das stories
  8–12 intactos.
- `grep -n "showNotification" app.R` — nenhuma ocorrência.
- `grep -n "draft-feedback" www/styles.css` — presente.

**Manual checks:**
- `make app`: registrar um pick mostra `Registrado: <jogador>` numa linha verde
  logo abaixo da faixa de estado; tentar registrar sem seleção mostra a frase
  de erro em vermelho e ela **fica** enquanto o operador mexe em outros
  controles; `Undo` mostra `Undo aplicado — pick <N> voltou a aberto.`; `Undo`
  sem picks mostra `Nada a desfazer — nenhum pick efetivo.`; remover
  `www/styles.css` e recarregar — sem erro de servidor.

## Spec Change Log

- **2026-09-03 — revisão em 3 camadas (blind-hunter / edge-case / verification-gap), sem loopback.** Nenhum achado `intent_gap`/`bad_spec`; frozen intacto. Patches aplicados sobre o diff:
  - `app.R` handler de `undo_btn`: o ramo `error =` agora distingue falha real (`nrow(picks) > 0` → `Undo não aplicado: <motivo>`) de "sem picks" (`Nada a desfazer — nenhum pick efetivo.`). Antes, uma falha de `save_state()` durante undo seria reportada como "nada a desfazer" (edge-case #3, contradiz o State Pattern "Falha local de persistência").
  - `app.R`: guarda de `NA` em `n` (já-escolhido) e `ov` (undo) antes do `sprintf("%d")`, com fallback sem o número — defesa dentro do error handler (edge-case #2, blind #8).
  - `tests/smoke.R`: `(13e3)` (falha de `save_state`) agora pula com aviso — não falha — quando o `Sys.chmod` é no-op (suite como root em CI), detectado por sondagem de escrita; `on.exit` mal posicionado removido. Novo `(13a2)` (transição error→ok limpa a linha vermelha) e assert de `aria-label`; `(13f)` ganhou `session$elapse(60000)` para fixar a ausência de timer/auto-clear; asserts de `--ok` afrouxados de classe exata para substring.
  - Defers registrados em `deferred-work.md`: região de feedback não fica presa na rolagem sob a `.status-strip` sticky (→ story 14, que posiciona as regiões); clique com seleção vazia renderiza `--danger` persistente onde antes era `warning` transitório (spec frozen fixou `kind = "error"`; revisitar com story 21 ou uma taxonomia de `kind`).
  - KEEP: o `renderUI` sobre `feedback()` reactiveVal; as strings Voice and Tone; `N` derivado de `state()$picks$overall`; `record_pick()`/`undo_pick()`/`commit_state()` intocados; o bloco `.draft-feedback` com `:empty` colapsando; a estrutura do bloco de teste `## --- story 13` com um caso por linha da matriz.

## Suggested Review Order

**Região de feedback (entrada e renderização)**

- Ponto de entrada: o `uiOutput` irmão logo abaixo da faixa de estado — onde o feedback vive.
  [`app.R:54`](../../../../app.R#L54)
- O `reactiveVal` que guarda o último evento (`kind`/`text`), `NULL` antes do primeiro pick/undo.
  [`app.R:150`](../../../../app.R#L150)
- `renderUI` puro sobre `feedback()`: `NULL` → `div.draft-feedback` vazio (colapsa via `:empty`); evento → linha `--ok`/`--error`.
  [`app.R:307`](../../../../app.R#L307)

**Caminho de pick/undo (só o feedback mudou)**

- `draft_btn`: pré-check de seleção vazia; sucesso → `Registrado:`; `error =` deriva `Já escolhido no pick N` vs `Pick não registrado:`.
  [`app.R:193`](../../../../app.R#L193)
- `undo_btn`: captura `overall` e `had_pick` antes de `undo_pick()`; `error =` distingue falha real de "sem picks" (patch da revisão).
  [`app.R:220`](../../../../app.R#L220)

**Microcopy estática**

- Rótulos acentuados e `draft_btn` → `"Registrar"`.
  [`app.R:61`](../../../../app.R#L61)

**Estilo (tokens de DESIGN.md)**

- Bloco `.draft-feedback`: borda-esquerda `--action` (confirmação) / `--danger` (erro), `:empty` colapsa, sem auto-clear.
  [`styles.css:747`](../../../../www/styles.css#L747)

**Testes (offline)**

- Bloco `story 13`: um caso por linha da matriz + transição error→ok, persistência sob `session$elapse`, id inválido, falha de `save_state` (com skip sob root).
  [`smoke.R:2745`](../../../../tests/smoke.R#L2745)
