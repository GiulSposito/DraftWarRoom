# Fantasy Draft War Room — Authoritative Implementation Intent

## Authority and scope

This document is the authoritative input for the simplified implementation. It supersedes earlier, more elaborate proposals that used SQLite, event sourcing, a package architecture, asynchronous workers, live Monte Carlo, multiple abstract engines, or a generalized multi-user platform. Those ideas are historical context only and must not be reintroduced unless a later approved change explicitly requests them.

Treat the work as one spec-backed epic implemented through small, independently reviewable stories.

## Why

Build a local, single-user NFL Fantasy Draft War Room in R for an experimental 12-team Full-PPR snake draft. The application must allow one person to prepare projections before the draft, simulate drafts in the terminal, operate a real draft quickly, and receive transparent pick recommendations that account for player value, roster fit, positional tiers, ADP, and the cost of waiting until the user's next pick.

The system must favor reliability, explainability, and implementation speed over architectural generality.

## Target league

Initial supported configuration:

- 12 fantasy teams.
- Snake draft.
- 15 rounds — one pick per roster slot (9 starters + 6 bench).
- Starting roster: QB 1, RB 2, WR 2, TE 1, FLEX 1 restricted to RB/WR, K 1, DST 1.
- Bench: 6 (any position profile).
- Full PPR.
- Draft order is entered immediately before the draft.
- The user's team and draft slot are configurable.

The league format (team count, roster slots, bench, flex positions) lives in a YAML file, `config/league.yml`, read by the functional core on the live draft path. The number of rounds is not stored — it is derived as the sum of all roster slots (starters + bench), so bench depth and round count can never disagree. Only this initial format needs complete validation in the first epic.

## Delivery strategy

Implement the functional core before the graphical interface:

1. Create a small executable R skeleton with synthetic projection data.
2. Integrate `FantasyFootballAnalytics/ffanalytics` only in the pre-draft preparation script.
3. Implement snake scheduling, draft state, RDS persistence, and a terminal draft loop.
4. Implement and test the recommendation algorithm.
5. Implement terminal mock simulation and calibration.
6. Add Shiny as a thin interface over the exact same core functions.

The terminal implementation is a real product and an operational fallback, not disposable scaffolding.

## Technical constraints

- R is the only application language.
- Runtime data and persistence use RDS.
- The application is local and single-user.
- `ffanalytics` may be called only by the pre-draft preparation path, never while a live draft is running.
- The live path must not require network access.
- Business rules live in plain functions under `R/` and must not depend on Shiny.
- `scripts/` and `app.R` are adapters over the same functional core.
- Persist facts and derive views: save the ordered picks, but derive the current pick, rosters, available players, lineup, and recommendations.
- Keep dependencies minimal and pin them with `renv`.
- Pin a known working version or commit of `ffanalytics`.
- Do not introduce SQLite, another database, event sourcing infrastructure, R6, golem, targets, Docker, an API, authentication, background workers, or dependency-injection frameworks.
- Do not perform live Monte Carlo simulations in the recommendation path.
- Do not add generic support for every fantasy league format during this epic.

## Repository shape

Use this small structure unless code evidence requires a minor adjustment:

```text
fantasy-warroom/
├── app.R
├── config.R
├── config/
│   ├── league.yml
│   └── score_settings.yml
├── Makefile
├── renv.lock
├── R/
│   ├── core.R
│   ├── recommendation.R
│   ├── simulation.R
│   └── persistence.R
├── scripts/
│   ├── prepare.R
│   ├── simulate.R
│   └── draft.R
├── data/
│   ├── raw_scrape.rds
│   └── projections.rds
├── state/
│   ├── draft.rds
│   └── draft.rds.bak
└── tests/
    └── smoke.R
```

Expected commands:

```text
make prepare
make test
make simulate
make draft
make app
```

## Pre-draft projections

Use `ffanalytics` as the source of the static valuation layer.

The preparation script must:

1. Load league scoring rules from `config.R`.
2. Start from the package's complete scoring rules and override only league differences, including Full-PPR receptions and any configured passing, turnover, kicker, or DST values.
3. Run `scrape_data()` for QB, RB, WR, TE, K, and DST.
4. Save the raw result to `data/raw_scrape.rds` so projections can be rebuilt without repeating every scrape.
5. Run `projections_table()` with custom scoring, configured VOR baselines, and one selected aggregation method, initially `robust`.
6. Add player information and ADP when available.
7. Normalize the result into one row per player.
8. Validate required fields and reject duplicate `player_id` values.
9. Save an immutable snapshot to `data/projections.rds`.

The normalized player table should contain, when available:

```text
player_id
player
nfl_team
pos
points
source_sd
source_low
source_high
vor
low_vor
high_vor
overall_rank
pos_rank
tier
adp
adp_sd
```

Interpret the package's floor, ceiling, and standard deviation as dispersion across projection sources, not as a complete probabilistic model of the player's season.

The runtime must also work with a synthetic projection fixture so core development and tests do not depend on live scrapers.

## Runtime RDS contracts

### `data/projections.rds`

Store a list with at least:

```text
schema_version
created_at
season
method
scoring
vor_baseline
players
```

This file is immutable during a draft.

### `state/draft.rds`

Store a list with at least:

```text
schema_version
projection_created_at
league
team_order
user_team
seed
picks
```

`picks` is an ordered data frame containing at least:

```text
overall
player_id
entered_at
```

Do not persist derived current-pick, roster, or availability fields.

Saving must be atomic enough for local use: write a temporary file, keep a backup of the previous state, and rename the temporary file into place. Every accepted pick saves immediately.

## Functional core

Implement a small set of plain functions with deterministic contracts:

```text
make_snake_schedule()
new_draft()
record_pick()
undo_pick()
derive_draft_view()
next_user_pick()
lineup_value()
recommend_players()
opponent_pick()
simulate_draft()
load_state()
save_state()
```

Core invariants:

1. The next overall pick is `nrow(picks) + 1`.
2. The team on the clock comes from the generated snake schedule.
3. A player cannot be drafted twice.
4. A drafted `player_id` must exist in the projection snapshot.
5. Undo removes only the most recent pick.
6. Picks cannot exceed teams multiplied by rounds.
7. Recommendations contain only available players.
8. Recommendations must not make completing mandatory roster slots impossible.
9. The same snapshot, configuration, and pick state produce the same recommendation order.

## Terminal draft interface

`scripts/draft.R` must provide a fast interactive loop.

At startup it loads the projection snapshot and either creates or resumes `state/draft.rds`. It displays the current round, overall pick, team on the clock, and the user's next pick.

Player entry should support exact normalized names, substring matching, prefix matching, and a small numbered disambiguation list. Approximate matching with base R `adist()` may be used as a fallback.

Required commands:

```text
/rec
/board
/board rb
/team
/teams
/undo
/status
/save
/quit
```

When it is the user's turn, show the top recommendations automatically with score, label, key metrics, and a concise deterministic explanation.

## Recommendation algorithm

The first production algorithm must be transparent and fast. It should combine four understandable components rather than use a black-box optimizer.

### 1. Roster marginal value

Calculate the best current lineup as:

- best QB;
- best two RBs;
- best two WRs;
- best TE;
- best remaining RB or WR as FLEX.

For each candidate:

```text
marginal_value = lineup_value(roster + candidate) - lineup_value(roster)
```

A candidate who remains on the bench receives a discounted option value based primarily on positive VOR. RB and WR bench options should retain more value than QB2 and TE2 because they can cover more starting and FLEX situations.

### 2. Probability of surviving to the user's next pick

Use ADP as market price. Derive a configurable draft standard deviation from ADP, `adp_sd`, and a minimum spread. Use a conditional survival probability so the calculation recognizes that the player is still available now.

The result is `p_next`, an approximate probability that the player remains available at the user's next selection.

This value is an operational decision aid, not a claim of perfectly calibrated probability.

### 3. Expected best alternative next time

For each position, sort available players by value and use their `p_next` values to calculate the expected value of the best survivor at the user's next pick. Do this analytically and deterministically; do not run live Monte Carlo.

Define the simplified wait cost as the positive difference between taking the candidate now and the expected best alternative later.

### 4. Tier cliff and ADP value

Use the tier supplied by `ffanalytics`. Measure how many relevant players remain in the candidate's tier and the projected drop to the best available player in the next tier.

Define ADP value as the difference between the current overall pick and the player's ADP; positive values mean the player fell beyond market cost.

### Initial combined score

Normalize components inside the current candidate shortlist and begin with configurable weights similar to:

```text
roster_value 0.50
wait_cost    0.30
tier_cliff   0.15
adp_value    0.05
```

These are initial hypotheses to calibrate through mocks, not immutable truths.

### Guardrails

- Do not recommend K or DST before the final rounds unless remaining roster slots make them mandatory.
- Penalize QB2 strongly while mandatory starters or FLEX remain open.
- Penalize TE2 while higher-value starting or FLEX needs remain.
- Preserve greater bench option value for RB and WR.
- When remaining picks equal remaining mandatory slots, only positions that maintain roster feasibility are eligible.

### Explanations and labels

Generate explanations through deterministic rules, not an LLM call.

Useful labels include:

```text
TAKE NOW
BEST VALUE
CAN WAIT
TIER CLIFF
ROSTER NEED
```

Each recommendation should state the most important reasons, such as marginal lineup gain, VOR, low `p_next`, last player in tier, ADP discount, or mandatory roster need.

## Terminal simulator

`scripts/simulate.R` must run complete mock drafts.

For each mock, derive a latent market pick for every player from ADP plus configurable random variation. Opponent teams generally select the best remaining market option subject to simple roster feasibility and reasonable positional limits.

Support comparison of at least:

```text
adp
vor
warroom
```

Report at least:

```text
projected starter points
starter VOR
discounted bench VOR
position counts
ADP surplus
reach count
roster validity
QB round
TE round
```

Use deterministic seeds. Mocks are for debugging, calibration, and strategy comparison, not proof of future league results.

Calibration should start with a small transparent grid over recommendation weights, not a genetic algorithm.

## Shiny interface

Implement Shiny only after the terminal draft and simulator work.

`app.R` must be a thin shell over the same core functions and RDS files. Do not duplicate formulas or business rules in Shiny reactives.

One operational page is enough. It should show:

- round, overall pick, team on the clock, and user's next pick;
- player search and Draft action;
- Undo action;
- top recommendations and explanations;
- user's roster with starters, FLEX, and bench;
- recent picks;
- available-player table with position filtering.

The terminal and Shiny interfaces must produce the same recommendation order for the same state and snapshot.

Target live behavior:

- player filtering feels immediate;
- recording and saving a pick is effectively instantaneous for this data size;
- the recommendation refresh should normally complete in well under one second and should target roughly 300 ms or less on the development machine;
- no network or scraper work occurs in the live path.

## Verification

At minimum, `make test` must verify:

- a 12-team, 15-round snake schedule contains 180 picks and reverses correctly;
- duplicate players are rejected;
- undo restores the last player to availability;
- state reload preserves all picks;
- recommendations never contain drafted players;
- identical input yields identical recommendation order;
- every simulated draft completes with valid rosters;
- terminal and Shiny use the same recommendation function.

`make simulate` must run a repeatable reduced mock suite suitable for development. A larger mock count may be used for explicit calibration runs.

## Non-goals for this epic

- Multi-user collaboration.
- Cloud deployment.
- Multiple simultaneous drafts.
- Automatic synchronization with a fantasy platform.
- Live injury/news ingestion.
- Live projection scraping.
- Universal scoring or roster-rule support.
- Historical season outcome backtesting.
- Machine-learned or genetic recommendation optimization.
- Mobile-first design.
- A polished public product.

## Required story order

Break this epic into exactly these independently reviewable stories, in this order:

1. **Walking skeleton and synthetic snapshot** — create the minimal repository, `config.R`, Makefile, core loader, synthetic `projections.rds`, and smoke-test command.
2. **ffanalytics projection adapter** — implement custom scoring, scraping/preparation, normalization, validation, raw snapshot, and `projections.rds` generation without changing the runtime core contract.
3. **Snake schedule, draft state, and RDS persistence** — implement schedule generation, state creation, derived views, atomic save/load, backup, pick validation, and undo.
4. **Operational terminal draft** — implement the interactive draft loop, player-name resolution, required commands, resume behavior, and a full reduced rehearsal.
5. **Roster-aware recommendation foundation** — implement lineup valuation, marginal roster value, VOR/tier candidate ranking, guardrails, deterministic labels, and explanations.
6. **Market-aware wait intelligence** — implement `p_next`, expected best survivor, wait cost, tier cliff, ADP value, final configurable score, and focused algorithm tests.
7. **Mock simulator and calibration** — implement opponent selections, complete seeded mocks, strategy comparison, metrics, weight-grid calibration, and invalid-roster checks.
8. **Thin Shiny War Room** — implement the single-page live UI over the shared core, state recovery, pick entry, undo, recommendations, roster, draft log, and terminal-versus-Shiny equivalence rehearsal.

For stories 1, 3, 5, 6, and 8, require a human checkpoint before or after implementation because they establish contracts, persistence, algorithm behavior, or live operating UX. Later automation may be used only after these patterns are stable.

## Epic success signal

The epic is successful when one person can:

1. generate or load a projection snapshot;
2. configure the 12-team draft order;
3. conduct all 180 picks in the terminal, stopping and resuming safely;
4. receive fast, deterministic, explainable recommendations on every personal pick;
5. run seeded mock drafts to compare ADP, VOR, and War Room strategies;
6. conduct the same draft through a simple Shiny interface that returns the same recommendations as the terminal core.
