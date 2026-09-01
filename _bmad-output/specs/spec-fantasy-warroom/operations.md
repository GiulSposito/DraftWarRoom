# Operations

Companion to `SPEC.md`. Repository shape, commands, terminal interface, simulator, calibration, verification, and the fixed story order.

## Repository shape

```
fantasy-warroom/
├── app.R
├── config.R
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

Minor adjustments allowed only when code evidence requires them. Not present this epic: `DESCRIPTION`, `NAMESPACE`, R6 classes, golem, SQLite, event sourcing, an API, Docker, a `targets` pipeline, background workers, authentication, Shiny modules, a generic repository layer, dependency injection.

## Commands

```
make prepare    Rscript scripts/prepare.R
make test       Rscript tests/smoke.R
make simulate   Rscript scripts/simulate.R
make draft      Rscript scripts/draft.R
make app        Rscript -e 'shiny::runApp(".")'
```

Run `make test` after every implementation story. Run `make simulate` after any recommendation or simulation change.

## Terminal draft interface (CAP-7)

`scripts/draft.R` is a fast interactive loop. At startup it loads the projection snapshot and either creates or resumes `state/draft.rds`, then shows the current round, overall pick, team on the clock, and the user's next pick.

Player-name resolution, in order: exact normalized name, substring match, prefix match, `adist()` fuzzy fallback, numbered disambiguation list.

Commands:

```
/rec        top recommendations with score, label, key metrics, explanation
/board      best available overall
/board rb   best available filtered by position
/team       the user's roster
/teams      all rosters
/undo       remove the last pick
/status     round, overall pick, team on the clock, user's next pick
/save       explicit save
/quit       save and exit
```

On the user's turn the top recommendations are shown automatically.

## Simulator (CAP-10)

`scripts/simulate.R` runs complete mock drafts. For each mock, derive a latent market pick per player from ADP plus configurable random variation. Opponent teams generally take the best remaining market option subject to simple roster feasibility and reasonable positional limits.

Strategies compared, at least: `adp`, `vor`, `warroom`.

Metrics reported, at least:

```
projected starter points     starter VOR              discounted bench VOR
position counts              ADP surplus              reach count
roster validity              QB round                 TE round
```

Deterministic seeds. Mocks are for debugging, calibration, and strategy comparison — not proof of season results.

## Calibration

Start with a small transparent grid over recommendation weights (not a genetic algorithm), e.g.:

```r
expand.grid(roster_value = c(0.40, 0.50, 0.60),
            wait_cost    = c(0.20, 0.30, 0.40),
            tier_cliff   = c(0.10, 0.15, 0.20))
```

`adp_value` completes the sum to 1. Fitness favors starter VOR plus a fraction of bench VOR and ADP surplus, with a large penalty for invalid rosters; prefer configurations that are good across snake slots and low-variance, not just highest mean.

## Verification (`make test`)

At minimum:

- a 12-team, 14-round snake schedule contains 168 picks and reverses correctly;
- duplicate players are rejected;
- undo restores the last player to availability;
- state reload preserves all picks;
- recommendations never contain drafted players;
- identical input yields identical recommendation order;
- every simulated draft completes with valid rosters;
- terminal and Shiny use the same recommendation function.

`make simulate` runs a repeatable reduced mock suite for development; a larger count is used only for explicit calibration runs.

## Shiny (CAP-11)

`app.R` is a thin shell over the same core functions and RDS files, no duplicated formulas. One operational page: round / overall pick / team on the clock / user's next pick; player search and Draft; Undo; top recommendations and explanations; user's roster with starters, FLEX, and bench; recent picks; available-player table with position filtering. Player filtering feels immediate; recording and saving a pick is effectively instantaneous; recommendation refresh targets ~300 ms and stays well under one second; no network or scraper work in the live path.

## Required story order

Eight independently reviewable stories, this order, no story doing a later story's work:

1. **Walking skeleton and synthetic snapshot** — minimal repository, `config.R`, `Makefile`, core loader, synthetic `projections.rds`, smoke-test command.
2. **ffanalytics projection adapter** — custom scoring, scraping/preparation, normalization, validation, raw snapshot, `projections.rds` generation, without changing the runtime core contract.
3. **Snake schedule, draft state, and RDS persistence** — schedule generation, state creation, derived views, atomic save/load, backup, pick validation, undo.
4. **Operational terminal draft** — interactive loop, player-name resolution, required commands, resume behavior, full reduced rehearsal.
5. **Roster-aware recommendation foundation** — lineup valuation, marginal roster value, VOR/tier ranking, guardrails, deterministic labels and explanations.
6. **Market-aware wait intelligence** — `p_next`, expected best survivor, wait cost, tier cliff, ADP value, final configurable score, focused algorithm tests.
7. **Mock simulator and calibration** — opponent selection, complete seeded mocks, strategy comparison, metrics, weight-grid calibration, invalid-roster checks.
8. **Thin Shiny War Room** — single-page live UI over the shared core, state recovery, pick entry, undo, recommendations, roster, draft log, terminal-vs-Shiny equivalence rehearsal.

Human checkpoint required for stories 1, 3, 5, 6, and 8 (contracts, persistence, algorithm behavior, live UX).
