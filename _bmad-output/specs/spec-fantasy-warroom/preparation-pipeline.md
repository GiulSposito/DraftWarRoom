# Preparation pipeline

Companion to `SPEC.md`. Covers CAP-1. Everything here happens only in `scripts/prepare.R`, before a draft, with network access. The live path never runs any of it.

## Steps

1. Load league scoring rules from `config.R`.
2. Start from `ffanalytics`'s complete scoring rules and override only the league differences — Full-PPR receptions (`rec = 1`) and any configured passing, turnover, kicker, or DST values. Copy-and-override, so less visible categories (field goals by distance, extra points, sacks, defensive TDs, points-allowed brackets) are preserved automatically.
3. Run `scrape_data()` for `QB`, `RB`, `WR`, `TE`, `K`, `DST`.
4. Save the raw result to `data/raw_scrape.rds` so projections can be rebuilt without repeating every scrape.
5. Run `projections_table()` with custom scoring, configured VOR baselines, and one aggregation method, initially `"robust"`.
6. Add player information and ADP when available (`add_player_info()`, `add_adp()`).
7. Normalize to one row per player, mapping to the `players` schema in `rds-contracts.md`.
8. Validate required fields (`player_id`, `player`, `pos`, `points`); reject duplicate `player_id`.
9. Save the immutable snapshot to `data/projections.rds` with the list keys in `rds-contracts.md`.

## `ffanalytics` field mapping

| snapshot field | `ffanalytics` source |
|---|---|
| `player_id` | `id` |
| `player` | `first_name` + `last_name` |
| `nfl_team` | `team` |
| `points` | `points` |
| `source_sd` | `sd_pts` |
| `source_low` | `floor` |
| `source_high` | `ceiling` |
| `vor` / `low_vor` / `high_vor` | `points_vor` / `floor_vor` / `ceiling_vor` |
| `overall_rank` / `pos_rank` / `tier` | `rank` / `pos_rank` / `tier` |
| `adp` / `adp_sd` | from `add_adp()` |

## Initial parameters

- Aggregation method: `"robust"` (may later become `"weighted"` without changing the RDS contract or the draft engine).
- VOR baseline: `c(QB = 13, RB = 35, WR = 36, TE = 13, K = 13, DST = 13)`.
- ECR and extra uncertainty layers (`add_ecr()`, `add_uncertainty()`) are out of scope for the first pass; `source_sd` is sufficient as a divergence indicator.
- Pin a known working version or commit of `ffanalytics` in `renv`.

## Synthetic fixture (CAP-2)

A separate builder produces a synthetic `data/projections.rds` satisfying the same schema, so core code and `make test` never depend on live scrapers or the network.
