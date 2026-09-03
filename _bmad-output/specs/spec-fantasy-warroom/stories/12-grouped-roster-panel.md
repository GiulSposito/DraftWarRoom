---
title: 'Painel de roster agrupado (A4)'
type: 'feature'
created: '2026-09-03'
status: 'done'
review_loop_iteration: 1
baseline_commit: '7d19a431543b02cd6ac2f5d05523a30791c3db50'
context:
  - '/Users/gsposito/Projects/football/DraftWarRoom/_bmad-output/specs/spec-fantasy-warroom/SPEC.md'
  - '/Users/gsposito/Projects/football/DraftWarRoom/_bmad-output/specs/spec-fantasy-warroom/functional-core.md'
  - '/Users/gsposito/Projects/football/DraftWarRoom/AGENTS.md'
  - '/Users/gsposito/Projects/football/DraftWarRoom/docs/design/DESIGN.md'
  - '/Users/gsposito/Projects/football/DraftWarRoom/docs/design/EXPERIENCE.md'
---

<frozen-after-approval reason="human-owned intent — do not modify unless human renegotiates">

## Intent

**Problem:** `app.R` mostra o roster do operador como um `renderTable` plano de 5
colunas (`slot`, `jogador`, `pos`, `pontos`, `vor`) que só lista os jogadores já
draftados — sem grupos visuais estáveis, sem vagas vazias e sem a forma enxuta de
uma linha por slot que `DESIGN.md` (§Components "Roster do operador") e
`EXPERIENCE.md` pedem. Em particular, nenhuma vaga aberta de titular aparece — o
operador não tem lembrete visual de que ainda falta QB, K, DST etc.

**Approach:** Trocar `tableOutput("roster_table")` por `uiOutput("roster_table")`
e o `renderTable` por um `renderUI` que compõe **três grupos visuais fixos** —
**Titulares** (QB, RB, WR, TE, **K**, **DST**), **FLEX**, **Banco** — com uma
linha por vaga de `state$league$roster`. Vagas não preenchidas aparecem
explícitas ("— aberto" nos titulares/FLEX, "—" no banco). CSS novo em
`www/styles.css`, tokens verbatim de `DESIGN.md`.

## Boundaries & Constraints

**Always:**
- **Gabarito de vagas** vem de `state$league$roster` (vetor nomeado inteiro
  `QB RB WR TE FLEX K DST BENCH` — o core garante todos os 8 slots como inteiros
  ≥ 0). O grupo **Titulares** tem `QB + RB + WR + TE + K + DST` linhas (uma por
  vaga), o grupo **FLEX** tem `FLEX` linhas, o grupo **Banco** tem no mínimo
  `BENCH` linhas. O total de linhas renderizadas é sempre `sum(state$league$roster)`
  mais qualquer excedente de banco.
- **Atribuição jogador→vaga:**
  - Para os slots `QB RB WR TE FLEX`, usar exclusivamente `roster_slots(roster,
    state$league)` (`R/recommendation.R`) — nunca re-slotar em `app.R`.
  - Para os slots `K` e `DST`, colocar por **identidade de posição**: os
    jogadores com `pos == "K"` preenchem as vagas `K` (as `roster_slots()` os
    devolve como `BENCH`); idem `DST`. É uma alocação 1-para-1 sem escolha, não
    seleção de titular — há exatamente uma vaga `K` e só kickers vão nela.
  - O grupo **Banco** recebe os jogadores que `roster_slots()` marca `BENCH`
    **menos** os que foram colocados nas vagas `K`/`DST` acima.
- **Excedente:** se houver mais jogadores de uma posição do que vagas
  (`roster_slots()` já limita QB/RB/WR/TE/FLEX; um 2º K ou 2º DST, ou um QB2
  etc.), o excedente vai para o **Banco**. O Banco nunca trunca — o mínimo de
  `BENCH` linhas é piso, não teto.
- **Ordenação:** jogadores de um slot multi-vaga (RB, WR; e Banco) são ordenados
  por `vor` (fallback `points` quando o snapshot não traz `vor`) **decrescente**
  e alocados às vagas nessa ordem; vagas livres ficam sempre por último dentro do
  grupo. Empate desfeito por `player_id`.
- Renderização pura sobre `view()$rosters[[state$user_team]]` e as duas funções
  acima. Nenhuma fórmula, ordenação de recomendação, `p_next`, `wait_cost`,
  lineup ou seleção de titular recalculada na view. A prioridade/peso de K/DST na
  **recomendação** não muda (segue `recommendation-algorithm.md`; K/DST continuam
  empurrados para o fim do draft) — este painel é só exibição.
- Cada linha preenchida: nome do jogador em uma linha; meta com `pos` (e
  ` · <nfl_team>` só quando presente) em `typography.label` / `--ink-muted`.
  `nfl_team` é campo opcional do snapshot — dropa em vez de imprimir `NA`. Nenhum
  número (`pontos`, `vor`) é exibido no painel.
- Rótulos de slot: posição isolada quando a contagem da liga é 1 (`QB`, `TE`,
  `K`, `DST`), numerada quando > 1 (`RB1`, `RB2`, `WR1`, `WR2`); FLEX → `FLEX`;
  banco → `BN`.
- Rótulo de slot em `--ink-muted` / `typography.label`, **não** `--action` —
  desvio consciente do mockup: `DESIGN.md` §Colors reserva o verde para pick
  vivo / confirmação / ação.
- `outputId` continua `roster_table` (agora `uiOutput`). `pos_filter`,
  `recs_pos_filter` e todos os ids das stories 8–11 permanecem.
- `app.R` continua adapter fino: sem pacote novo no `renv.lock`, sem JavaScript
  próprio, sem `bslib`/`sass`/`includeCSS`/`shinyjs`. CSS só em `www/styles.css`,
  sem asset remoto. `recommend_players()` continua chamado exatamente 1× no code.

**Ask First:**
- Exibir melhor lineup, ocupação numérica de slots ("2/9") ou impacto marginal
  do candidato focado no painel — é parte das stories 16/22.
- Reestruturar as seções em regiões workspace/wide ou tornar painéis colapsáveis
  — story 14. Adicionar pacote ao `renv.lock`.

**Never:**
- Board em grade, painel de inspeção, undo redesenhado, teclado, `aria-live`
  reativo (stories 13–21).
- Rede, `ffanalytics`, leitura de `yaml` nova, mudança em `state/draft.rds` /
  `data/projections.rds`, Shiny modules, nova função de core.
- Reimplementar seleção de titular ou `lineup_value()` em `app.R`; recomputar
  `vor` / lineup na view. (A colocação por `pos` de K/DST não é seleção de
  titular — é identidade de posição para uma vaga única.)

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| Roster parcial | user roster: QB, 2 RB, 1 WR, 1 K | Titulares: `QB` preenchido; `RB1`/`RB2` preenchidos com os 2 RB de maior `vor`; `WR1` preenchido, `WR2` = "— aberto"; `TE` = "— aberto"; `K` preenchido; `DST` = "— aberto". FLEX = "— aberto". Banco: 6 linhas "—" (o K não conta como banco) | N/A |
| Roster vazio | usuário sem picks | Titulares 8 linhas + FLEX 1 linha, todas "— aberto"; Banco 6 linhas "—"; os três grupos presentes; total de linhas = `sum(roster)` = 15 | N/A |
| 3º RB draftado | user roster com 3 RB | `roster_slots()` põe o 3º RB em `FLEX` → ele aparece na linha FLEX; `RB1`/`RB2` são os 2 de maior `vor` mesmo que draftados fora dessa ordem | N/A |
| K e DST draftados | user roster com QB, K, DST | `K` e `DST` preenchidos no grupo Titulares (colocação por `pos`); nenhum deles no Banco; Banco = 6 linhas "—" | N/A |
| 2º K draftado | user roster com 2 K | a 1ª vaga `K` recebe o K de maior `vor`; o 2º K vai para o Banco | N/A |
| Over-draft de banco | user roster que enche todo titular + FLEX + 7 jogadores slot-`BENCH` que não são K/DST | Banco mostra 7 linhas, nenhuma truncada nem preenchida com vazio | N/A |
| `nfl_team` presente | snapshot real (sempre traz `nfl_team`) | meta da linha preenchida = `<pos> · <nfl_team>` (ex.: `QB · ARI`) | N/A |
| `nfl_team` ausente | snapshot sem a coluna `nfl_team` | meta da linha mostra só `pos` (sem ` · `, sem `NA`) | N/A |
| Draft completo | user roster com 15 jogadores | toda vaga preenchida, zero "— aberto"/"—"; sem erro | página funcional |
| `styles.css` ausente | `www/styles.css` removido | painel monta sem estilo, sem erro de servidor | página funcional |

</frozen-after-approval>

## Code Map

- `app.R:75-78` — `fluidRow(column(6, h4("Seu roster"),
  tableOutput("roster_table")), column(6, h4("Picks recentes"), ...))`.
  **Trocar** só `tableOutput("roster_table")` por `uiOutput("roster_table")`; a
  coluna "Picks recentes" fica intacta.
- `app.R:331-352` — `output$roster_table <- renderTable({...})`. **Substituir**
  por `output$roster_table <- renderUI({...})`. O código atual já obtém
  `roster <- view()$rosters[[st$user_team]]` e chama `roster_slots(roster,
  st$league)` — reusar essa fonte para QB/RB/WR/TE/FLEX/BENCH.
- `app.R:341` — `val <- if ("vor" %in% names(roster)) roster$vor else
  roster$points` já existe no `renderTable` atual (mesma escolha de `vor` com
  fallback `points`). **Manter** — é a moeda de ordenação; a alternativa (expor
  um helper de core) está registrada em `deferred-work.md`, fora do escopo.
- `app.R:21` — `%||%` disponível para os campos opcionais.
- `R/recommendation.R:160-202` — `roster_slots(roster, league)` → `data.frame(
  player_id, slot)`, `slot` ∈ `QB RB WR TE FLEX BENCH`; roxygen `:160-177`
  documenta que K/DST vão para `BENCH` (espelha `lineup_value()`). **Não
  alterar.** 0 linhas para roster `NULL`/0 linhas.
- `R/recommendation.R:136-140` — `.warroom_value_of()` é a moeda de valor do core
  (`vor`, fallback `points`); referência para o comentário do `val` no painel.
- `R/core.R:392-418` — `derive_draft_view()`. `$rosters[[team]]` são linhas do
  snapshot (`player_id`, `player`, `pos`, `points`, `vor`, `tier`, `nfl_team`
  quando houver) dos jogadores draftados pelo time, em ordem de pick. Time sem
  picks → data.frame de 0 linhas (não `NULL`). `player_id` é sempre `character`
  (contrato `rds-contracts.md`).
- `R/core.R:111` — `.warroom_roster_slots <- c("QB","RB","WR","TE","FLEX","K",
  "DST","BENCH")`; `load_league()` (`:83-`) rejeita slot ausente, não-inteiro ou
  negativo, então `state$league$roster` é sempre completo e inteiro. Liga
  inicial: `QB1 RB2 WR2 TE1 FLEX1 K1 DST1 BENCH6`.
- `config.R:25-26` — `user_team <- "Team 01"`; sempre presente no caminho vivo.
- `docs/design/mockups/live-war-room.html:163-169` + `www/styles.css` do mockup
  (linhas ~83-88) — referência de classes: `.roster`, `.roster-group`,
  `.roster-row`, `.slot`, `.empty`, `small`. O mockup só desenha Titulares/Banco
  com FLEX como linha; aqui são 3 grupos e K/DST são vagas — os spines vencem.
- `docs/design/DESIGN.md` frontmatter — `components.operator-roster`,
  `typography.label`, `colors.ink-muted`; §Components "Roster do operador";
  §Colors (action só para pick vivo/ação).
- `docs/design/EXPERIENCE.md:71` — "Roster do operador — Agrupa titulares, FLEX e
  banco; torna visíveis … slots vazios"; §55 microcopy usa "aberto" para vaga
  livre.
- `www/styles.css:1-34` — header comment (hoje termina na story 11) →
  **atualizar** com o parágrafo da story 12. `:304-416` bloco `.smart-list` —
  **inserir** o bloco `.roster-panel` depois dele. `:442-482` regras genéricas de
  `table`/`.shiny-table` permanecem (os `renderTable` de recent_picks e available
  continuam).
- `tests/smoke.R:1765-1780` — bloco `(8e)` faz um cross-check de
  `output$roster_table` casando markup `<td>` de tabela (`renderTable`).
  **Atualizar** para o novo markup agrupado.
- `tests/smoke.R:1954-1958`, `:2378-2382` — loops de ids incluem `roster_table`
  por `grepl` de substring; seguem válidos com `uiOutput`.
- `tests/smoke.R:2170` — `.s11_count(h, needle)` (conta ocorrências) já em
  escopo, reusável para contar linhas/grupos.
- `tests/smoke.R:2418` — fim do bloco story 11; `:2420` começa o guard do
  `prepare.R`. **Inserir** o bloco `## --- story 12` entre os dois.
- `R/projections.R` (`build_synthetic_projections`) — o fixture sintético:
  `points`/`vor` decrescem com o sufixo numérico do `player_id` (`SYN-RB-001` >
  `SYN-RB-002` …) e **sempre traz `nfl_team`**. Um teste de ordenação
  discriminante precisa passar ids fora da ordem de `vor`.

## Tasks & Acceptance

**Execution:**
- [x] `app.R` — UI: `uiOutput("roster_table")` no lugar do `tableOutput`.
  Server: `output$roster_table <- renderUI({...})` sobre
  `view()$rosters[[st$user_team]]`. Computar um vetor de vaga por jogador:
  `roster_slots()` para QB/RB/WR/TE/FLEX/BENCH; depois reatribuir a `"K"` os
  `slot_count("K")` jogadores `pos == "K"` de maior `vor` e a `"DST"` os
  `slot_count("DST")` de `pos == "DST"` (os demais K/DST permanecem `BENCH`).
  Compor `.roster-panel` (`role="group"`, `aria-label` estático) com 3
  `.roster-group`: **Titulares** = linhas para `QB RB WR TE K DST` (contagens de
  `st$league$roster`, rótulos isolados/numerados), **FLEX** = `FLEX` linhas,
  **Banco** = `max(BENCH, nº de jogadores ainda `BENCH`)` linhas. Multi-vaga e
  Banco ordenados por `vor` (fallback `points`) desc, empate por `player_id`;
  vagas livres por último → "— aberto" (titulares/FLEX) / "—" (banco). Linha
  preenchida: `<span class="slot">` + `<span class="name">` + `<span
  class="meta">` (`pos`, + ` · <nfl_team>` quando presente; dropar `NA`). Sem
  `pontos`/`vor` exibidos. Nada mais no `server` muda.
- [x] `www/styles.css` — atualizar o header comment; adicionar `.roster-panel`,
  `.roster-group`, `.roster-group-label` (label type), `.roster-row`,
  `.roster-row--empty`, `.roster-row .slot` (`--ink-muted`, **não** `--action`),
  `.roster-row .name` (trunca), `.roster-row .meta`, `.roster-row .empty`. Só
  tokens de `DESIGN.md`, sem `@import` / `url(http`.
- [x] `tests/smoke.R` — atualizar o cross-check de `output$roster_table` em
  `(8e)` para o markup agrupado; novo bloco `## --- story 12` via
  `.s8_bake_server` + `shiny::testServer` + `.strip_html`, com **um teste por
  linha da matriz**, incluindo:
  - roster parcial: `K` preenchido **e** `DST` = "— aberto"; Banco 6 linhas "—".
  - roster vazio: assevera o placeholder "— aberto" nas 8 linhas de Titulares e
    na linha de FLEX (não só a contagem), "—" no Banco, e total de
    `<div class="roster-row">` == `sum(league$roster)` == 15.
  - 3º RB → FLEX, passando os RB **fora da ordem de `vor`** e exigindo `RB1` = o
    de maior `vor`.
  - K + DST → ambos no grupo Titulares, nenhum no Banco.
  - 2º K → 1ª vaga `K` recebe o de maior `vor`, o 2º K aparece no Banco.
  - over-draft de banco: contagem exata de linhas do Banco = nº de jogadores
    `BENCH` (sem K/DST), zero linhas vazias.
  - `nfl_team` presente (fixture real): linha preenchida mostra
    `<span class="meta">QB · <team></span>`.
  - `nfl_team` ausente: `<span class="meta">QB</span>`, e nenhum `"NA"` no HTML.
  - draft completo: zero `roster-row--empty`, zero "aberto".
  - `styles.css` ausente: painel monta, sem erro (padrão swap-and-restore da
    story 11).
  - bench: assevera que o rótulo `<span class="slot">BN</span>` aparece numa
    linha preenchida (ex.: o K excedente).
  UI estática: `id="roster_table"` presente e **sem** `<table` renderizado nele;
  ids das stories 8–11 intactos; `www/styles.css` contém `.roster-panel` /
  `.roster-group` / `.roster-row` e a regra de `.roster-row .slot` **não** usa
  `var(--action)`, sem asset remoto; `app.R` sem
  `bslib|sass|includeCSS|shinyjs|tags$script|Shiny.setInputValue` novo, sem
  símbolo de rede/RNG, `roster_slots`/`recommend_players` não redefinidos,
  `recommend_players(` ainda chamado 1×.

**Acceptance Criteria:**
- Given `make test` sem rede, when executado, then status 0 com os blocos das
  stories 1–12; as linhas "story 8/9/10/11 offline checks OK" continuam e a
  equivalência `recs()` ↔ `recommend_players()` de `(8c)`/`(8e)` passa sem
  edição.
- Given `Rscript -e 'source("app.R");
  cat(as.character(htmltools::renderTags(ui)$html))'`, when revisado, then há
  `id="roster_table"` (um `uiOutput`, sem `<table` estático) e seguem presentes
  `status_strip`, `recs_table`, `recs_pos_filter`, `recs_note`,
  `recent_picks_table`, `available_table`, `player_choice`, `draft_btn`,
  `undo_btn`, `pos_filter`.
- Given uma liga inicial e um roster vazio, when o painel renderiza, then o
  número de `<div class="roster-row">` é `sum(state$league$roster)` (15: 8
  Titulares + 1 FLEX + 6 Banco).
- Given `git diff app.R`, when revisado, then as mudanças são só o
  `tableOutput`→`uiOutput` e o `renderTable`→`renderUI` de `roster_table`; nada
  em `recs`/`view`/`commit_state`/`record_pick`/`undo_pick`/`save_state` ou nos
  demais `render*`.
- Given `grep -nE "bslib|sass|includeCSS|shinyjs|tags\$script|Shiny\.setInputValue" app.R`,
  when comparado ao estado anterior, then nenhuma ocorrência nova.

## Spec Change Log

- **2026-09-03 — loopback 1 (intent_gap).** Revisão em 3 camadas apontou que a
  regra frozen "atribuição jogador→slot é exclusivamente `roster_slots()`" (que
  manda K/DST para o Banco) contradizia a própria intent frozen ("uma linha por
  vaga de slot", "vagas vazias explícitas"): o painel renderizava 13 vagas em vez
  de `sum(roster)` = 15, sem cue de K/DST aberto, e K+DST+4 banco faziam o Banco
  parecer cheio (piso de 6 linhas). Decisão humana: **K e DST são vagas
  dedicadas no grupo Titulares**, preenchidas por identidade de `pos` (colocação
  1-para-1, não seleção de titular); `roster_slots()` continua a fonte única para
  QB/RB/WR/TE/FLEX; o Banco exclui os K/DST colocados e o piso de `BENCH` linhas
  passa a contar só banco de verdade. A prioridade/peso de K/DST na recomendação
  é assunto de `recommendation-algorithm.md` e **não muda**.
  - Amendado: Intent, Boundaries (nova regra de colocação K/DST + total de
    linhas = `sum(roster)`), matriz de I/O (linhas "Roster parcial", "Roster
    vazio", "K e DST", nova "2º K", "Over-draft de banco" recontada, "nfl_team
    presente" separada de "ausente").
  - KEEP (o que funcionou e deve sobreviver à re-derivação): o `renderUI` com
    helpers `filled_row`/`empty_row`/`fill_rows`; o gabarito de vagas a partir de
    `state$league$roster`; a ordenação por `vor` com fallback `points`; o rótulo
    de slot em `--ink-muted` (desvio consciente do mockup, `DESIGN.md` §Colors);
    o header comment do CSS e o bloco `.roster-panel`; a estrutura do bloco de
    teste `## --- story 12` com `.s12_state` fabricando o roster do Team 01 e
    `.s12_render`/`.s12_group`/`.s12_filled`/`.s12_empty`; o cross-check
    reescrito de `(8e)`; as estáticas de UI/CSS/`app.R` do `(12i)`.
  - Lacunas de teste a fechar na re-derivação (achado verification-gap): asserção
    de `<span class="meta">pos · nfl_team</span>` no caso presente; asserção do
    rótulo `BN` numa linha preenchida; caso de ordenação `vor` **discriminante**
    (ids fora da ordem de pick); placeholder "— aberto" nos titulares/FLEX do
    roster vazio; asserção de total de linhas == `sum(roster)`.
  - Registrado em `deferred-work.md`: `val <- if ("vor" ...) roster$vor else
    roster$points` em `app.R` duplica a moeda de `.warroom_value_of()` do core
    (pré-existente, herdado do `renderTable`).

## Design Notes

- **Por que `renderUI` e não `renderTable`.** Grupos visuais estáveis, uma linha
  por vaga (preenchida ou vazia) e nome em `typography.data` com meta em
  `typography.label` não se expressam num `renderTable`. Mesmo padrão das
  stories 10 (faixa de estado) e 11 (lista inteligente): formatação pura, o teste
  assevera sobre uma string de HTML.
- **Colocação de K/DST.** `roster_slots()` os devolve como `BENCH` (espelha
  `lineup_value()`, que nunca conta K/DST no lineup). O painel os "puxa" para as
  vagas `K`/`DST` do grupo Titulares por `pos`, porque essa é a vaga que a liga
  reserva e o operador precisa ver aberta. É colocação por identidade — uma vaga,
  uma posição, sem otimização — e por isso não conta como reimplementar seleção
  de titular. O core não muda; a recomendação continua empurrando K/DST para o
  fim do draft.
- **Total de linhas = `sum(state$league$roster)`.** Invariante barata que casa a
  contagem de vagas com o `rounds` derivado e teria pego a regressão do loopback
  1. Um roster vazio da liga inicial renderiza 15 linhas: 8 Titulares (QB, RB1,
  RB2, WR1, WR2, TE, K, DST), 1 FLEX, 6 Banco.
- **Números fora do painel.** `DESIGN.md` pede "matriz enxuta"; `pontos`/`vor`
  detalhados são do painel de inspeção (story 16). A ordenação interna por `vor`
  (fallback `points`) decide só qual jogador ocupa `RB1` vs `RB2` e a ordem do
  Banco.
- **Desvio do mockup.** O mockup pinta `.slot` em verde (`--action`); aqui o
  rótulo de slot fica em `--ink-muted` / label — `DESIGN.md` §Colors reserva o
  verde para o pick vivo e a ação. Os spines vencem o mockup.
- Exemplo de linha (preenchida): `RB1  Bijan Robinson   RB · ATL`.
  Exemplo de linha (vazia): `DST  — aberto`.

## Verification

**Commands:**
- `make test` — status 0; inclui "story 12" e mantém "story 8/9/10/11 offline
  checks OK".
- `Rscript -e 'source("app.R"); cat(as.character(htmltools::renderTags(ui)$html))'`
  — `id="roster_table"` presente, sem `<table` dentro dele; ids das stories 8–11
  intactos.
- `grep -n "roster-panel\|roster-group\|roster-row" www/styles.css` — presentes.

**Manual checks:**
- `make app`: o roster aparece como três grupos fixos (Titulares com QB/RB/WR/
  TE/K/DST, FLEX, Banco); vagas não preenchidas mostram "— aberto" / "—";
  draftar um K preenche a vaga `K` em Titulares (não o Banco); draftar um RB para
  a 3ª vaga o coloca na linha FLEX; registrar um pick recompõe o painel sem
  piscar as outras tabelas; remover `www/styles.css` e recarregar — sem erro de
  servidor.

## Suggested Review Order

**Ligação da UI**

- Única troca de widget: `tableOutput` → `uiOutput`, resto da `fluidRow` intacto.
  [`app.R:76`](../../../../app.R#L76)

**Composição do painel (renderUI)**

- Ponto de entrada: comentário do design + assinatura do `renderUI`; leia primeiro para pegar a intenção.
  [`app.R:331`](../../../../app.R#L331)
- Colocação de K/DST por identidade de `pos` — puxados do `BENCH` de `roster_slots()` para as vagas dedicadas, maior `vor` primeiro, excedente fica no banco.
  [`app.R:359`](../../../../app.R#L359)
- `filled_row()` / `empty_row()`: meta `pos · nfl_team` com guardas de `NA`, nome guardado, sem número exibido.
  [`app.R:380`](../../../../app.R#L380)
- `fill_rows()`: aloca jogadores às vagas rotuladas por `vor` desc (empate por `player_id`); vagas livres por último.
  [`app.R:399`](../../../../app.R#L399)
- Montagem dos três grupos: Titulares (`QB RB WR TE K DST`), FLEX, Banco (piso `BENCH`, nunca trunca).
  [`app.R:416`](../../../../app.R#L416)

**Estilo (tokens de DESIGN.md)**

- Bloco `.roster-panel`; `.roster-row .slot` em `--ink-muted`, nunca `--action` (desvio consciente do mockup).
  [`styles.css:435`](../../../../www/styles.css#L435)

**Testes (offline)**

- Cross-check do `(8e)` reescrito para o markup agrupado: 3 grupos, linhas == `sum(roster)`, meta `pos · nfl_team`, sem número.
  [`smoke.R:1771`](../../../../tests/smoke.R#L1771)
- Bloco `story 12`: um teste por linha da matriz + lacunas do loopback 1 (ordenação `vor` discriminante, rótulo `BN`, placeholder no roster vazio, total de linhas).
  [`smoke.R:2445`](../../../../tests/smoke.R#L2445)
