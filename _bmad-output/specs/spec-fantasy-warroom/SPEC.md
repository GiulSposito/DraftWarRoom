---
id: SPEC-fantasy-warroom
companions:
  - rds-contracts.md
  - recommendation-algorithm.md
  - functional-core.md
  - preparation-pipeline.md
  - operations.md
  - ../../../AGENTS.md
sources:
  - ../../../docs/fantasy-warroom-bmad-intent.md
---

> **Canonical contract.** This SPEC and the files in `companions:` are the complete, preservation-validated contract for what to build, test, and validate. Source documents listed in frontmatter are for traceability — consult them only if you need narrative rationale or prose color this contract intentionally omits.

# Fantasy Draft War Room

## Why

This is a **vision to realize** with a hard **deadline**: a local, single-user NFL Fantasy Draft War Room, in R, for one experimental 12-team Full-PPR snake draft. One person needs to prepare projections before the draft, rehearse drafts in the terminal, operate the real draft quickly on the day, and receive transparent pick recommendations that weigh player value, roster fit, positional tiers, ADP, and the cost of waiting until their next pick. The draft is a one-time ~180-pick live event; a tool that breaks or stalls on draft day is unrecoverable, so the terminal path is simultaneously the first usable product, the simulation environment, the executable specification of the mechanism, and the operational fallback if the graphical interface fails. Every trade-off resolves toward reliability, explainability, and implementation speed over architectural generality.

## Capabilities

- **CAP-1 — Pre-draft projection preparation**
  - **intent:** User runs a preparation script that turns `ffanalytics` multi-source scrapes into an immutable, normalized projection snapshot using league-custom Full-PPR scoring, with the raw scrape saved separately so projections can be rebuilt without re-scraping.
  - **success:** `data/projections.rds` exists as a list matching the schema in `rds-contracts.md`, one row per player, required fields validated, duplicate `player_id` rejected; `data/raw_scrape.rds` holds the raw scrape result.

- **CAP-2 — Synthetic projection fixture**
  - **intent:** Core development and the test suite run against a synthetic projection snapshot instead of live scrapers.
  - **success:** `make test` passes using only the synthetic fixture, with no network access; the fixture satisfies the same `projections.rds` schema as a real snapshot.

- **CAP-3 — Snake schedule generation**
  - **intent:** System generates the complete pick order for a 12-team, 15-round snake draft, where the round count is the sum of all roster slots.
  - **success:** the schedule has 180 picks and reverses correctly at each round boundary (pick 13 belongs to team 12, pick 24 to team 1).

- **CAP-4 — Draft state creation, persistence, and recovery**
  - **intent:** User creates a new draft or resumes an existing one; every accepted pick is persisted atomically with a backup of the prior state.
  - **success:** after recording picks, terminating the process, and reloading, all picks are preserved in order; a `state/draft.rds.bak` backup of the previous state exists.

- **CAP-5 — Derived draft views**
  - **intent:** System derives the current pick, team on the clock, all rosters, available players, the best current lineup, and the user's next pick from the ordered picks alone.
  - **success:** for any pick state the current overall pick equals `nrow(picks) + 1` and the team on the clock matches the generated schedule; no derived field is written to `state/draft.rds`.

- **CAP-6 — Pick validation and undo**
  - **intent:** User records a pick by player or undoes the most recent pick.
  - **success:** a player cannot be drafted twice; an unknown `player_id` is rejected; total picks cannot exceed teams × rounds; undo removes only the last pick and returns that player to availability.

- **CAP-7 — Operational terminal draft loop**
  - **intent:** User conducts an entire draft through an interactive terminal loop with player-name resolution and the full command set, with recommendations shown automatically on the user's turn.
  - **success:** a reduced full rehearsal completes every pick with at least one stop and resume; `/rec`, `/board`, `/board <pos>`, `/team`, `/teams`, `/undo`, `/status`, `/save`, `/quit` all work; player entry resolves exact, substring, prefix, and fuzzy matches with a numbered disambiguation list.

- **CAP-8 — Roster-aware recommendation foundation**
  - **intent:** On the user's pick the system ranks available players by roster marginal value, VOR, and positional tier, applies feasibility guardrails, and attaches a deterministic label and a rule-generated explanation.
  - **success:** recommendations never contain drafted players and never contain a player whose selection would make a mandatory roster slot impossible; identical snapshot + config + pick state yields an identical order; K/DST are excluded before the final rounds unless mandatory; explanations are produced by rules, never an LLM.

- **CAP-9 — Market-aware wait intelligence**
  - **intent:** Recommendations incorporate the probability a player survives to the user's next pick, the expected best alternative at that pick, wait cost, tier cliff, and ADP value, combined through configurable weights into a final score.
  - **success:** `p_next` is computed analytically as a conditional survival probability bounded to `[0, 1]` with no live Monte Carlo; the four-component score reproduces deterministically; the focused algorithm tests in `operations.md` pass.

- **CAP-10 — Mock simulator and calibration**
  - **intent:** User runs complete seeded mock drafts with ADP-driven opponents, compares the `adp`, `vor`, and `warroom` strategies on the documented metrics, and calibrates recommendation weights over a small transparent grid.
  - **success:** every simulated draft completes with valid 14-player rosters filling all mandatory positions; `make simulate` runs a repeatable reduced suite; the strategy comparison reports the metric set in `operations.md`; seeds make runs reproducible.

- **CAP-11 — Thin Shiny War Room**
  - **intent:** User conducts the same draft through a single-page Shiny interface that calls the same core functions and RDS files as the terminal.
  - **success:** terminal and Shiny produce the same recommendation order from the same state and snapshot; no formula or business rule is duplicated in Shiny reactives; recommendation refresh completes well under one second (target ~300 ms on the dev machine); the live path makes no network calls.

## Constraints

- R is the only application language; runtime data and persistence use RDS only.
- `ffanalytics` may be called only by `scripts/prepare.R`, never while a live draft runs; the live path (`R/` core, `scripts/draft.R`, `app.R`) makes no network calls.
- Business rules live in plain functions under `R/` and must not depend on Shiny; `scripts/` and `app.R` are adapters over the same functional core, with no duplicated formulas.
- Persist only the ordered picks (`overall`, `player_id`, `entered_at`); current pick, rosters, availability, lineup, and recommendations are always derived, never persisted. The next overall pick is always `nrow(picks) + 1`.
- `data/projections.rds` is immutable for the duration of a draft.
- State saves are atomic: write a temp file, keep a backup of the previous state, rename into place; every accepted pick saves immediately.
- No SQLite or other database, event sourcing, R6, golem, targets, Docker, API, authentication, background workers, or dependency-injection framework.
- No live Monte Carlo in the recommendation path; wait-cost math is analytic and deterministic. The same snapshot + config + pick state must yield the same recommendation order.
- Dependencies are minimal and pinned with `renv`, including a pinned version or commit of `ffanalytics`.
- The terminal draft and simulator are complete and working before any Shiny work begins.
- Only the initial league format is fully validated this epic: 12 teams, roster QB 1 / RB 2 / WR 2 / TE 1 / FLEX 1 (RB or WR) / K 1 / DST 1, bench 6, Full PPR. The round count is not configured — it is derived as the sum of all roster slots (9 starters + 6 bench = 15 rounds, 180 picks), so bench depth and round count cannot disagree. Draft order is entered immediately before the draft; user team and slot configurable in `config.R`.
- The league format (team count, roster slots, bench, flex positions) lives in `config/league.yml` and is read by the functional core on the live draft path; `config.R` no longer holds it. This is the one place the live path parses YAML.
- The core engine and its first Shiny shell are implemented as stories 1–8 in the fixed order defined in `operations.md`. A follow-on UI/UX increment — stories 9–25, distilled from `docs/design/backlog-adaptacao-shiny.md` (in turn from `docs/design/DESIGN.md`, `EXPERIENCE.md`, and `mockups/live-war-room.html`) — refines CAP-11's Shiny surface and adds no capability. No story implements work belonging to a later story. Human checkpoints are required for stories 1, 3, 5, 6, 8, and for the follow-on stories that establish a layout, interaction, or contract pattern (14, 19, 22, 23, 24, 25).
- Recommendation guardrails (full detail in `recommendation-algorithm.md`): no K/DST before the final rounds unless mandatory; penalize QB2 strongly and TE2 while starters or FLEX remain open; preserve greater bench option value for RB/WR; when remaining picks equal remaining mandatory slots, only feasibility-preserving positions are eligible.
- Explanations and labels are generated by deterministic rules, never an LLM call.
- `ffanalytics` floor / ceiling / standard deviation are interpreted as dispersion across projection sources (`source_low` / `source_high` / `source_sd`), not a full probabilistic season model, and carry small weight.

## Non-goals

- Multi-user collaboration; cloud deployment; multiple simultaneous drafts.
- Automatic synchronization with a fantasy platform; live injury/news ingestion; live projection scraping during a draft.
- Universal scoring or roster-rule support for arbitrary league formats.
- Historical-season outcome backtesting.
- Machine-learned or genetic recommendation optimization.
- Mobile-first design; a polished public product.
- Persisting an undo/correction event log, or correcting an arbitrary earlier pick (not only the most recent): both stay blocked by the persist-only-ordered-picks and no-event-sourcing constraints, and are out of scope until a separate owner decision reconciles them. They are described in `docs/design/backlog-adaptacao-shiny.md` (Tier D5, D6) but are deliberately absent from the story breakdown.

## Success signal

One person can generate or load a projection snapshot, configure the 12-team draft order, conduct all 180 picks in the terminal — stopping and resuming safely — and receive fast, deterministic, explainable recommendations on every personal pick. The same person can run seeded mock drafts comparing the ADP, VOR, and War Room strategies, and then conduct the same draft through a single-page Shiny interface that returns the same recommendations, in the same order, as the terminal core reading the same RDS state.

## Assumptions

- The synthetic fixture must satisfy the same `projections.rds` schema as a real snapshot so that core code and tests are identical across both, inferred from the intent's requirement that the runtime work with a synthetic fixture.
