## config.R -- static configuration for the Draft War Room.
## Values only, no business logic. Sourced by adapters (scripts/, tests/, app.R).
## Business rules live in R/*.R and never here.

## League format -- the only fully validated configuration this epic.
league <- list(
  teams  = 12L,
  rounds = 14L,
  roster = c(QB = 1L, RB = 2L, WR = 2L, TE = 1L, FLEX = 1L, K = 1L, DST = 1L, BENCH = 6L),
  flex_positions = c("RB", "WR")
)

## Projection snapshot parameters (see rds-contracts.md / preparation-pipeline.md).
season <- 2026L
method <- "robust"
vor_baseline <- c(QB = 13, RB = 35, WR = 36, TE = 13, K = 13, DST = 13)

## Full-PPR league scoring. The league differs from the scrape package's default
## rules in only a handful of categories, so the overrides live in a YAML file
## (already in the scrape package's scoring-list shape) that only
## scripts/prepare.R reads. prepare.R merges it over the base rules with
## warroom_scoring() and stamps the result into data/projections.rds. This path
## is the single source; there is no inline scoring list (story 1's literal used
## keys that do not exist in the real scrape API).

## Placeholders until the draft order is entered immediately before the draft
## (story 3 onward). Kept here so config.R already carries every knob.
user_team <- "Team 01"
user_slot <- 1L

## Seed carried into every new draft state by new_draft() (story 3) and reused by
## the story 7 mock simulator for reproducible runs and deterministic tie-breaks.
## Pure value, no logic.
seed <- 1L

## Filesystem layout. data/*.rds and state/*.rds are gitignored and rebuilt.
paths <- list(
  data        = "data",
  state       = "state",
  projections = file.path("data", "projections.rds"),
  raw_scrape  = file.path("data", "raw_scrape.rds"),
  draft_state = file.path("state", "draft.rds"),
  scoring     = file.path("config", "score_settings.yml")
)
