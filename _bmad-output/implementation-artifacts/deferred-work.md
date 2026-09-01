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
