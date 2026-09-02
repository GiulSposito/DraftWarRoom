# RDS contracts

Companion to `SPEC.md`. The two operational RDS files and the normalized player table. Downstream stories must not change these contracts without a spec update.

## `data/projections.rds`

An immutable list, written by `scripts/prepare.R` (CAP-1) or the synthetic fixture builder (CAP-2). Immutable for the duration of a draft.

Keys, at least:

| key | meaning |
|---|---|
| `schema_version` | integer, currently `1` |
| `created_at` | `POSIXct` snapshot timestamp |
| `season` | integer season year |
| `method` | aggregation method used, initially `"robust"` |
| `scoring` | the full scoring-rules object used |
| `vor_baseline` | named numeric vector of per-position VOR baselines |
| `players` | data frame, one row per player (see below) |

### Normalized `players` table

One row per player. No duplicate `player_id`. Contains, when available:

```
player_id      player          nfl_team       pos
points         source_sd       source_low     source_high
vor            low_vor         high_vor
overall_rank   pos_rank        tier
adp            adp_sd
```

Required fields (validated, reject on failure): `player_id`, `player`, `pos`, `points`. `pos` is one of `QB`, `RB`, `WR`, `TE`, `K`, `DST`.

`source_sd` / `source_low` / `source_high` are dispersion across projection sources (from `ffanalytics` `sd_pts` / `floor` / `ceiling`), not a probabilistic season model.

## `state/draft.rds`

The single source of truth for a draft. Written atomically after every accepted pick (CAP-4). A `state/draft.rds.bak` holds the previous state.

Keys, at least:

| key | meaning |
|---|---|
| `schema_version` | integer, currently `1` |
| `projection_created_at` | `created_at` of the snapshot this draft is bound to |
| `league` | list resolved from `config/league.yml`: `teams` (12), `roster` named integer vector, `flex_positions` (`c("RB","WR")`), and `rounds` — **derived, not stored**, as the sum of every `roster` slot (starters + bench) |
| `team_order` | character vector of team names in draft-slot order |
| `user_team` | one entry from `team_order` |
| `seed` | integer, for reproducible simulation/tie-breaks |
| `picks` | ordered data frame (see below) |

`roster` named vector for the initial league: `QB=1, RB=2, WR=2, TE=1, FLEX=1, K=1, DST=1, BENCH=6`. Its slots sum to 15, so `rounds` is 15 and the draft is 180 picks (12 × 15).

### `picks` data frame

Ordered, append-only during a draft. At least:

```
overall      integer, 1..180, equals row number
player_id    character, must exist in the snapshot, unique within picks
entered_at   POSIXct
```

### Never persisted

Current pick, team on the clock, per-team rosters, available players, best lineup, next user pick, position-within-round, recommendations. All derived (CAP-5). The next overall pick is always `nrow(picks) + 1`.

## Invariants

1. The next overall pick is `nrow(picks) + 1`.
2. The team on the clock comes from the generated snake schedule.
3. A player cannot be drafted twice.
4. A drafted `player_id` must exist in the projection snapshot.
5. Undo removes only the most recent pick.
6. Picks cannot exceed teams × rounds (180).
7. Recommendations contain only available players.
8. Recommendations must not make completing mandatory roster slots impossible.
9. The same snapshot, configuration, and pick state produce the same recommendation order.
