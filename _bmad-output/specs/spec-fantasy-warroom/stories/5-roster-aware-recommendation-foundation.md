---
title: 'Fundação de recomendação ciente do roster'
type: 'feature'
created: '2026-09-01'
status: 'done'
review_loop_iteration: 0
baseline_commit: 'c1d94449cb996b99666cdb5a3d8d811444db87ca'
context:
  - '/Users/gsposito/Projects/football/DraftWarRoom/_bmad-output/specs/spec-fantasy-warroom/SPEC.md'
  - '/Users/gsposito/Projects/football/DraftWarRoom/_bmad-output/specs/spec-fantasy-warroom/recommendation-algorithm.md'
  - '/Users/gsposito/Projects/football/DraftWarRoom/_bmad-output/specs/spec-fantasy-warroom/functional-core.md'
  - '/Users/gsposito/Projects/football/DraftWarRoom/_bmad-output/specs/spec-fantasy-warroom/rds-contracts.md'
  - '/Users/gsposito/Projects/football/DraftWarRoom/AGENTS.md'
---

<frozen-after-approval reason="human-owned intent — do not modify unless human renegotiates">

## Intent

**Problem:** As stories 1–4 entregaram o snapshot de projeção e todo o núcleo de
estado e o loop de terminal, mas não existe recomendação: `scripts/draft.R` mostra
apenas um _stand-in_ ("board por valor") no lugar de `/rec` e na vez do usuário.
O usuário precisa, em cada pick pessoal, de uma lista ordenada de jogadores
disponíveis que pese ganho marginal no lineup, VOR e tier, respeite a viabilidade
do roster, e traga um rótulo e uma explicação determinísticos (SPEC "Why", CAP-8).

**Approach:** Criar `R/recommendation.R` com `lineup_value()`, `recommend_players()`
e `default_decision_weights()` — funções puras, offline, sem `shiny` — implementando
os **componentes 1 e 4** de `recommendation-algorithm.md`: valor do melhor lineup,
valor marginal do roster, valor de opção de banco, `tier_cliff`, `adp_value`, os
guardrails de viabilidade (K/DST, QB2, TE2, slot mandatório), e rótulos +
explicações gerados por regras. `p_next`, `wait_cost` e o score final de 4 termos
são da story 6: as colunas existem no resultado mas `p_next` sai `NA` e `wait_cost`
sai `NA`, e o `decision_score` combina só os 3 termos disponíveis. `scripts/draft.R`
passa a renderizar a saída real de `recommend_players()`.

## Boundaries & Constraints

**Always:**
- `R/recommendation.R` contém toda a regra; é puro e offline (sem rede, sem
  `shiny`, sem I/O de arquivo, sem RNG). Carregado automaticamente por
  `load_core()` (que faz `source()` de `R/*.R`).
- Assinatura exata do catálogo (`functional-core.md`): `recommend_players(state,
  projection_snapshot, weights = default_decision_weights(), n = 10L)`. Determinista:
  mesmo `state` + `projection_snapshot` + `weights` → mesma ordem e mesmos scores.
  Desempate sempre por `player_id` ascendente (`method = "radix"`).
- `lineup_value(roster, league)` = soma do **`vor`** (value over replacement) do
  melhor lineup possível: melhor QB, 2 melhores RB, 2 melhores WR, melhor TE,
  melhor RB/WR restante como FLEX. Usa `points` como fallback só se o snapshot não
  trouxer `vor`. VOR é a moeda de "valor" no intent (`docs/fantasy-warroom-bmad-
  intent.md` — "player value", métrica de simulador "starter VOR"): `points`
  bruto faz QBs dominarem o pick 1 porque projeção de QB > projeção de RB em termos
  absolutos, escondendo a escassez posicional. Um titular de VOR negativo ainda
  conta; K e DST **não** entram no `lineup_value` (só nos guardrails / roster
  need). Contagens de slot vêm de `state$league$roster`; FLEX de
  `state$league$flex_positions`. Slot vazio contribui 0.
- Para cada candidato disponível: `marginal_value = lineup_value(roster +
  candidato) - lineup_value(roster)` — ou seja, a contribuição marginal de VOR ao
  lineup titular. Quando `marginal_value <= 0` (candidato iria
  para o banco), o `roster_value` do candidato é um **valor de opção de banco**
  descontado, guiado por VOR positivo: `max(0, vor) * fator[pos]`, com
  `fator` RB = WR = 1.0, TE = 0.6, QB = 0.5, K = DST = 0.2 (RB/WR retêm mais valor
  de banco que QB2/TE2). `roster_value = if (marginal_value > 0) marginal_value
  else valor_de_opção_de_banco`.
- Componente 4: `tier_cliff = points(candidato) - points(melhor disponível na
  mesma posição com `tier` estritamente maior; se não houver, o pior disponível
  da mesma posição; se nem isso, 0)`. `adp_value = current_overall - adp(candidato)`
  (positivo = caiu abaixo do custo de mercado); `adp` ausente/`NA` → `adp_value = 0`.
- `decision_score = 100 * (w_roster * N(roster_value) + w_tier * N(tier_cliff) +
  w_adp * N(adp_value))` menos as penalidades de guardrail (QB2, TE2), com piso 0.
  `N(x)` normaliza para `[0,1]` dentro do conjunto elegível: `(x-min)/(max-min)`,
  e `0` quando `max == min` ou `x` é `NA`. `w_wait` é ignorado nesta story.
- Guardrails de **elegibilidade** (candidato removido da lista):
  - nunca um jogador já draftado (vem de `derive_draft_view()$available`) nem um
    cuja seleção torne um slot mandatório impossível de completar;
  - "estrangula slot": quando `picks_restantes_do_usuário == slots_mandatórios_não
    preenchidos`, um candidato de banco puro (todas as vagas da sua posição já
    preenchidas e sem vaga de FLEX) é removido; um que preenche vaga mandatória
    permanece. `slots_mandatórios` = vetor `roster` menos a entrada `BENCH`;
    `picks_restantes_do_usuário = state$league$rounds - nrow(roster_do_usuário)`;
  - K e DST são removidos enquanto `round_on_clock < state$league$rounds - 2`
    **exceto** quando já são mandatórios sob aperto de viabilidade
    (`picks_restantes_do_usuário <= slots_mandatórios_não_preenchidos`).
- Guardrails de **penalidade** (candidato permanece, `decision_score` reduzido):
  - QB2 (roster já tem ≥ 1 QB e candidato é QB) enquanto qualquer titular
    mandatório ou o FLEX seguir em aberto → penalidade forte (40);
  - TE2, mesma condição → penalidade menor (25).
- Rótulo (primeira regra que casa vence, nesta ordem): `TAKE NOW` (rank 1 **e**
  (preenche need mandatório **ou** condição de tier cliff) **e** `decision_score >=
  60`); `ROSTER NEED` (preenche slot mandatório não preenchido e a folga de picks
  é ≤ 2 **ou** a posição tem ≤ 3 disponíveis no tier do candidato ou melhor);
  `TIER CLIFF` (posição de lineup e ≤ 1 disponível da mesma posição no tier do
  candidato, contando o candidato); `BEST VALUE` (`adp_value >= 8`); `CAN WAIT`
  (default). Todos os limiares são constantes nomeadas no topo do arquivo.
- `reason` é uma string única montada por regras a partir dos fragmentos
  disparados (ganho no lineup, VOR, escassez de tier, desconto de ADP, need
  mandatório, nota de guardrail), no máximo ~4 fragmentos, unidos por `"; "`;
  fallback `"melhor disponivel pelo valor combinado"`.
- Colunas do resultado, nesta ordem (`recommendation-algorithm.md` "Recommendation
  output columns"): `player_id player pos points vor tier adp p_next
  marginal_value wait_cost tier_cliff adp_value decision_score label reason`.
  `p_next` e `wait_cost` são `NA_real_` nesta story.
- Draft completo (`derive_draft_view()$is_complete`) → data frame de 0 linhas com
  o conjunto completo de colunas e tipos.
- `scripts/draft.R` continua adapter: só renderização. Nada de fórmula nova; a
  chamada a `recommend_players()` é embrulhada em `tryCatch` como o resto do loop.

**Ask First:**
- Alterar qualquer contrato de `rds-contracts.md`, a assinatura de
  `recommend_players` em `functional-core.md`, ou os alvos do `Makefile`.
- Adicionar arquivo em `R/` além de `recommendation.R`.
- Adicionar chave nova a `config.R` ou ao contrato de `state/draft.rds`.
- Mudar a discrepância `BENCH` de `rds-contracts.md` (9 titulares + 6 de banco =
  15 vagas, mas 14 rounds) — já registrada em `deferred-work.md`; esta story a
  contorna usando `rounds` e `roster` menos `BENCH`, sem depender do número.

**Never:**
- Implementar `p_next`, `expected_best_next`, `wait_cost` de verdade, o score final
  de 4 termos configurável, ou os testes focados de algoritmo — tudo isso é story 6.
- Monte Carlo, `rnorm`/`runif`/`sample()` não semeado, qualquer RNG no caminho de
  recomendação. Chamada a LLM para rótulo ou explicação.
- Simulação (`R/simulation.R`, `scripts/simulate.R`), Shiny (`app.R`).
- Chamada de rede em `R/` ou `scripts/draft.R`. Reconciliar com `docs/archive/`.
- SQLite/outro banco, event sourcing, R6, golem, targets, Docker, API, injeção de
  dependência.

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| Roster vazio, vez do usuário | 0 picks, usuário na vez | top-n por valor combinado; RB/WR lideram (marginal alto); nenhum K/DST; cada linha com `label` e `reason` | N/A |
| QB2 | roster do usuário tem 1 QB, titulares em aberto | segundo QB com `decision_score` penalizado (40), ranqueado abaixo de RB/WR/TE comparáveis | N/A |
| TE2 | roster tem 1 TE, FLEX em aberto | segundo TE penalizado (25, menos que QB2) | N/A |
| K/DST cedo | round 3, roster longe de cheio | nenhum K nem DST no resultado | N/A |
| K/DST forçado | picks restantes == slots mandatórios (incl. K e DST) | K/DST elegíveis e rotulados `ROSTER NEED` | N/A |
| Estrangula slot | picks restantes == slots mandatórios, candidato é banco puro (ex.: RB4) | esse candidato ausente da lista | N/A |
| Tier cliff | último disponível de um tier numa posição de lineup necessária | rótulo `TIER CLIFF`; `reason` cita a escassez do tier | N/A |
| Faller de ADP | `adp` do candidato bem abaixo do overall atual | `adp_value` positivo; pode receber `BEST VALUE` | N/A |
| Determinismo | mesmo state + snapshot + weights, duas chamadas | ordem das linhas e `decision_score` idênticos | N/A |
| Draft completo | `is_complete == TRUE` | data frame de 0 linhas com todas as colunas/tipos | N/A |
| Sem coluna `adp` | snapshot sem `adp` | `adp_value == 0`, coluna `adp` `NA`, sem crash | degradação, sem erro |
| `n` > elegíveis | `n = 10`, só 4 elegíveis | retorna 4 linhas | N/A |
| `/rec` no terminal | qualquer estado durante o draft | tabela com rank, jogador, pos, points, VOR, tier, `decision_score`, `label` e `reason` | erro embrulhado vira mensagem, loop segue |

</frozen-after-approval>

## Code Map

- `R/recommendation.R` — **novo**. `default_decision_weights()` →
  `c(roster_value = 0.50, wait_cost = 0.30, tier_cliff = 0.15, adp_value = 0.05)`.
  `lineup_value(roster, league)` puro. `recommend_players(state,
  projection_snapshot, weights = default_decision_weights(), n = 10L)`: deriva
  `view <- derive_draft_view(state, projection_snapshot)`, pega
  `view$rosters[[state$user_team]]`, `view$available`, `view$current_overall`,
  `view$round_on_clock`; filtra elegibilidade; calcula componentes; normaliza;
  aplica penalidades; rotula; explica; ordena por `decision_score` desc,
  `player_id` asc; devolve `head(n)`. Helpers internos com prefixo `.warroom_`
  (ex.: `.warroom_lineup_slots`, `.warroom_bench_option_value`,
  `.warroom_unfilled_mandatory`, `.warroom_rec_label`, `.warroom_rec_reason`,
  `.warroom_norm01`). Sem `shiny`, sem rede, sem RNG.
- `R/load_core.R` — `load_core()` faz `source()` de `R/*.R` em ordem alfabética
  (`load_core.R:26-28`), pulando `load_core.R`. `recommendation.R` carrega depois
  de `core.R` (que define `derive_draft_view`, `next_user_pick`,
  `make_snake_schedule`) — ok. Não modificar.
- `R/core.R` — `derive_draft_view():260` dá `available`, `rosters`,
  `round_on_clock`, `current_overall`, `is_complete`; `next_user_pick():318`.
  Usar como está, não modificar.
- `R/projections.R` — `build_synthetic_projections():92` produz o fixture com
  `points`, `vor`, `tier` (por posição, `pmin(ceiling(r/6), 12)`), `pos_rank`,
  `adp`, `overall_rank`. `load_projections():253` devolve o snapshot validado.
  Não modificar.
- `config.R` — `league` (`config.R:6-11`: `roster` nomeado com `BENCH`,
  `flex_positions = c("RB","WR")`), `vor_baseline` (`config.R:16`). Só leitura.
- `scripts/draft.R` — `.warroom_show_recommendations():86` hoje tem o ramo
  degradado ("recomendacoes chegam na story 5") + `.warroom_print_board` como
  _stand-in_. **Substituir** por um renderizador real das colunas de
  `recommend_players()` (rank, player, pos, points, vor, tier, decision_score,
  label, reason), ainda dentro de `tryCatch`. `/rec` (`draft.R:207`) e o
  auto-show na vez do usuário (`draft.R:189`) chamam esse helper — assinatura
  local inalterada. Remover o texto de placeholder. Nada de regra nova.
- `tests/smoke.R` — **estender**: bloco de story 5 antes do Summary
  (`smoke.R:891`). Helpers `fail()` (`smoke.R:15`), `snap`/`team_order`/`cfg` já
  disponíveis no escopo. **Corrigir** as duas asserções da story 4 que casam o
  texto antigo: `smoke.R:782` e `smoke.R:823` (`"recomendacoes chegam na story
  5"` → novo marcador do renderizador real, ex.: `"recomendacoes (top"`).
- `Makefile` — alvo `test` inalterado. `make simulate` ainda falha
  (`scripts/simulate.R` é story 7) — fora do escopo; verificação desta story é
  `make test`.
- `_bmad-output/implementation-artifacts/deferred-work.md:57-59` — item que pede
  exatamente este renderizador real + teste de saída de terminal; esta story o
  resolve.

## Tasks & Acceptance

**Execution:**
- [x] `R/recommendation.R` — criar. `default_decision_weights()`, `lineup_value()`
  e `recommend_players()` + helpers `.warroom_`. Componentes 1 e 4, guardrails de
  elegibilidade e de penalidade, rótulos, explicações, colunas e ordem exatas,
  determinismo com desempate por `player_id`. `p_next`/`wait_cost` = `NA_real_`.
  Puro, offline, sem `shiny`/RNG/rede.
- [x] `scripts/draft.R` — trocar o _stand-in_ de `.warroom_show_recommendations`
  por um renderizador da saída real de `recommend_players()`, dentro de
  `tryCatch`; remover o texto de placeholder da story 5.
- [x] `tests/smoke.R` — bloco offline de story 5 cobrindo cada linha da matriz
  I/O (construindo estados com `new_draft` + `record_pick` sobre `snap`,
  `tempdir()` só, sem rede): pesos default, `lineup_value` direto, ranking de
  roster vazio, penalidade QB2 e TE2, exclusão de K/DST cedo e inclusão quando
  forçados, exclusão do candidato que estrangula slot, rótulos `TIER CLIFF` /
  `BEST VALUE` / `ROSTER NEED` / `CAN WAIT`, determinismo (duas chamadas
  idênticas), draft completo → 0 linhas, snapshot sem `adp`, `n` > elegíveis.
- [x] `tests/smoke.R` — corrigir as duas asserções da story 4 que casam
  `"recomendacoes chegam na story 5"` para o novo marcador; exercitar `/rec` real
  num `run_draft()` guiado por `textConnection` e afirmar que a tabela sai com
  `label` e `reason`.

**Acceptance Criteria:**
- Given `make test` sem rede, when executado, then status 0 e o bloco de story 5
  passa junto com os de stories 1–4.
- Given `grep -nE "monte|rnorm|runif|\bsample\(|p_next *<-|wait_cost *<- *[^N]" R/recommendation.R`,
  when inspecionado, then nenhuma ocorrência (sem Monte Carlo, sem RNG, `p_next` e
  `wait_cost` ficam `NA`).
- Given `grep -nE "shiny|http[s]?://|read\.|readRDS|saveRDS|scrape" R/recommendation.R`,
  when inspecionado, then nenhuma ocorrência.
- Given duas chamadas de `recommend_players()` com o mesmo `state`, o mesmo
  `projection_snapshot` e os mesmos `weights`, when comparadas, then os data
  frames são `identical()`.
- Given qualquer estado, when `recommend_players()` retorna, then nenhum
  `player_id` do resultado está em `state$picks$player_id` e nenhum candidato de
  banco puro aparece quando `picks_restantes == slots_mandatórios_não_preenchidos`.
- Given um round anterior a `rounds - 2` e um roster sem aperto de viabilidade,
  when `recommend_players()` retorna, then nenhuma linha tem `pos %in% c("K","DST")`.
- Given a vez do usuário no terminal, when o prompt aparece, then a tabela de
  recomendações real (com `decision_score`, `label`, `reason`) já foi impressa —
  sem o texto "chegam na story 5".

## Spec Change Log

- **2026-09-01 — `lineup_value` passa a somar `vor`, não `points` (renegociação do
  bloco frozen, autorizada pelo humano em sessão durante a implementação).**
  Achado: com `lineup_value` em `points` bruto, os 4 primeiros recomendados no
  pick 1 eram QBs (QB1 ≈ 380 pts de ganho marginal vs RB1 ≈ 343) e a coluna `vor`
  não entrava em nenhum termo do score — contradizendo a linha "RB/WR lideram" da
  matriz, CAP-8 ("rank by ... VOR ...") e a lógica de draft VBD. Emenda:
  `lineup_value` soma o `vor` do melhor lineup (`points` como fallback se
  ausente); `marginal_value` vira contribuição marginal de VOR. `tier_cliff`
  continua em `points` (queda de projeção, não de valor); `adp_value` e os pesos
  (0.50 / 0.30 / 0.15 / 0.05) ficam como estavam. Evita: um ranqueador que ignora
  escassez posicional e recomenda QB no pick 1. KEEP: a fórmula do `decision_score`
  de 3 termos, o desempate por `player_id`, e `p_next`/`wait_cost` = `NA` até a
  story 6.

## Design Notes

- **Score parcial nesta story.** `decision_score` combina só `roster_value`,
  `tier_cliff`, `adp_value` (pesos crus 0.50 / 0.15 / 0.05, sem renormalizar);
  penalidades QB2/TE2 subtraídas depois. `N()` é monótona e o mesmo peso multiplica
  todos os candidatos → ordem determinística. As colunas `p_next`/`wait_cost` já
  saem no resultado (como `NA_real_`) para o contrato não mudar na story 6.
- **`lineup_value` — exemplo (soma de `vor` do melhor lineup):**
  ```
  roster (vor): QB 80 | RB 140, RB 120, RB 95 | WR 110, WR 90 | TE 55
  lineup = 80 + (140+120) + (110+90) + 55 + FLEX(melhor RB/WR restante = 95)
         = 675
  ```
  QB1 vor (~80) < RB1 vor (~145), então RB/WR lideram o pick 1 — ao contrário de
  `points` bruto, onde QB1 (~380) > RB1 (~343).
- **Rótulos sem `p_next`.** `TAKE NOW` e `CAN WAIT` na doc dependem de `p_next`
  (story 6). Aqui `TAKE NOW` é aproximado ("rank 1 + need/cliff + score alto") e
  `CAN WAIT` é o default; a story 6 refina ambos. A lista e a prioridade dos
  rótulos permanecem.
- **Renderizador do terminal.** `.warroom_show_recommendations` perde o ramo
  _stand-in_ (`recommend_players` sempre existe agora); formata `rank. player
  (pos)  score X  [LABEL]  reason`, alinhado, dentro do `tryCatch` do loop.

## Verification

**Commands:**
- `make test` — expected: status 0, sem rede; bloco de story 5 + stories 1–4.
- `Rscript -e 'source("R/load_core.R"); load_core(); snap <- build_synthetic_projections(); st <- new_draft(snap, sprintf("Team %02d", 1:12), "Team 01"); r <- recommend_players(st, snap); stopifnot(nrow(r) == 10L, !any(r$pos %in% c("K","DST")), identical(r, recommend_players(st, snap)))'`
  — expected: sem erro.
- `grep -nE "monte|rnorm|runif|\bsample\(|shiny|http" R/recommendation.R` — expected: sem saída.
- `printf 'Team 01,Team 02,Team 03,Team 04,Team 05,Team 06,Team 07,Team 08,Team 09,Team 10,Team 11,Team 12\n/rec\n/quit\n' | Rscript scripts/draft.R` com `state/` limpo
  — expected: imprime a tabela de recomendações com `label` e `reason`, sem o texto "chegam na story 5", sai 0.

## Suggested Review Order

**O algoritmo (comece aqui)**

- Ponto de entrada: deriva a view, filtra elegíveis, calcula componentes, pontua, rotula, ordena.
  [`recommendation.R:256`](../../../../R/recommendation.R#L256)
- Renegociação central: `vor` é a moeda de valor, `points` só como fallback.
  [`recommendation.R:110`](../../../../R/recommendation.R#L110)
- `lineup_value` público: melhor lineup por VOR; K/DST fora; slot vazio = 0.
  [`recommendation.R:128`](../../../../R/recommendation.R#L128)
- Núcleo do melhor lineup a partir de vetores paralelos pos/valor; soma independe de desempate.
  [`recommendation.R:81`](../../../../R/recommendation.R#L81)
- Pesos default (0.50 / 0.30 / 0.15 / 0.05); `wait_cost` carregado mas ignorado nesta story.
  [`recommendation.R:56`](../../../../R/recommendation.R#L56)

**Guardrails e viabilidade (invariantes 7-9)**

- Filtro de elegibilidade: estrangulamento de slot mandatório + K/DST cedo.
  [`recommendation.R:280`](../../../../R/recommendation.R#L280)
- Slots mandatórios não preenchidos + necessidade de FLEX não coberta por sobra RB/WR.
  [`recommendation.R:134`](../../../../R/recommendation.R#L134)
- Score de 3 termos + penalidades QB2 (-40) / TE2 (-25) com titulares em aberto.
  [`recommendation.R:323`](../../../../R/recommendation.R#L323)
- Rótulos por regra (prioridade) e `reason` montada de fragmentos.
  [`recommendation.R:348`](../../../../R/recommendation.R#L348)

**Adapter de terminal**

- Renderizador real de `recommend_players()` (sem o ramo _stand-in_), dentro do `tryCatch`.
  [`draft.R:86`](../../../../scripts/draft.R#L86)

**Testes**

- Bloco offline de story 5: cada linha da matriz I/O, `tempdir()` apenas, sem rede.
  [`smoke.R:891`](../../../../tests/smoke.R#L891)
- Asserções da story 4 realinhadas ao renderizador real (`recomendacoes (top`).
  [`smoke.R:782`](../../../../tests/smoke.R#L782)
