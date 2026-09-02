---
title: 'Inteligência de espera ciente do mercado'
type: 'feature'
created: '2026-09-01'
status: 'done'
review_loop_iteration: 0
baseline_commit: '8a186ab273065e8477ede341faf14c14fd37c8e9'
context:
  - '/Users/gsposito/Projects/football/DraftWarRoom/_bmad-output/specs/spec-fantasy-warroom/SPEC.md'
  - '/Users/gsposito/Projects/football/DraftWarRoom/_bmad-output/specs/spec-fantasy-warroom/recommendation-algorithm.md'
  - '/Users/gsposito/Projects/football/DraftWarRoom/_bmad-output/specs/spec-fantasy-warroom/functional-core.md'
  - '/Users/gsposito/Projects/football/DraftWarRoom/_bmad-output/specs/spec-fantasy-warroom/rds-contracts.md'
  - '/Users/gsposito/Projects/football/DraftWarRoom/AGENTS.md'
---

<frozen-after-approval reason="human-owned intent — do not modify unless human renegotiates">

## Intent

**Problem:** A story 5 entregou `recommend_players()` com os componentes 1 e 4
(valor marginal do roster, `tier_cliff`, `adp_value`) e um `decision_score` de
apenas 3 termos; as colunas `p_next` e `wait_cost` saem `NA` e nada no algoritmo
pesa o custo de esperar até o próximo pick do usuário. O usuário precisa, em cada
pick pessoal, saber a probabilidade de um jogador sobreviver até sua próxima
seleção, qual a melhor alternativa esperada naquele momento, e o custo de esperar
— combinados no score final configurável de 4 termos (CAP-9, `recommendation-
algorithm.md` componentes 2 e 3).

**Approach:** Estender `R/recommendation.R` (puro, offline, determinístico, sem
Monte Carlo, sem RNG) com: `p_next` como probabilidade **condicional** de
sobrevivência via aproximação normal da distribuição de pick a partir de `adp` /
`adp_sd`; `expected_best_next(pos)` analítico a partir dos `p_next` dos
disponíveis; `wait_cost = max(0, roster_value(candidato) - expected_best_next(pos))`;
e o `decision_score` de 4 termos incluindo `w_wait * N(wait_cost)`. `tier_cliff`
e `adp_value` já existem da story 5 e não mudam de fórmula — só passam a dividir
o score com o novo `wait_cost`. Rótulos `TAKE NOW` / `CAN WAIT` passam a usar
`p_next`. `scripts/draft.R` mostra `p_next` e `wait_cost` na tabela (só
renderização). Testes focados de algoritmo em `tests/smoke.R`.

## Boundaries & Constraints

**Always:**
- Todo o código novo em `R/recommendation.R`, puro e offline: sem `shiny`, sem
  rede, sem I/O de arquivo, sem RNG, **sem Monte Carlo**. Carregado por
  `load_core()`. Assinatura de `recommend_players()` inalterada (`state,
  projection_snapshot, weights = default_decision_weights(), n = 10L`).
- Determinístico: mesmo `state` + `projection_snapshot` + `weights` → mesma ordem
  e mesmos valores (`identical()`). Desempate sempre `player_id` ascendente
  (`method = "radix"`). Nenhuma função de `stats` que use RNG; só `pnorm`.
- **`p_next`** (`recommendation-algorithm.md` componente 2): distribuição de pick
  do jogador ≈ `Normal(adp, sd)`, com
  `sd = max(.warroom_adp_sd_min, .warroom_adp_sd_mult * adp_sd_do_snapshot)`;
  quando o snapshot não traz `adp_sd`, `adp_sd_do_snapshot = .warroom_adp_sd_frac
  * adp`. `.warroom_adp_sd_min`, `.warroom_adp_sd_mult`, `.warroom_adp_sd_frac`
  são constantes nomeadas no topo do arquivo (o "desvio-padrão configurável").
  Sobrevivência **condicional** a estar disponível agora:
  `p_next = P(pick >= following_pick) / P(pick >= current_overall)`, calculada em
  espaço log (`pnorm(..., lower.tail = FALSE, log.p = TRUE)`, diferença, `exp`)
  para estabilidade quando as duas caudas são minúsculas. Resultado **limitado a
  `[0, 1]`**. `p_next` é auxílio operacional, não probabilidade calibrada.
- **`following_pick`** = menor `overall` do schedule cujo slot é o do usuário e
  que é **estritamente maior** que `current_overall` (o pick pessoal *depois*
  deste). Derivado de `make_snake_schedule()` por helper interno `.warroom_`
  (não alterar `next_user_pick()`, cuja semântica "≥ pick atual" retorna o pick
  atual quando o usuário está na vez).
- **`expected_best_next(pos)`** (componente 3): calculado **uma vez por posição
  presente entre os candidatos** (não por candidato). Ordena os disponíveis da
  posição (`view$available`, antes do filtro de elegibilidade) por `vor` desc,
  `player_id` asc; toma os primeiros `.warroom_survivor_cap` (constante). Para
  esse pool: `p_best(j) = p_next(j) * prod_{h<j} (1 - p_next(h))`;
  `expected_best_next(pos) = sum_j value(j) * p_best(j)`, onde `value(j)` é o
  `roster_value` do sobrevivente `j` calculado igual ao dos candidatos (marginal
  no lineup se `> 0`, senão valor de opção de banco descontado), contra o
  `base_lineup` do usuário. Sobreviventes com `p_next` `NA` são removidos do pool.
- **`wait_cost`** = `max(0, roster_value(candidato) - expected_best_next(pos(candidato)))`.
- **`decision_score`** de 4 termos:
  `100 * (w_roster*N(roster_value) + w_wait*N(wait_cost) + w_tier*N(tier_cliff)
  + w_adp*N(adp_value))`, menos penalidades de guardrail (QB2 −40, TE2 −25),
  piso 0. Pesos crus de `default_decision_weights()` (`0.50 / 0.30 / 0.15 /
  0.05`), sem renormalizar (igual à story 5). `N()` é `.warroom_norm01`
  existente: `N` de um vetor todo-`NA` já devolve zeros, então o termo de espera
  degrada sozinho para 0 quando `wait_cost` é indisponível — sem caso especial no
  score.
- **`p_next` / `wait_cost` = `NA_real_`** quando: o snapshot não tem coluna `adp`;
  **ou** `following_pick` é `NA` (usuário sem picks futuros); **ou**, por
  candidato, o `adp` do candidato é `NA`. Nesses casos o score cai para os 3
  termos disponíveis (comportamento idêntico ao da story 5).
- **Rótulos** (mesma lista e mesma ordem de prioridade da story 5): `TAKE NOW`
  passa a exigir `rank 1` **e** `decision_score >= .warroom_take_now_score` **e**
  (`p_next <= .warroom_take_now_pnext` **ou** need mandatório crítico **ou**
  condição de tier cliff); `CAN WAIT` continua o default e cobre o caso
  "`p_next >= .warroom_can_wait_pnext`". `ROSTER NEED`, `TIER CLIFF`, `BEST VALUE`
  inalterados. Todos os limiares são constantes nomeadas no topo do arquivo.
- **`reason`**: acrescentar fragmentos determinísticos para `p_next` baixo
  ("provavel que saia antes do seu proximo pick (p_next X.XX)") e para
  `wait_cost` alto ("custo de esperar +X.X de VOR"); manter o teto de ~4
  fragmentos unidos por `"; "` e o fallback existente.
- Colunas do resultado e sua ordem **inalteradas** (`.warroom_rec_columns`);
  `p_next` e `wait_cost` continuam `numeric`. Draft completo → data frame de 0
  linhas com o conjunto e os tipos completos (já feito).
- `scripts/draft.R` continua adapter: `.warroom_show_recommendations` ganha
  `p_next` e `wait_cost` na segunda linha de cada item, dentro do `tryCatch`.
  Nenhuma fórmula nova.

**Ask First:**
- Alterar `rds-contracts.md`, a assinatura de `recommend_players` ou
  `next_user_pick` em `functional-core.md`, ou os alvos do `Makefile`.
- Adicionar arquivo em `R/` além de `recommendation.R`, ou adicionar chave a
  `config.R` / ao contrato de `state/draft.rds` (os parâmetros de `p_next` ficam
  como constantes em `recommendation.R`, não em `config.R`).
- Mudar a discrepância `BENCH` de `rds-contracts.md` (já em `deferred-work.md`);
  esta story a contorna usando `state$league$rounds`, como a story 5.
- Mudar os pesos default ou introduzir renormalização do `decision_score`.

**Never:**
- Monte Carlo, `rnorm`/`runif`/`sample()`/qualquer RNG no caminho de recomendação;
  chamada a LLM para rótulo ou `reason`.
- Alterar as fórmulas de `lineup_value`, `marginal_value`, `tier_cliff`,
  `adp_value` ou os guardrails de elegibilidade/penalidade da story 5.
- Simulação (`R/simulation.R`, `scripts/simulate.R`), Shiny (`app.R`), trabalho de
  qualquer story posterior.
- Chamada de rede em `R/` ou `scripts/draft.R`. Reconciliar com `docs/archive/`.
- SQLite/outro banco, event sourcing, R6, golem, targets, Docker, API, injeção de
  dependência.

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| Pick pessoal, snapshot com `adp` | roster vazio, usuário na vez (pick 1) | toda linha tem `p_next` em `[0,1]` e `wait_cost >= 0` finito; jogador de `adp` baixo tem `p_next` menor que um de `adp` alto na mesma posição | N/A |
| Determinismo | mesmo state + snapshot + weights, duas chamadas | data frames `identical()` (ordem, `p_next`, `wait_cost`, `decision_score`) | N/A |
| Posição secando | disponíveis daquela posição quase todos com `adp` < próximo pick do usuário | candidato ali recebe `wait_cost` alto e, no rank 1 com score alto, rótulo `TAKE NOW` | N/A |
| Posição profunda | muitos disponíveis com `p_next` alto | `wait_cost` baixo/zero; rótulo tende a `CAN WAIT` | N/A |
| `w_wait` importa | comparar `recommend_players(..., weights c/ wait_cost = 0)` vs default num estado onde uma posição seca | a ordem dos candidatos muda entre as duas chamadas | N/A |
| Sem coluna `adp` | snapshot sem `adp`/`adp_sd` | `p_next` e `wait_cost` todos `NA`; `decision_score` finito (3 termos); sem crash | degradação, sem erro |
| Sem próximo pick do usuário | estado no último round, usuário já sem pick futuro | `p_next` e `wait_cost` `NA`; score de 3 termos | N/A |
| `adp` `NA` por jogador | snapshot com coluna `adp` mas alguns `NA` | esses candidatos: `p_next` e `wait_cost` `NA`; demais calculados; sobreviventes com `p_next` `NA` não entram no `expected_best_next` | N/A |
| Draft completo | `is_complete == TRUE` | data frame de 0 linhas com todas as colunas/tipos | N/A |
| `p_next` limitado | jogador ainda disponível bem além do `adp` (caudas minúsculas) | `p_next` finito em `[0,1]`, sem `NaN`/`Inf` (cálculo em log) | N/A |
| `/rec` no terminal | vez do usuário | tabela mostra `p_next` e `wait` além de score/label/reason | erro embrulhado vira mensagem, loop segue |

</frozen-after-approval>

## Code Map

- `R/recommendation.R` — **estender**. Novas constantes no topo (junto das da
  story 5): `.warroom_adp_sd_min`, `.warroom_adp_sd_mult`, `.warroom_adp_sd_frac`,
  `.warroom_survivor_cap`, `.warroom_take_now_pnext`, `.warroom_can_wait_pnext`.
  Novos helpers `.warroom_`: `.warroom_following_user_pick(state, current_overall)`
  (usa `make_snake_schedule`, `match(state$user_team, state$team_order)`);
  `.warroom_pick_sd(adp, adp_sd)` vetorizado; `.warroom_p_next(adp, sd,
  current_overall, following_pick)` vetorizado, em log, `pmin(pmax(., 0), 1)`;
  `.warroom_expected_best_next(available_pos, r_pos, r_val, base_lineup, league,
  sd, current_overall, following_pick)` devolve um escalar. Em
  `recommend_players()` ([`recommendation.R:256`](../../../../R/recommendation.R#L256)):
  após o bloco de componentes da story 5, computar `following_pick`; `p_next` dos
  candidatos (coluna); `expected_best_next` uma vez por `unique(cand$pos)`;
  `wait_cost` por candidato; trocar o `score` de 3 para 4 termos
  ([`recommendation.R:324`](../../../../R/recommendation.R#L324)); preencher
  `p_next`/`wait_cost` no `data.frame` de saída
  ([`recommendation.R:393`](../../../../R/recommendation.R#L393), hoje `NA_real_`);
  refinar rótulos ([`recommendation.R:366`](../../../../R/recommendation.R#L366)) e
  `.warroom_rec_reason` ([`recommendation.R:204`](../../../../R/recommendation.R#L204)).
  `roster_value` dos sobreviventes reaproveita a lógica marginal-ou-banco já no
  loop de candidatos — extrair para um helper `.warroom_roster_value_of(pos, val,
  vor, r_pos, r_val, base_lineup, league)` e chamar dos dois lados.
- `R/core.R` — `next_user_pick():318` e `make_snake_schedule():50` usados como
  referência pelo helper novo; **não modificar**. `derive_draft_view():260` dá
  `available`, `rosters`, `current_overall`, `round_on_clock`, `is_complete`.
- `R/projections.R` — `build_synthetic_projections():92`: fixture traz `adp`
  (`overall_rank + wobble`) e `adp_sd` (`round(4 + 0.05*adp, 1)`).
  `normalize_projections():406`: `adp`/`adp_sd` viajam como par e podem ser
  descartados juntos — daí o fallback `.warroom_adp_sd_frac`. **Não modificar.**
- `scripts/draft.R` — `.warroom_show_recommendations():86`: acrescentar `p_next`
  e `wait` à segunda linha (`fmt_num` já existe para `NA -> "-"`). Só formatação,
  dentro do `tryCatch`. `/rec` (`draft.R:215`) e o auto-show (`draft.R:196`) já
  chamam o helper.
- `config.R` — `league` (`config.R:6`), só leitura. Nenhuma chave nova.
- `tests/smoke.R` — **corrigir** `smoke.R:958`: a asserção da story 5
  (`!all(is.na(r0$p_next)) || !all(is.na(r0$wait_cost))` → `fail`) agora inverte —
  com `adp` no fixture, `r0$p_next` passa a ser calculado. Trocar por: `p_next` em
  `[0,1]` e `wait_cost >= 0` para `r0`. **Estender**: bloco de story 6 antes do
  Summary (`smoke.R:1063`), reusando `snap`, `team_order`, `cfg`, `fail`,
  `s4_run`, `team_line`, `has`, `s5_state` do escopo.
- `Makefile` — alvo `test` inalterado; `make simulate` ainda falha
  (`scripts/simulate.R` é story 7) — fora do escopo, verificação é `make test`.
- `_bmad-output/implementation-artifacts/deferred-work.md:22` — item da story 1
  sobre o `adp` quase-monótono do fixture: `p_next` fica uma função suave do rank,
  suficiente para exercitar o mecanismo; a divergência mercado-vs-valor mais rica
  continua deferida (não resolver aqui).

## Tasks & Acceptance

**Execution:**
- [x] `R/recommendation.R` — adicionar constantes e helpers `.warroom_`
  (`following_user_pick`, `pick_sd`, `p_next`, `expected_best_next`,
  `roster_value_of`), computar `p_next` e `wait_cost` em `recommend_players()`,
  trocar `decision_score` para 4 termos, preencher as colunas `p_next`/`wait_cost`,
  refinar rótulos (`TAKE NOW`/`CAN WAIT` com `p_next`) e `reason`. Puro, offline,
  determinístico, sem Monte Carlo/RNG. `p_next`/`wait_cost` = `NA_real_` nos três
  casos de degradação.
- [x] `scripts/draft.R` — `.warroom_show_recommendations`: exibir `p_next` e
  `wait` na tabela, dentro do `tryCatch`; sem regra nova.
- [x] `tests/smoke.R` — corrigir `smoke.R:958`; adicionar bloco offline de story 6
  cobrindo cada linha da matriz I/O: limites `[0,1]` de `p_next`, `wait_cost >= 0`,
  monotonicidade de `p_next` por `adp` na mesma posição, determinismo
  (`identical()` de duas chamadas), posição secando → `wait_cost` alto +
  `TAKE NOW`, posição profunda → `wait_cost` baixo + `CAN WAIT`, `w_wait = 0` muda
  a ordem, snapshot sem `adp` → tudo `NA` e score finito, sem próximo pick →
  `NA`, `adp` `NA` por jogador, draft completo → 0 linhas, estabilidade numérica
  para jogador muito além do `adp`, e `/rec` no terminal mostrando `p_next`/`wait`.

**Acceptance Criteria:**
- Given `make test` sem rede, when executado, then status 0 e o bloco de story 6
  passa junto com os de stories 1–5.
- Given `grep -nE "monte|rnorm|runif|\bsample\(|replicate|\bboot\b" R/recommendation.R`,
  when inspecionado, then nenhuma ocorrência.
- Given `grep -nE "shiny|http[s]?://|readRDS|saveRDS|read\.|scrape" R/recommendation.R`,
  when inspecionado, then nenhuma ocorrência.
- Given duas chamadas de `recommend_players()` com o mesmo `state`, o mesmo
  `projection_snapshot` e os mesmos `weights`, when comparadas, then os data
  frames são `identical()`, incluindo `p_next` e `wait_cost`.
- Given qualquer estado com a coluna `adp` presente e `following_pick` não-`NA`,
  when `recommend_players()` retorna, then todo `p_next` finito está em `[0, 1]`
  (sem `NaN`/`Inf`) e todo `wait_cost` finito é `>= 0`.
- Given um snapshot sem coluna `adp`, when `recommend_players()` retorna, then
  `p_next` e `wait_cost` são todos `NA` e `decision_score` é finito e não-negativo.
- Given a vez do usuário no terminal, when a tabela de `/rec` é impressa, then ela
  mostra `p_next` e `wait` além de `decision_score`, `label` e `reason`.

## Design Notes

- **Sobrevivência condicional em log.** `z = (x - adp)/sd`;
  `l1 = pnorm(z_following, lower.tail = FALSE, log.p = TRUE)`,
  `l0 = pnorm(z_current, lower.tail = FALSE, log.p = TRUE)`;
  `p_next = exp(l1 - l0)`. Para um jogador muito além do `adp` as duas caudas são
  ~`1e-12` e a razão direta vira `0/0` — o espaço log resolve. `following >
  current` ⇒ `l1 <= l0` ⇒ `p_next <= 1`; `pmin(pmax(., 0), 1)` cobre ruído de
  ponto flutuante.
- **`expected_best_next` uma vez por posição.** Depende só de posição, pool de
  disponíveis, `p_next` e `following_pick` — nunca do candidato. Calcular por
  posição (≤ 6), reusar para todos os candidatos dela, mantém o custo perto do da
  story 5. O candidato entra no próprio pool (segue disponível se você não o
  pegar). `p_next` não tem termo próprio no score (`recommendation-algorithm.md`
  não define `w_pnext`) — age via `wait_cost`, rótulos e coluna informativa.
- **`value(j)` = `roster_value` do sobrevivente, não `vor` cru.** `wait_cost`
  subtrai `roster_value(candidato) - expected_best_next(pos)`; as duas pontas
  usam a mesma `.warroom_roster_value_of` para ficarem na mesma escala (marginal
  no lineup, com fallback de banco). Candidato de banco puro ⇒ `wait_cost` ~0.
- **Exemplo (fixture, pick 1, `following_pick = 24`):** `SYN-RB-001` (`adp ≈ 2`,
  `sd ≈ 4.1`) ⇒ `p_next ≈ 1e-7`, some; WR de `adp ≈ 40` (`sd ≈ 6`) ⇒
  `p_next ≈ 0.996`, `CAN WAIT`.

## Verification

**Commands:**
- `make test` — expected: status 0, sem rede; bloco de story 6 + stories 1–5.
- `Rscript -e 'source("R/load_core.R"); load_core(); snap <- build_synthetic_projections(); st <- new_draft(snap, sprintf("Team %02d", 1:12), "Team 01"); r <- recommend_players(st, snap); stopifnot(all(r$p_next >= 0 & r$p_next <= 1), all(r$wait_cost >= 0), identical(r, recommend_players(st, snap)))'`
  — expected: sem erro.
- `grep -nE "monte|rnorm|runif|\bsample\(|replicate" R/recommendation.R` — expected: sem saída.
- `printf 'Team 01,Team 02,Team 03,Team 04,Team 05,Team 06,Team 07,Team 08,Team 09,Team 10,Team 11,Team 12\n/rec\n/quit\n' | Rscript scripts/draft.R` com `state/` limpo
  — expected: tabela de `/rec` com `p_next` e `wait`, sai 0.
</content>
</invoke>
