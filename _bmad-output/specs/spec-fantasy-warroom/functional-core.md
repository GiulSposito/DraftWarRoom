# Functional core

Companion to `SPEC.md`. The plain functions under `R/` that hold all business rules. None import `shiny`. `scripts/` and `app.R` call these and add no logic of their own.

## Function catalog

| function | responsibility |
|---|---|
| `make_snake_schedule()` | generate the 168 turns for 12 teams × 14 rounds, serpentine |
| `new_draft()` | create the initial `state/draft.rds` list |
| `record_pick()` | validate and append a player to `picks` |
| `undo_pick()` | remove the most recent pick |
| `derive_draft_view()` | current pick, team on the clock, rosters, available players, lineup |
| `next_user_pick()` | the user's next overall selection |
| `lineup_value()` | value of the best possible lineup for a roster |
| `recommend_players()` | rank candidates; see `recommendation-algorithm.md` |
| `opponent_pick()` | simulated-team selection behavior |
| `simulate_draft()` | run one complete mock draft |
| `load_state()` | read `state/draft.rds` |
| `save_state()` | atomic write of `state/draft.rds` with `.bak` backup |

## Contract shape

```r
recommend_players(state, projection_snapshot,
                  weights = default_decision_weights(), n = 10L)
```

Deterministic: same `state` + `projection_snapshot` + `weights` → same ordered result.

## File layout under `R/`

- `core.R` — schedule, draft state, `record_pick`, `undo_pick`, `derive_draft_view`, `next_user_pick`
- `recommendation.R` — `lineup_value`, `recommend_players`, components, guardrails, labels, explanations
- `simulation.R` — `opponent_pick`, `simulate_draft`, strategy comparison, calibration
- `persistence.R` — `load_state`, `save_state`, backup, schema checks

## Invariants (also in `rds-contracts.md`)

1. Next overall pick is `nrow(picks) + 1`.
2. Team on the clock comes from the snake schedule.
3. No player drafted twice.
4. Drafted `player_id` must exist in the snapshot.
5. Undo removes only the most recent pick.
6. Picks cannot exceed 168.
7. Recommendations contain only available players.
8. Recommendations never make mandatory roster slots impossible to complete.
9. Same snapshot + config + pick state → same recommendation order.
