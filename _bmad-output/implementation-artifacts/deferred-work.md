# Deferred work

Issues surfaced during review but intentionally not fixed in the story that found them.

- source_spec: `_bmad-output/specs/spec-fantasy-warroom/stories/1-walking-skeleton-and-synthetic-snapshot.md`
  summary: `validate_projections()` is a thin schema gate — it checks list-key presence, the four required `players` fields, the `pos` enum and `player_id` uniqueness, but does not type-check `season` / `method` / `vor_baseline` / `scoring`, does not assert the full normalized `players` column set (`nfl_team`, `source_sd/low/high`, `vor/low_vor/high_vor`, `overall_rank`, `pos_rank`, `tier`, `adp`, `adp_sd`), and does no numeric or ordering sanity (`adp > 0`, `overall_rank` a `1:n` permutation, `source_low <= points <= source_high`).
  evidence: Story 1 deliberately scoped validation to the minimum in the frozen spec. A real scraped snapshot in story 2 could pass `load_projections()` with missing or garbage fields that stories 5-7 then consume as `NULL`. Strengthen the gate when the real preparation pipeline lands.

- source_spec: `_bmad-output/specs/spec-fantasy-warroom/stories/1-walking-skeleton-and-synthetic-snapshot.md`
  summary: There is no public config accessor. `config.R` is reachable only through the private, CWD-dependent `.warroom_load_config()` helper in `R/projections.R`; `load_core()` sources `R/*.R` but never exposes `league` / `scoring` / `vor_baseline`. `build_synthetic_projections()` reads `config.R` from disk on every call, so it is not pure.
  evidence: Story 1 has no adapters yet, so the gap is invisible now. Story 3 is the first adapter (`scripts/`) and every adapter from 3 onward needs config — it should introduce a public `load_config()` and make `build_synthetic_projections()` take a config object as a defaulted argument.

- source_spec: `_bmad-output/specs/spec-fantasy-warroom/stories/1-walking-skeleton-and-synthetic-snapshot.md`
  summary: `make test` builds the runtime artifact `data/projections.rds` as a side effect of `tests/smoke.R`. Once story 2's `scripts/prepare.R` writes a real snapshot, `make test` still rebuilds the synthetic fixture on top of it (a `.bak` copy is now taken first, but the real snapshot is still displaced).
  evidence: CAP-2 calls for a "separate builder". Consider a dedicated fixture path, or a synthetic-vs-real marker in the snapshot, so the smoke test never competes with a real projection snapshot.

- source_spec: `_bmad-output/specs/spec-fantasy-warroom/stories/1-walking-skeleton-and-synthetic-snapshot.md`
  summary: The roster in `rds-contracts.md` (`QB=1, RB=2, WR=2, TE=1, FLEX=1, K=1, DST=1, BENCH=6`) is 9 starters + 6 bench = 15 roster slots, but 12 teams x 14 rounds gives 14 picks per team.
  evidence: `BENCH` is most likely meant to be 5. This is an upstream companion-contract discrepancy, not a code bug — it needs a spec update (`bmad-spec`), and stories 3+ (draft state, roster feasibility) will be built on the wrong number until it is resolved.

- source_spec: `_bmad-output/specs/spec-fantasy-warroom/stories/1-walking-skeleton-and-synthetic-snapshot.md`
  summary: The synthetic fixture's `adp` is a near-monotone function of projection rank (`adp = overall_rank + smooth wobble`), so market price and player value barely diverge.
  evidence: Story 6 (`p_next`, ADP surplus, reach count) and the story 7 simulator's ADP-surplus / reach metrics only carry signal when the market disagrees with value. Inject a deterministic position- or id-based divergence into the fixture's `adp` before those stories rely on it.

- source_spec: `_bmad-output/specs/spec-fantasy-warroom/stories/1-walking-skeleton-and-synthetic-snapshot.md`
  summary: `nfl_team` codes in the fixture (`LV`, `LAC`, `LAR`, `WAS`, `JAX`) are unconstrained and `validate_projections()` places no constraint on the column; `ffanalytics` / nflverse often emit `LA`, `WSH`, `JAC`.
  evidence: If any later story joins on or displays `nfl_team`, define a canonical team-code list and validate against it, and align the fixture with whatever `scripts/prepare.R` produces in story 2.

- source_spec: `_bmad-output/specs/spec-fantasy-warroom/stories/2-ffanalytics-projection-adapter.md`
  summary: `make test`'s offline guarantee now depends on `renv` being pre-installed. The new `.Rprofile` sources `renv/activate.R` on every `Rscript` call, and from a clean checkout / CI cache-miss that autoloader bootstraps `renv` over the network before `tests/smoke.R` runs.
  evidence: Verified `make test` runs offline on this machine only because `renv` 1.2.3 is already installed. A fully hermetic test path (or a documented "renv must be preinstalled" precondition plus a CI renv cache) is follow-up work.

- source_spec: `_bmad-output/specs/spec-fantasy-warroom/stories/2-ffanalytics-projection-adapter.md`
  summary: No check pins the real `ffanalytics` projection-table contract (exact column names, `pos` label domain). `make test` exercises `normalize_projections()` only against a hand-built `mk_proj_table()` that encodes the author's assumptions, so an API drift within the pinned `ffanalytics` version is invisible until `make prepare` is run with network.
  evidence: The pinned commit and a successful live `make prepare` this session cover the current risk, but a regression would only surface right before the draft. A separate, non-`make test` check that runs one `scrape_data()` (or reads a committed `raw_scrape` fixture) and asserts `names(projections_table(...))` and `all(unique(pos) %in% valid_pos)` would close the gap.

- source_spec: `_bmad-output/specs/spec-fantasy-warroom/stories/2-ffanalytics-projection-adapter.md`
  summary: `scripts/prepare.R` silently overwrites `data/projections.rds` on every run. The snapshot must be immutable for the duration of a draft, but there is no guard against a mid-draft re-prepare replacing it.
  evidence: Compounds the existing story-1 deferred item about `make test` displacing a real snapshot. Add an explicit guard (refuse unless the file is absent or `--force` is passed).

- source_spec: `_bmad-output/specs/spec-fantasy-warroom/stories/2-ffanalytics-projection-adapter.md`
  summary: `scripts/prepare.R` loads `config.R` via its own `sys.source` into a private env with a different required-key set than `.warroom_load_config()` in `R/projections.R`. Two divergent config loaders for the same file.
  evidence: Compounds the story-1 deferred item calling for a single public `load_config()`. Fold `prepare.R` onto it when story 3 introduces the accessor.

- source_spec: `_bmad-output/specs/spec-fantasy-warroom/stories/3-snake-schedule-draft-state-and-rds-persistence.md`
  summary: Nothing binds a draft to its projection snapshot at pick time. `record_pick()` and `derive_draft_view()` accept any `snapshot` argument without checking `snapshot$created_at == state$projection_created_at`, so picks can be recorded and views derived against the wrong snapshot with no error.
  evidence: `rds-contracts.md` says the state is "bound to" one snapshot via `projection_created_at`, but the binding is currently write-only metadata. Story 4 (resume behavior) is the natural place to enforce it — on resume, load the snapshot and assert the timestamp matches before entering the loop.

- source_spec: `_bmad-output/specs/spec-fantasy-warroom/stories/4-operational-terminal-draft.md`
  summary: Story 4's resume path does not enforce the draft-to-snapshot binding. `run_draft()` calls `load_state()` then `load_projections()` and enters the loop without asserting `snapshot$created_at == state$projection_created_at`, so resuming a draft against a rebuilt snapshot is silently allowed.
  evidence: Carries forward the story-3 deferred item that nominated story 4 as the enforcement point; the approved story-4 spec did not include it, so it was intentionally left for a focused follow-up. The check is one comparison at the top of `run_draft()` after both files are loaded.

- source_spec: `_bmad-output/specs/spec-fantasy-warroom/stories/4-operational-terminal-draft.md`
  summary: New-draft team-order entry commits immediately with no echo or confirmation step. A mistyped team name cannot be corrected from inside the loop (`/undo` only touches picks) — the user must delete `state/draft.rds` by hand.
  evidence: Adversarial review finding. The frozen spec says "chamar new_draft e save_state na hora", so a confirm step is a deliberate scope decision to revisit; Shiny (story 8) enters the draft order through a different flow anyway.

- source_spec: `_bmad-output/specs/spec-fantasy-warroom/stories/4-operational-terminal-draft.md`
  summary: The live `recommend_players` rendering branch in `scripts/draft.R` is untested and guesses at story-5 output columns. Column names were aligned to `recommendation-algorithm.md`, but the row formatting (`paste(format(recs[i, show]), collapse = "  ")`) is crude and unverified.
  evidence: Story 5 owns the `recommend_players` contract and should replace this stand-in renderer with a proper one plus a terminal-output test, per its own spec.

- source_spec: `_bmad-output/specs/spec-fantasy-warroom/stories/4-operational-terminal-draft.md`
  summary: `.warroom_print_board` hardcodes a 15-row cap with no way for the user to ask for more, even though `available_board()` already accepts an `n` argument. `/board <n>` or `/board <pos> <n>` would be a natural extension.
  evidence: Adversarial review finding; minor usability gap, out of scope for the required command set.

- source_spec: `_bmad-output/specs/spec-fantasy-warroom/stories/5-roster-aware-recommendation-foundation.md`
  summary: `recommend_players()` takes ~130 ms per call on the dev machine (20-call benchmark, ~60-pick mid-draft state). It recomputes `.warroom_best_lineup` — which re-runs `.warroom_slot_counts` and re-sorts the whole roster by position — once per eligible candidate (~180×), and `.warroom_tier_cliff` re-filters the full `available` table per candidate.
  evidence: Comfortably under the terminal need, but CAP-11 / story 8 targets ~300 ms for the Shiny recommendation refresh and this is already ~40% of that budget before any UI overhead. A focused pass before or during story 8 should hoist the per-position sorted base lineup out of the candidate loop and pre-group `available` by position once.

- source_spec: `_bmad-output/specs/spec-fantasy-warroom/stories/6-market-aware-wait-intelligence.md`
  summary: `.warroom_following_user_pick()` in `R/recommendation.R` re-derives the snake schedule and the user's slot the same way `next_user_pick()` in `R/core.R` does, differing only by a strict `>` instead of `>=`; the two should be one function parametrized by the comparison / starting overall.
  evidence: The story-6 frozen spec explicitly directed an internal helper and forbade touching `next_user_pick()`, so the duplication was accepted for this story. `make_snake_schedule()` (the real shared rule) is not duplicated, but AGENTS.md calls for no repeated core logic; consolidate when `next_user_pick()` can be renegotiated.

- source_spec: `_bmad-output/specs/spec-fantasy-warroom/stories/6-market-aware-wait-intelligence.md`
  summary: `.warroom_norm01()` returns all zeros when its input has a degenerate range, so a `wait_cost` vector with exactly one finite value (a single candidate at a drying position, the rest `NA`) contributes nothing to `decision_score` — the wait signal is silently dropped in exactly the scenario it matters most.
  evidence: `.warroom_norm01` is unchanged story-5 code; story 6 introduces the mostly-`NA` `wait_cost` vector that exposes it. The story-6 spec relies on `.warroom_norm01` as-is ("sem renormalizar"). A fix (treat a lone finite value as its own max, or fall back to an absolute scale) belongs in a focused pass on the normalization helper.

- source_spec: `_bmad-output/specs/spec-fantasy-warroom/stories/6-market-aware-wait-intelligence.md`
  summary: `expected_best_next(pos)` values each surviving alternative with `.warroom_roster_value_of()` against the user's **pre-pick** `base_lineup`; after the user actually drafts at the current pick the roster changes, so the marginal value of next-pick alternatives is computed against a stale roster, biasing `wait_cost` for positions the user is about to fill.
  evidence: The story-6 spec fixes the survivor scale as "contra o base_lineup do usuário" for determinism and simplicity. Whether alternatives should be valued against `roster + candidate` is a modeling question for calibration (story 7) once mock drafts can measure the effect.

- source_spec: `_bmad-output/specs/spec-fantasy-warroom/stories/6-market-aware-wait-intelligence.md`
  summary: `decision_score` uses the raw weights with no renormalization, so its reachable maximum is ~100 only when all four normalized terms are non-zero; whenever `wait_cost` degrades to `NA` (no `adp` column, no following pick, late draft) the ceiling drops to ~70 while the absolute label thresholds (`.warroom_take_now_score = 60`, `.warroom_best_value_adp`, etc.) stay fixed, making `TAKE NOW` / `BEST VALUE` materially harder to reach. Same effect for any user-supplied `weights` not summing to 1.
  evidence: Pre-existing from story 5's 3-term raw-weight score; story 6 widens the gap between the full and degraded ceilings. Either renormalize the active weights or derive the thresholds from the achievable maximum; both are calibration concerns for story 7.

- source_spec: `_bmad-output/specs/spec-fantasy-warroom/stories/6-market-aware-wait-intelligence.md`
  summary: `recommend_players()` never checks that `state`'s user is actually on the clock. Called off-turn (e.g. `/rec` during an opponent's pick), `adp_value` and the `p_next` conditional denominator are computed against the opponent's `current_overall` while `following_pick` is the user's next real pick — a silently incoherent recommendation.
  evidence: Pre-existing since story 5 (`adp_value` already used `current_overall`); story 6's `p_next` denominator compounds it. `scripts/draft.R` only auto-shows on the user's turn, but `/rec` is reachable anytime. A one-line guard (or an explicit "assuming your pick" note) closes it.

- source_spec: `_bmad-output/specs/spec-fantasy-warroom/stories/6-market-aware-wait-intelligence.md`
  summary: The `adp_sd` fallback in `.warroom_pick_sd()` (`.warroom_adp_sd_frac * adp`, used when the snapshot has `adp` but no `adp_sd` column) has no test — every story-6 test uses the synthetic fixture, which always carries `adp_sd`, or drops `adp`/`adp_sd` together.
  evidence: `normalize_projections()` drops `adp` and `adp_sd` as a pair, so the fallback only fires for a hand-built or partial snapshot. Low risk, but the branch is uncovered; add a targeted assertion when the real preparation pipeline's ADP handling is revisited.

- source_spec: `_bmad-output/specs/spec-fantasy-warroom/stories/7-mock-simulator-and-calibration.md`
  summary: `.warroom_sim_starter_ids()` in `R/simulation.R` mirrors `.warroom_best_lineup()`'s starter selection, but its flex-pool logic diverges from `.warroom_best_lineup()`'s for a hypothetical league that puts `TE` (or `K`/`DST`) in `flex_positions` — `.warroom_best_lineup()`'s flex pool only excludes already-used RB/WR starters (its `start_k` ternary is `0L` for any other position), while `.warroom_sim_starter_ids()` excludes every already-used starter regardless of position, so the two would disagree on who "starts."
  evidence: The initial league's `flex_positions` is fixed to `c("RB","WR")` in `config.R`, and SPEC.md's Constraints state "only the initial league format is fully validated this epic," so the divergent case is currently unreachable. Revisit if a future league format ever varies `flex_positions`.

- source_spec: `_bmad-output/specs/spec-fantasy-warroom/stories/7-mock-simulator-and-calibration.md`
  summary: `scripts/simulate.R --calibrate` has no automated end-to-end test of its own CLI wiring (exit code, output) — only `calibrate_weights()` itself is unit-tested via `tests/smoke.R`.
  evidence: Running the full default weight grid (20 rows x default seeds x slots) inside `make test` would violate story 7's explicit "calibration is heavier, run only on explicit request, not part of the reduced dev suite" design. Closing this would need `scripts/simulate.R` to accept a way to shrink the grid/seeds for a fast test run.

- source_spec: `_bmad-output/specs/spec-fantasy-warroom/stories/7-mock-simulator-and-calibration.md`
  summary: `expect_error()` in `tests/smoke.R` (defined in story 1) never asserts the actual error message text — its `label` argument is purely descriptive, used only in the failure path when no error was raised at all — so every `expect_error(...)` call across the suite (including story 7's `opponent_pick()` check) gives false confidence that a *specific* error string is being verified.
  evidence: This is a repo-wide test-helper limitation from story 1, not something story 7 introduced; surfaced incidentally while reviewing story 7's use of the same helper. Strengthening it (compare `conditionMessage()` against a pattern) would touch every story's tests, so it needs a dedicated pass.

- source_spec: `_bmad-output/specs/spec-fantasy-warroom/stories/7-mock-simulator-and-calibration.md`
  summary: `.warroom_sim_metrics()` in `R/simulation.R` recomputes the pick-to-team-slot mapping (`make_snake_schedule()` + `match()` + `schedule$slot[state$picks$overall]`) instead of reusing the equivalent mapping `derive_draft_view()` already builds internally to construct `rosters` — because that mapping isn't exposed in `derive_draft_view()`'s return value.
  evidence: Same class of tension as the story-6 deferred item about `.warroom_following_user_pick()` duplicating `next_user_pick()`'s pattern instead of sharing it, since `R/core.R` is frozen this story (`derive_draft_view()` cannot be changed without human approval). Consider exposing the pick-slot mapping from `core.R` to remove both duplications together in a focused pass.

- source_spec: `_bmad-output/specs/spec-fantasy-warroom/stories/7-mock-simulator-and-calibration.md`
  summary: `calibrate_weights()`'s grid x seed x slot loop (`R/simulation.R`) has no per-run failure isolation — a single `simulate_draft()` error on any one run aborts the entire (potentially multi-minute) calibration sweep with no partial results.
  evidence: Low likelihood given `recommend_players()`'s own feasibility guardrails make a mid-draft failure very unlikely under any valid league/team_order, and per-run isolation was out of scope for this story's spec ("a plain double loop"). Worth hardening if calibration grids/seed counts grow larger in practice.

- source_spec: `_bmad-output/specs/spec-fantasy-warroom/stories/8-thin-shiny-war-room.md`
  summary: `app.R` has no guard against two concurrent Shiny sessions (e.g. two browser tabs) pointing at the same `state/draft.rds` — each session loads its own `init_state` independently and `commit_state()`/`save_state()` is last-write-wins, so a pick made in one session can be silently overwritten by a stale save from the other.
  evidence: SPEC.md's Non-goals rule out multi-user collaboration, but two tabs of the *same* single user during a live draft is a narrower, plausible slip (e.g. the operator opens a second tab after a browser refresh) that the frozen story-8 spec did not address. A session-start freshness check (compare `state_path`'s mtime or the loaded picks count before each `commit_state()` write) would close it.

- source_spec: `_bmad-output/specs/spec-fantasy-warroom/stories/8-thin-shiny-war-room.md`
  summary: `app.R`'s `draft_btn`/`undo_btn` error handlers report both a `record_pick()`/`undo_pick()` validation rejection and a `save_state()` I/O failure under the same generic message prefix (`"pick rejeitado: ..."` / `"nada a desfazer: ..."`), so a live-draft operator cannot tell "that pick is invalid" apart from "the state file failed to save" from the notification alone.
  evidence: Review finding (verification-gap layer) during story 8's review. Not required by the frozen spec's I/O matrix, but worth a follow-up distinguishing the two failure modes (e.g. prefix I/O failures with a distinct "FALHA AO SALVAR" label, matching the terminal's own `safe_save()` wording in `scripts/draft.R`).

- source_spec: `_bmad-output/implementation-artifacts/spec-wave1-15-round-and-draft-day-guards.md`
  summary: `scripts/prepare.R --force` (bypass the immutability guard and rebuild `data/projections.rds`) and its `.bak` retention have no automated test. `tests/smoke.R` only exercises the no-`--force` refusal via a fast subprocess; the `--force` branch, the pre-rebuild `.bak` copy, and the atomic `.tmp`+rename write are uncovered.
  evidence: Review finding (verification-gap + blind-hunter, wave 1). The `.bak` copy now happens at the guard (before any scrape), so a `--force` subprocess is closer to testable, but it still loads the `ffanalytics` namespace for `projections_table()` (~30-50s) even when it reuses the committed `data/raw_scrape.rds`, which is too slow for the offline smoke suite. A targeted check (sentinel `projections.rds` -> `Rscript scripts/prepare.R --force` -> assert the sentinel now lives in `data/projections.rds.bak`) would close it if the runtime cost is accepted.

- source_spec: `_bmad-output/implementation-artifacts/spec-wave1-15-round-and-draft-day-guards.md`
  summary: `.warroom_validate_state()` now hard-rejects any `state/draft.rds` whose `league$rounds` is not `sum(roster)`, which is true of every state file written before wave 1 (they carry the old `rounds = 14` while the roster summed to 15). There is no migration and `schema_version` stayed `1L`.
  evidence: Review finding (blind-hunter + verification-gap, wave 1). Accepted for now: the real draft has not started, `state/*.rds` is a gitignored per-machine derived artifact, and the stale story-8 dev state file was deleted. If a pre-wave-1 draft ever needed to resume, it would need a one-off `league$rounds <- sum(league$roster)` fixup or a `schema_version` bump with a migration.

- source_spec: `_bmad-output/specs/spec-fantasy-warroom/stories/9-dark-terminal-shell.md`
  summary: `www/styles.css` colors the off-turn recommendation note ("Você não está na vez...") with `--danger` (`#FF6B6B`), preserving the pre-story-9 inline `#b00`. `DESIGN.md` reserves `danger` for "falha, conflito ou ação inválida" and assigns `warning` to "estado que pede conferência" — an off-turn note is the latter.
  evidence: Review finding (blind-hunter, story 9). Story 9 (A1) is a faithful visual port, so re-adjudicating each component's color role was out of scope; the story-9 spec's Tasks explicitly named `danger` for `.recs-note`. Story 13 (A5, "Microcopy and feedback pass" over `EXPERIENCE.md` Voice/Tone + State Patterns) is the natural place to move it to `--warning`.

- source_spec: `_bmad-output/specs/spec-fantasy-warroom/stories/10-fixed-status-strip.md`
  summary: The snake schedule + `slot`->`team_order` + `snapshot$players` join is now derived inline in three places on the live render path — `output$status_strip`, `output$recent_picks_table`, and (for rosters) `derive_draft_view()` — so `make_snake_schedule()` is rebuilt several times per reactive flush. AGENTS.md discourages duplicated derivation in adapters.
  evidence: Story 10 only added the third copy and its frozen scope forbids touching the other `render*` functions. A `server()`-scope `schedule <- reactive(make_snake_schedule(...))` plus a small shared "pick -> team/player" helper (or exposing the schedule on `derive_draft_view()`) would remove the duplication; do it in a story that already owns those render functions (e.g. story 15 board grid, or story 18 audit panel).

- source_spec: `_bmad-output/specs/spec-fantasy-warroom/stories/10-fixed-status-strip.md`
  summary: `scroll-padding-top` on the scroll container is a static `96px` approximation of the sticky status strip's real height, which is dynamic (the flex row wraps in a narrow docked window, plus the last-pick and saved lines). When the strip is taller than 96px a Tab focus target can still land hidden behind it.
  evidence: EXPERIENCE.md Accessibility Floor wants focus visible "inclusive abaixo da faixa fixa". A robust fix needs the strip's measured height (a ResizeObserver writing a CSS custom property, or a layout that reserves space), which conflicts with story 10's "no custom JavaScript" boundary. Revisit with the keyboard/a11y stories (19, 21) or the layout story (14).

- source_spec: `_bmad-output/specs/spec-fantasy-warroom/stories/11-candidate-smart-list.md`
  summary: `app.R` now has two position filters on the same screen with different sentinel strings and languages — the available-board filter (`selectInput("pos_filter", ...)`, story 8) uses `"ALL"` (English), the new recommendations filter (`radioButtons("recs_pos_filter", ...)`, story 11) uses `"Todos"` (Portuguese). The rest of the recs UI is Portuguese.
  evidence: Review finding (blind-hunter, story 11). Story 11's frozen spec fixes `selected = "Todos"` for the new control, and harmonizing the older `pos_filter` would touch story-8 code and its `(8e)` smoke assertions (`session$setInputs(pos_filter = "QB")`), which is out of scope here. Align both on one sentinel/language in a story that already owns the available-board rendering (e.g. story 14 panel-grid layout) or a dedicated microcopy pass (story 13, A5).
