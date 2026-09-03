# Adaptação da interface Shiny ao design proposto — avaliação e backlog

- **Status:** rascunho de referência (não é spec)
- **Criado:** 2026-09-02
- **Fontes lidas:** `docs/design/DESIGN.md`, `docs/design/EXPERIENCE.md`,
  `docs/design/mockups/live-war-room.html`, `app.R` (implementação atual),
  `docs/fantasy-warroom-bmad-intent.md` (intent autoritativo), `AGENTS.md`,
  `_bmad-output/specs/spec-fantasy-warroom/RETROSPECTIVE.md`.
- **Objetivo:** listar user stories candidatas a `/bmad-spec`, da mais simples
  (só look'n'feel) à mais complexa (mudança de backend / contrato RDS), para que
  a adaptação da War Room Shiny ao design seja especificada em incrementos
  independentes e revisáveis.
- **Escopo deste documento:** proposta apenas. Nada foi implementado.

---

## 1. Estado atual da interface (`app.R`)

`app.R` é um adapter fino sobre o core (story 8, `1c8c3db`), e funcionalmente
faz o que o épico pediu:

- `fluidPage` + `titlePanel("Draft War Room")` + `renderTable`, tema Bootstrap
  default (claro).
- Layout em stack vertical de `fluidRow` / `column`.
- Busca de jogador = `selectizeInput` (dropdown único, `server = TRUE`).
- Recomendações = `tableOutput` de até 11 colunas
  (`player, pos, points, vor, tier, adp, p_next, wait_cost, decision_score,
  label, reason`).
- Roster do operador = tabela plana `slot / jogador / pos / pontos / vor`.
- "Board" = `recent_picks_table`, tabela plana dos últimos 15 picks.
- Disponíveis = `tableOutput` de até 50 linhas com filtro de posição via
  `selectInput`.
- Pick / undo via `record_pick()` / `undo_pick()` + `save_state()` atômico,
  na ordem correta (salva antes de atualizar o `reactiveVal`).
- Já implementado e reaproveitável:
  - nota de _off-turn_ (`recs_note`: "Você não está na vez — estes números
    assumem que você pica agora"), via `attr(recs(), "off_turn")`;
  - binding snapshot ↔ state na subida (`.warroom_assert_snapshot_binding()`);
  - mesma injeção de dependência do terminal (`server(..., snapshot, state_path,
    config)`) para `shiny::testServer()`.

O que **não** existe hoje: tema escuro / tokens, faixa de estado estruturada,
smart-list densa, painel de inspeção, board em grade, undo estilizado e
persistente, navegação por teclado, `aria-live` / roles de combobox, e todo o
IA anterior ao _live_ (Sessões, Preparar draft, ordem snake, Pausa/Export,
Conclusão, correção de pick, auditoria persistente).

---

## 2. O que o design pede a mais

`DESIGN.md` + `EXPERIENCE.md` + o mockup descrevem:

- **Shell de terminal escuro**: tokens de cor (`canvas #0B0F14`, `surface`,
  `surface-raised`, `ink`, `ink-muted`, `action #57D68D` só para pick vivo /
  confirmação / ação, `focus #67B7FF`, `warning`, `danger`), pilha
  monoespaçada do sistema, cantos quase retos (`rounded.sm = 2px`), espaçamento
  denso (`spacing.2` em linhas, `spacing.4` só em superfícies principais).
- **Faixa de estado fixa** no topo: overall pick em `typography.display`, time
  no relógio, próximo pick do operador, último jogador registrado, estado da
  sessão — sempre visível, atualiza como uma unidade.
- **Campo de busca + autocomplete**: campo de largura dominante, resultados
  imediatamente abaixo (nome / posição / time NFL), resultado que `Enter`
  registra com `candidate-active` + contorno de foco.
- **Lista inteligente**: tabela curta ordenada (posição, nome, tier, score,
  motivo resumido), nº 1 destacado por ordem e peso tipográfico (não por card),
  filtros de posição como badges discretos, ≥ 5 candidatos.
- **Painel de inspeção**: `Espaço` sobre candidato → projeção, valor, preço de
  mercado, tier + restantes, urgência, impacto marginal no roster; declara
  ausência de dados opcionais.
- **Board de draft**: grade round × time, pick atual marcado, picks do operador
  rotulados (não só cor), realce transitório no pick recém-registrado.
- **Roster do operador**: matriz de slots com grupos visuais estáveis
  (titulares / FLEX / banco), slots vazios visíveis.
- **Undo**: controle sempre visível, atalho `U`, borda/texto `warning`, mostra o
  próximo pick a desfazer (overall, jogador, time) e a contagem de reversões
  disponíveis (undo multinível).
- **Interação keyboard-first**: `/` foca a busca, ↑↓ movem o destaque, `Enter`
  registra, `Espaço` inspeciona, `Esc` fecha a camada superior, `U` desfaz;
  regras distintas dentro e fora de input editável.
- **Piso de acessibilidade** (reduzido pelo Sprint Change de 2026-08-31): uma
  região `aria-live=polite`, roles/labels do combobox, focus-ring visível,
  ordem de Tab acompanhando a leitura.
- **IA multi-superfície antes do _live_**:
  - **Sessões** — listar sessões locais por recência, pré-selecionar a mais
    nova, restaurar só após confirmação;
  - **Preparar draft** — qualidade do snapshot (metadados, cobertura, avisos,
    bloqueios), configuração da liga, ordem snake + `Validate and Lock`;
  - **Pausa / exportação** — pausar/retomar e exportar picks, rosters,
    configuração e metadados;
  - **Conclusão** — fechar a sessão no último pick, manter exportação;
  - **Correção de pick antigo** (Flow 4b) — redirecionar um pick arbitrário do
    passado, revalidar a sequência, preservar picks posteriores;
  - **Auditoria persistente** — registros, undos e correções em ordem, "não
    apaga auditoria".

---

## 3. Divergências de linhagem — resolver antes de especificar

1. **`docs/design/` vem de outro tronco BMAD.** Os campos `sources` de
   `DESIGN.md` e `EXPERIENCE.md` apontam para
   `prds/prd-Fantasy Draft War Room-2026-08-28/`,
   `architecture/architecture-Fantasy Draft War Room-2026-08-28/` e
   `docs/fantasy-draft-war-room-spec.md` — **nenhum existe no repositório**. O
   intent autoritativo é `docs/fantasy-warroom-bmad-intent.md` e a spec
   destilada é `_bmad-output/specs/spec-fantasy-warroom/`.
2. **O design é mais conservador no algoritmo do que o que foi entregue.**
   `EXPERIENCE.md` declara "Não há PNext/VONA, simulação [...] no V1" — mas
   `p_next`, `wait_cost` e o simulador já foram construídos (stories 6 e 7). O
   design fica atrás da implementação nesse ponto e à frente dela no shell de
   UX.
3. **A implementação entregue é deliberadamente "uma página operacional".** O
   intent diz "Implement Shiny only after the terminal draft and simulator
   work" e "One operational page is enough". O IA multi-superfície do design é
   expansão de escopo pós-épico, não reconciliação de algo que ficou
   pela metade.

**Ação:** uma story 0 de reconciliação (`/bmad-spec` update) que decide o que
de `docs/design/` entra num épico "War Room UX", corrige os `sources` e marca
explicitamente os itens condicionais a decisão de policy (§4).

---

## 4. Paredes de policy (`AGENTS.md`) que o design encosta

- **"Nunca introduzir event sourcing"** + **"`state/draft.rds` guarda só os
  picks ordenados (`overall`, `player_id`, `entered_at`)"**. Auditoria
  persistente de undos/correções e a correção de pick arbitrário exigem um log
  ordenado de eventos no RDS — tensiona diretamente as duas regras. Precisa de
  decisão explícita do dono do intent antes de qualquer spec.
- **"`yaml` é lido em exatamente dois lugares"** (`scripts/prepare.R` e o
  resolver de liga em `R/core.R`). Editar a configuração da liga pela UI
  encosta nessa restrição — ou a edição é gravada de volta no
  `config/league.yml`, ou a liga passa a viver só no `state` (já carrega
  `state$league`).
- **"Terminal e simulador funcionam antes de qualquer trabalho em Shiny"** e
  **"Não implementar partes de stories futuras enquanto trabalha na atual"**.
  As stories abaixo são explicitamente pós-épico; devem ser um épico novo com
  sua própria ordem, não enxertos no `spec-fantasy-warroom`.
- **"Nunca fazer chamada de rede no caminho do draft ao vivo"**. Nada nas
  stories abaixo introduz rede — a qualidade do snapshot (D1) lê só metadados
  já gravados em `data/projections.rds`.

---

## 5. O que já dá para reusar sem tocar o backend

| Necessidade do design | Já existe no core |
|---|---|
| Impacto marginal no roster ("+2.1" no mockup) | `recommend_players()` devolve a coluna `marginal_value` |
| Projeção / valor / preço de mercado / tier / urgência na inspeção | colunas `points`, `vor`, `adp`, `tier`, `p_next` do mesmo retorno |
| Busca tolerante a variação de nome | `resolve_player()` em `R/core.R` (exato → prefixo → substring → `adist()`) |
| Slot de cada jogador no roster (titular / FLEX / banco) | `roster_slots(roster, league)` em `R/recommendation.R` |
| Board round × time | `make_snake_schedule()` + `state$picks` + `snapshot$players` |
| Disponíveis ordenados e filtrados por posição | `available_board(view, pos, n)` em `R/core.R` |
| Nota de off-turn | `attr(recs(), "off_turn")`, já renderizada |

---

## 6. Backlog proposto

Cada linha é uma candidata a uma story `/bmad-spec`. Agrupadas por tier de
risco crescente.

### Story 0 — Reconciliação de escopo (pré-requisito)

`/bmad-spec` update. Decide quais elementos de `docs/design/` entram no épico
"War Room UX", corrige os `sources` dos dois docs de design para apontarem o
intent real, e marca os itens condicionais a decisão de policy (Tier D5/D6).
Sem código.

### Tier A — só look'n'feel (CSS / tema; zero backend, zero contrato RDS)

| # | Story | Escopo |
|---|---|---|
| A1 | Shell de terminal escuro | `www/styles.css` com os design tokens (cores, mono, `rounded.sm`, escala de `spacing`). Substituir o chrome do `fluidPage`. Nenhum output muda de conteúdo. |
| A2 | Faixa de estado fixa | Header sticky estruturado: `PICK N` em destaque, time no relógio, "seu próximo pick", último pick registrado (derivar de `picks` + snapshot), indicador "sessão local · salva". Substitui o `textOutput("banner")`. |
| A3 | Smart-list de candidatos | Reformatar o `recs_table`: lista curta ranqueada (#, nome + pos, tier, score, motivo de uma linha), nº 1 com peso tipográfico, filtro de posição como badges. Mesmo `recommend_players()`, render novo. |
| A4 | Painel de roster agrupado | Reformatar o `roster_table`: grupos Titulares / FLEX / Banco, slots vazios visíveis. `roster_slots()` já dá a atribuição. |
| A5 | Microcopy + feedback | Aplicar a tabela Voice/Tone do `EXPERIENCE.md` (`Registrado: X`, `Já escolhido no pick 42. Busque outro jogador.`). Erros persistem até o operador poder agir; feedback junto à faixa de estado. |

#### Repriorização de 2026-09-03 (sessão de teste com dados reais)

Depois de rodar um draft de teste na app, quatro lacunas de uso ficaram
evidentes e foram promovidas para **antes** do restante do Tier B/C. No
`stories.yaml` elas são as stories **14, 15, 16**; o backlog abaixo (antes 14→25)
desceu +3.

| # | Story | Escopo |
|---|---|---|
| A6 (story 14) | Legibilidade da lista + clicar para draftar | (1) Subir o contraste do conteúdo hoje em `--ink-muted` — `motivo`, `tier`, `score` e os **nomes de jogador** são conteúdo, não decoração. (2) Clicar em qualquer ponto da linha de candidato registra o jogador (mesmo caminho `record_pick()` do `Enter` na linha 1). Revisa o par de tokens de contraste aceito "como está" no Sprint Change de 2026-08-31 → `spec_checkpoint`. |
| A7 (story 15) | Painel de rosters de todos os times | O que o terminal já faz com `/teams` e a app não tem: roster por time (grupos Titulares / FLEX / Banco) via `derive_draft_view()$rosters` + `roster_slots()`, com o time do operador marcado. Read-only, sem tocar core nem contrato. `spec_checkpoint` só para fixar layout / colapso na janela estreita. |
| C2 → story 16 | Busca como combobox | **Puxada para frente** do Tier C: autocomplete próprio reusando `resolve_player()`. Entrega mouse + type-to-filter + `Enter` agora; navegação por teclado e roles `aria-combobox` ficam com C1 (story 22) e C3 (story 23). |

### Tier B — layout + render mais rico (deriva de views existentes; no máximo um helper puro read-only)

| # | Story | Escopo | Toca core? |
|---|---|---|---|
| B1 | Layout em grade de painéis | Regiões `workspace` (candidatos + inspeção) e `wide` (board + roster) + auditoria; dois estados amplo / estreito com colapso simples (sem painéis com preservação de foco — escopo já reduzido no Sprint Change). | Não |
| B2 | Board em grade | Matriz round × time, pick atual destacado, picks do operador rotulados ("YOU"), realce transitório no pick novo. Puro sobre `make_snake_schedule()` + `picks` + snapshot. | Não |
| B3 | Painel de inspeção | `Espaço` / clique num candidato → projeção, valor, preço de mercado (`adp`), tier + restantes, urgência (de `p_next`), impacto marginal (`marginal_value`). Todos os campos já saem de `recommend_players()`. Declara "Não disponível neste snapshot" quando `adp` / `p_next` faltam (caso do snapshot real atual, sem ADP). | Não |
| B4 | Undo redesenhado | Controle persistente, borda `warning`, mostra o próximo pick a desfazer (overall / jogador / time) + a contagem de picks efetivos (`nrow(picks)`). Continua usando `undo_pick()`. | Não |
| B5 | Painel de auditoria (read-only) | Lista de picks recentes + linhas "Registrado". Nota: eventos de undo / correção não são persistidos hoje — este painel fica picks-only até o Tier D5. | Não |

### Tier C — keyboard-first + acessibilidade (front-end pesado: JS / input customizado; zero core)

| # | Story | Escopo |
|---|---|---|
| C1 | Modelo de interação por teclado | `/` foca a busca, ↑↓ movem o destaque de candidato, `Enter` registra, `Espaço` inspeciona, `Esc` fecha a camada, `U` desfaz. Regras dentro vs fora de input editável (`EXPERIENCE.md` Interaction Primitives). Handler JS + `Shiny.setInputValue`. |
| C2 | Busca como combobox | Substituir o `selectizeInput` por um autocomplete próprio: linhas nome / pos / time NFL, resultado destacado = ação do `Enter`, match incremental tolerante. Reusar `resolve_player()` do core. |
| C3 | Piso de acessibilidade | Uma região `aria-live=polite` + `aria-atomic`, roles / labels do combobox, focus-ring visível, ordem de Tab (estado → busca → candidatos → inspeção → board → roster). Alvo é o conjunto **reduzido** do Sprint Change de 2026-08-31 (sem `aria-activedescendant`, roving tabindex, zoom 200% linear, `prefers-reduced-motion`). |

### Tier D — backend / contrato RDS / novas funções de core (exige `/bmad-spec`; D5 e D6 exigem decisão de policy)

| # | Story | Escopo | Impacto |
|---|---|---|---|
| D1 | Qualidade do snapshot + gate de início | Superfície que resume season / method / fontes / scoring / cobertura / avisos e **bloqueia iniciar** em incompatibilidade; sinaliza campos opcionais ausentes (`adp` / `adp_sd` — relevante agora). Core: uma função pura `snapshot_quality()`. | Novo helper de core, sem mudar contrato. Médio. |
| D2 | Setup de draft na app | Configuração de liga (times / rounds via roster / slots / FLEX / scoring / time do operador) + entrada da ordem snake + `Validate and Lock`. A app hoje não tem a entrada de ordem que o terminal tem. | Shiny ganha o fluxo de ordem; editar a liga encosta na regra "yaml em dois lugares" (§4). Grande. |
| D3 | Gestão de múltiplas sessões | Superfície "Sessões": listar sessões locais por recência, pré-selecionar a mais nova, confirmar antes de restaurar, estado vazio "nenhuma sessão". | `R/persistence.R` + `rds-contracts.md` passam de um `state/draft.rds` fixo para múltiplos arquivos nomeados / datados. Grande. |
| D4 | Pausa / retomar + Export | Pausa = novo campo `status` no state (bump de `schema_version` + migração — a wave 1 já valida o schema de forma dura). Export = serializador puro de picks / rosters / configuração / metadados. | Contrato RDS ganha um campo. Export é puro. Médio. |
| D5 | Trilha de auditoria persistente | Persistir eventos de undo / correção ("não apaga auditoria"). | **Conflito de policy:** um log ordenado de eventos no state tensiona "persistir só picks ordenados" e a linha "nunca event sourcing". Decisão do dono do intent. Grande e contencioso. |
| D6 | Correção de pick antigo (Flow 4b) | Redirecionar um pick arbitrário do passado para um jogador disponível, revalidar a sequência recomposta, preservar picks posteriores, registrar a correção. Nova função de core `correct_pick()`. | Depende de D5. Renegocia o invariante "undo remove só o pick mais recente". Maior e mais contencioso. |

---

## 7. Ordem sugerida de especificação

```
0 → A1 → A2 → A3 / A4 / A5 → A6 / A7 / C2 → B1 → B2 → B3 → B4 → B5 → C1 → C3
  → D1 → D4 → D2 → D3 → (D5 → D6, só se a policy permitir)
```

A6 / A7 / C2 = stories 14 / 15 / 16 no `stories.yaml` (repriorização de
2026-09-03). C2 saiu do bloco Tier C e foi para 16; C1 (story 22) depois passa a
navegação por teclado por cima do combobox já entregue.

- Tier A entrega a maior parte da percepção visual do mockup sem risco de
  regressão funcional.
- Tier B fecha o restante do layout e a inspeção, ainda sem tocar contrato.
- Tier C é a camada de interação; independente de D.
- D5 e D6 podem nunca ser aprovados — o design os pede, a policy atual os
  barra.

## 8. Nota de performance

A retrospectiva (AV-4) mediu `recommend_players()` em ~286 ms por chamada
mid-draft, antes de qualquer overhead de reactive / render. Qualquer story de
Tier B ou C que re-renderize ao mudar o foco de candidato **não** pode
rechamar `recommend_players()` a cada tecla: cachear o frame de recomendações
num `reactive` e fazer reordenação / filtro / seleção no cliente.
