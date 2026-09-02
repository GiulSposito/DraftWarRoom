---
title: 'Simulador de mock draft e calibracao'
type: 'feature'
created: '2026-09-02'
status: 'done'
review_loop_iteration: 0
baseline_commit: 'd47a38cf60b434461b7a3fc1b8c489f3566021af'
context:
  - '/Users/gsposito/Projects/football/DraftWarRoom/_bmad-output/specs/spec-fantasy-warroom/SPEC.md'
  - '/Users/gsposito/Projects/football/DraftWarRoom/_bmad-output/specs/spec-fantasy-warroom/operations.md'
  - '/Users/gsposito/Projects/football/DraftWarRoom/_bmad-output/specs/spec-fantasy-warroom/functional-core.md'
  - '/Users/gsposito/Projects/football/DraftWarRoom/_bmad-output/specs/spec-fantasy-warroom/recommendation-algorithm.md'
  - '/Users/gsposito/Projects/football/DraftWarRoom/_bmad-output/specs/spec-fantasy-warroom/rds-contracts.md'
  - '/Users/gsposito/Projects/football/DraftWarRoom/AGENTS.md'
---

<frozen-after-approval reason="human-owned intent — do not modify unless human renegotiates">

## Intent

**Problem:** Stories 1-6 entregaram todo o core de draft ao vivo e o algoritmo de
recomendação, mas nada roda um mock draft completo para depurar, comparar
estratégias ou calibrar os pesos do `decision_score`. `R/simulation.R` e
`scripts/simulate.R` ainda não existem (CAP-10).

**Approach:** Criar `R/simulation.R` (puro) com `opponent_pick()` determinístico
dado um "valor de mercado" já sorteado, `simulate_draft()` (168 picks, seed único
gera o ruído de mercado uma vez, o resto é determinístico), comparação das
estratégias `adp`/`vor`/`warroom` para o time do usuário, o conjunto de métricas
de `operations.md` e uma grade de calibração pequena e transparente
(`expand.grid`, sem algoritmo genético). `scripts/simulate.R` roda uma suíte
reduzida por padrão e a calibração completa só sob flag explícita.

## Boundaries & Constraints

**Always:**
- Todo código novo em `R/simulation.R`, puro, offline, sem `shiny`. Carregado por
  `load_core()`. Reaproveita (leitura apenas, não modifica) `make_snake_schedule`,
  `new_draft`, `record_pick`, `derive_draft_view` (`R/core.R`); `recommend_players`,
  `default_decision_weights`, `lineup_value`, e os helpers `.warroom_` de
  `R/recommendation.R` (`best_lineup`, `slot_counts`, `pos_count`,
  `unfilled_mandatory`, `value_of`, `bench_value`, `col`, `pick_sd`, `pos_levels`
  de `R/core.R`) — mesmo ambiente global via `load_core()`, sem duplicar fórmula.
- **`opponent_pick(available, roster, league, market_value)`**: puro/determinístico
  — recebe o vetor de mercado já sorteado (nomeado por `player_id`), filtra
  candidatos elegíveis (mesmo strand-guard de `recommend_players`: nunca inviabiliza
  slot mandatório; K/DST só nos rounds finais salvo squeeze) mais um teto
  posicional simples e nomeado `.warroom_sim_pos_cap` (`QB=2, RB=8, WR=8, TE=2,
  K=1, DST=1`, ignorado só quando o strand-guard exige a posição), e escolhe o
  `player_id` de menor `market_value` (desempate `player_id` asc). `stop()` se
  não sobrar candidato elegível.
- **`simulate_draft(snapshot, team_order, user_team, seed, strategy =
  c("adp","vor","warroom"), weights = default_decision_weights(), league =
  NULL)`**: gera `market_value = adp + ruído` uma única vez por chamada, com
  `set.seed(seed)` isolado (salva/restaura `.Random.seed` global — nunca vaza
  estado de RNG para quem chamou) e desvio de `.warroom_pick_sd(adp, adp_sd)`;
  jogador sem `adp` recebe o pior `market_value` (maior valor finito + 1,
  desempate por ordem de player_id). Roda os 168 picks via `record_pick()` (nunca
  duplica a validação). No turno do `user_team`: `strategy = "warroom"` chama
  `recommend_players(state, snapshot, weights, n = 1L)$player_id[1]` (o algoritmo
  real, sem heurística paralela); `"adp"`/`"vor"` usam o mesmo filtro de
  elegibilidade do `opponent_pick` (sem `market_value`/ruído) ordenando por `adp`
  asc ou `vor` desc. Todo outro time usa `opponent_pick()`. Retorna
  `list(state, metrics, rosters_valid)`: `metrics` (lista, só do `user_team`) com
  `starter_points`, `starter_vor` (= `lineup_value` do roster final),
  `bench_vor`, `pos_counts` (vetor nomeado QB..DST), `adp_surplus`,
  `reach_count`, `roster_valid`, `qb_round`, `te_round`; `rosters_valid` (lógico
  nomeado por `team_order`, via `.warroom_unfilled_mandatory(...)$total == 0` e
  `nrow(roster) == league$rounds`).
- **Determinismo**: mesmo `snapshot` + `team_order` + `user_team` + `seed` +
  `strategy` + `weights` → `state`/`metrics` `identical()` entre duas chamadas.
- **`compare_strategies(snapshot, team_order, user_team, seed, strategies =
  c("adp","vor","warroom"), weights = default_decision_weights())`**: roda
  `simulate_draft()` para cada estratégia com o mesmo `seed` (mesmo sorteio de
  mercado — comparação justa) e devolve um data frame, uma linha por estratégia,
  com todas as métricas achatadas (`n_QB`..`n_DST` em vez do vetor `pos_counts`)
  mais `all_rosters_valid` (todos os 12 times).
- **`default_weight_grid()`**: exatamente a grade de `operations.md`
  (`roster_value` 0.40/0.50/0.60, `wait_cost` 0.20/0.30/0.40, `tier_cliff`
  0.10/0.15/0.20), `adp_value = 1 - soma das três`, descartando linhas com
  `adp_value < 0`.
- **`calibrate_weights(snapshot, team_order, seeds = c(1L,2L,3L), slots =
  c(1L,6L,12L), grid = default_weight_grid())`**: para cada linha da grade, roda
  `simulate_draft(strategy = "warroom")` para cada combinação `slot`×`seed`
  (`user_team = team_order[slot]`); fitness por corrida =
  `starter_vor + .warroom_calib_bench_frac*bench_vor +
  .warroom_calib_adp_frac*adp_surplus -
  .warroom_calib_invalid_penalty*!roster_valid` (constantes nomeadas no topo do
  arquivo: `0.5`, `0.1`, `1000`). Agrega por linha: `mean_fitness`, `sd_fitness`
  (0 se uma corrida só), `risk_score = mean_fitness -
  .warroom_calib_variance_penalty * sd_fitness` (constante `1.0`),
  `all_valid`. Devolve o data frame da grade ordenado por `risk_score` desc
  (grid + agregados). **Nunca** algoritmo genético/evolutivo — só o loop
  transparente sobre `expand.grid`.
- `scripts/simulate.R`: adapter só de I/O. Sem args: `compare_strategies()` com
  1-2 seeds (suíte reduzida, rápida, para dev) e checa `all_rosters_valid`. Com
  `--calibrate`: roda `calibrate_weights()` completo e imprime a tabela ordenada
  (execução mais pesada, só sob pedido explícito). Usa `.warroom_load_config()`
  (`R/projections.R`) e `load_projections(cfg$paths)` já existentes — nenhum
  loader de config novo.
- `tests/smoke.R`: novo bloco de story 7 antes do Summary, cobrindo a matriz
  abaixo. `make simulate` deve funcionar (`Makefile` já tem o alvo).

**Ask First:**
- Qualquer mudança em `R/recommendation.R`, `R/core.R`, `R/persistence.R`,
  `R/projections.R`, no `Makefile`, ou nos pesos default de
  `default_decision_weights()`.

**Never:**
- Algoritmo genético ou qualquer otimizador não-transparente para calibração.
- Chamada de rede; RNG fora de `simulate_draft()`'s bloco isolado; RNG em
  `R/recommendation.R`.
- Duplicar fórmula de `lineup_value`/`marginal_value`/bench-discount/guardrails
  — sempre reusar os helpers de `recommendation.R`.
- Simulação/calibração dentro do caminho de `recommend_players()` (CAP-9
  continua puramente analítico).

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| Draft completo | `simulate_draft(..., strategy = "warroom")` | 168 picks, `rosters_valid` todo `TRUE`, `state$picks` sem duplicata | N/A |
| Determinismo | duas chamadas, mesmos argumentos | `identical()` em `state` e `metrics` | N/A |
| Três estratégias | `compare_strategies(...)` mesmo seed | data frame de 3 linhas, colunas com as 8 métricas de `operations.md` + `all_rosters_valid` | N/A |
| `opponent_pick` nunca redraft | qualquer turno de oponente | `player_id` retornado sempre em `available$player_id` e nunca já em `state$picks` | N/A |
| Strand guard | 2 picks restantes, só K/DST faltam | `opponent_pick`/`adp`/`vor` ignoram o teto posicional e preenchem o mandatório | N/A |
| Calibração mínima | grade de 2 linhas, 1 seed, 1 slot | `calibrate_weights()` devolve 2 linhas com `mean_fitness`/`risk_score` finitos, ordenadas | N/A |
| `make simulate` | execução padrão sem flag | roda rápido (suíte reduzida), imprime as 3 estratégias, sai 0 | N/A |

</frozen-after-approval>

## Code Map

- `R/simulation.R` — **novo**. Constantes: `.warroom_sim_pos_cap`,
  `.warroom_sim_reach_margin` (10), `.warroom_calib_bench_frac` (0.5),
  `.warroom_calib_adp_frac` (0.1), `.warroom_calib_invalid_penalty` (1000),
  `.warroom_calib_variance_penalty` (1.0). Helpers privados:
  `.warroom_with_seed(seed, expr)` (salva/restaura `.Random.seed`),
  `.warroom_market_value(players, seed)`, `.warroom_eligible_sim_candidates
  (available, roster, league, round_on_clock)` (strand-guard + K/DST grace +
  teto posicional, reusado por `opponent_pick` e pelas estratégias `adp`/`vor`),
  `.warroom_sim_starter_ids(roster, league)` (espelha a seleção de
  `.warroom_best_lineup` — mesma métrica de valor, mesmos slots/flex — mas
  devolve `player_id`s com desempate, para separar titular de banco; não altera
  `recommendation.R`), `.warroom_roster_is_valid(roster, league)`,
  `.warroom_sim_metrics(roster, state, snapshot, league, team)`. Funções
  públicas: `opponent_pick`, `simulate_draft`, `compare_strategies`,
  `default_weight_grid`, `calibrate_weights`.
- `R/core.R` — `make_snake_schedule():50`, `new_draft():126`, `record_pick():183`,
  `derive_draft_view():260`, `.warroom_resolve_league` (interno) — **reusar, não
  modificar**.
- `R/recommendation.R` — `recommend_players():409`, `default_decision_weights():82`,
  `lineup_value():154`, e os `.warroom_` internos citados acima
  (`best_lineup:107`, `slot_counts:87`, `pos_count:98`, `unfilled_mandatory:162`,
  `value_of:136`, `bench_value:226`, `col:189`, `pick_sd:264`) — **reusar, não
  modificar**.
- `R/projections.R` — `.warroom_load_config():55`, `load_projections():253` —
  reusados por `scripts/simulate.R`, igual a `scripts/draft.R`.
- `scripts/simulate.R` — **novo**, mesmo padrão de `scripts/draft.R`
  (`source("R/load_core.R"); load_core()`, carrega config + snapshot, sem regra
  de negócio própria).
- `tests/smoke.R` — **estender**, bloco de story 7 antes do `## --- Summary`
  (`smoke.R:1205`), reusando `snap`, `team_order`, `cfg` do escopo.

## Tasks & Acceptance

**Execution:**
- [x] `R/simulation.R` — constantes + `.warroom_with_seed`, `.warroom_market_value`,
  `.warroom_eligible_sim_candidates`, `opponent_pick`, `simulate_draft`,
  `.warroom_sim_starter_ids`, `.warroom_roster_is_valid`, `.warroom_sim_metrics`,
  `compare_strategies`, `default_weight_grid`, `calibrate_weights`.
- [x] `scripts/simulate.R` — suíte reduzida por padrão; `--calibrate` roda a
  grade completa.
- [x] `tests/smoke.R` — bloco de story 7 cobrindo a matriz I/O acima.

**Acceptance Criteria:**
- Given `make test`, when executado sem rede, then status 0 com os blocos de
  stories 1-7.
- Given `make simulate`, when executado, then imprime as 3 estratégias e sai 0
  em tempo curto (suíte reduzida, sem calibração completa).
- Given duas chamadas de `simulate_draft()` com os mesmos argumentos, when
  comparadas, then `identical()`.
- Given qualquer `simulate_draft()` completo, when os 12 rosters finais são
  inspecionados, then todos têm 14 jogadores e nenhum slot mandatório vazio.
- Given `grep -nE "monte|rnorm|runif|\bsample\(|genetic|GA\b" R/recommendation.R`,
  when inspecionado, then nenhuma ocorrência (RNG fica só em `simulation.R`).

## Design Notes

- **Ruído de mercado uma vez só.** `market_value` é sorteado uma única vez por
  `simulate_draft()` (não por pick), via `.warroom_with_seed(seed, rnorm(...))`
  com `sd = .warroom_pick_sd(adp, adp_sd)` — a mesma escala de dispersão que
  `p_next` já usa, então "quanto o mercado erra o ADP" tem uma única definição
  no projeto. O resto do draft é 100% determinístico dado esse vetor.
- **`warroom` reusa o algoritmo de verdade.** A estratégia `"warroom"` não
  reimplementa nada — chama `recommend_players()` e pega o topo. Isso também
  significa que o custo de `recommend_players()` (~130ms/chamada, já anotado em
  `deferred-work.md`) só entra 14x por simulação (só nos turnos do usuário), não
  168x — mantém `simulate_draft()` rápido o bastante para os testes offline.
- **Calibração é busca em grade, não otimização.** `calibrate_weights()` é um
  loop duplo (grade × seeds × slots) somando/tirando média de uma fórmula de
  fitness fixa — nenhuma seleção, mutação ou geração evolutiva. `risk_score`
  penaliza variância para não escolher uma configuração que só funciona num
  slot/seed sortudo.

## Verification

**Commands:**
- `make test` — expected: status 0, sem rede; bloco de story 7 junto com 1-6.
- `make simulate` — expected: tabela das 3 estratégias, sai 0, roda em segundos
  (sem `--calibrate`).
- `Rscript scripts/simulate.R --calibrate` — expected: tabela da grade de
  calibração ordenada por `risk_score`, sai 0 (execução mais longa, manual).
- `grep -nE "genetic|evolution|GA\(" R/simulation.R` — expected: sem saída.

## Suggested Review Order

**Um mock draft completo (entry point)**

- Um seed sorteia o mercado uma vez; os 168 picks depois disso são 100% determinísticos — a estratégia `warroom` chama `recommend_players()` de verdade.
  [`simulation.R:315`](../../../../R/simulation.R#L315)

**Ruído de mercado e isolamento de RNG**

- Único ponto de RNG em todo `R/`: `sd` reaproveita `.warroom_pick_sd` (a mesma escala que `p_next` já usa).
  [`simulation.R:76`](../../../../R/simulation.R#L76)

- `set.seed()` salva/restaura `.Random.seed` global para nunca vazar estado para quem chamou.
  [`simulation.R:52`](../../../../R/simulation.R#L52)

**Elegibilidade compartilhada (oponente + estratégias adp/vor)**

- Mesmo strand-guard de `recommend_players()` mais um teto posicional simples; comentário deixa claro que é espelhado, não compartilhado, porque `recommendation.R` está congelado nesta story.
  [`simulation.R:112`](../../../../R/simulation.R#L112)

- Escolhe sempre o candidato elegível de menor `market_value` já sorteado; desempate por `player_id`.
  [`simulation.R:156`](../../../../R/simulation.R#L156)

**Métricas por draft**

- Espelha a seleção de `.warroom_best_lineup()` com desempate por `player_id` para separar titular de banco por identidade.
  [`simulation.R:184`](../../../../R/simulation.R#L184)

- As 8 métricas de `operations.md` — starter points/VOR, bench VOR, ADP surplus, reach count, QB/TE round — a partir dos picks reais do time.
  [`simulation.R:231`](../../../../R/simulation.R#L231)

**Comparação de estratégias e calibração**

- Mesmo seed nas 3 estratégias (mesmo sorteio de mercado) para comparação justa; achata `pos_counts` em colunas `n_QB`..`n_DST`.
  [`simulation.R:390`](../../../../R/simulation.R#L390)

- `expand.grid` com `adp_value` completando a soma a 1; nenhuma linha negativa sobrevive.
  [`simulation.R:432`](../../../../R/simulation.R#L432)

- Loop transparente grade x seeds x slots com `risk_score = mean - variância`; nunca um otimizador genético/evolutivo.
  [`simulation.R:461`](../../../../R/simulation.R#L461)

**Adapter de linha de comando**

- Suíte reduzida por padrão; falha alto (`SIMULATE FAIL`) se qualquer estratégia deixar um roster inválido.
  [`simulate.R:45`](../../../../scripts/simulate.R#L45)

- `--calibrate` roda a grade completa e avisa se a configuração recomendada não passou `all_valid`.
  [`simulate.R:72`](../../../../scripts/simulate.R#L72)

- Flag desconhecida vira erro claro em vez de cair silenciosamente na suíte reduzida.
  [`simulate.R:33`](../../../../scripts/simulate.R#L33)

**Testes (story 7)**

- Bloco offline completo cobrindo toda a matriz I/O: `opponent_pick`, draft completo, determinismo, seeds diferentes, RNG isolado, comparação, strand guard/teto posicional, grade default, calibração (incluindo recomputo manual da agregação multi-run), `make simulate`, e o grep anti-RNG/genético.
  [`smoke.R:1205`](../../../../tests/smoke.R#L1205)

- Registro de dívida técnica intencionalmente adiada (divergência de flex hipotética, cobertura de `--calibrate`, isolamento de falha na grade de calibração, entre outras).
  [`deferred-work.md`](../../../implementation-artifacts/deferred-work.md)
