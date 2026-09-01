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

## Full-PPR league scoring. Story 1 keeps this as literal values and it is the
## single source for both config and the synthetic fixture. Story 2 replaces it
## with the scraper's complete rules plus league overrides, same RDS contract.
scoring <- list(
  pass = list(pass_yds = 0.04, pass_tds = 4, pass_int = -2, pass_2pt = 2),
  rush = list(rush_yds = 0.1, rush_tds = 6, rush_2pt = 2),
  rec  = list(rec = 1, rec_yds = 0.1, rec_tds = 6, rec_2pt = 2),
  misc = list(fumbles_lost = -2, fumbles_rec_td = 6),
  kick = list(xp = 1, fg_0019 = 3, fg_2029 = 3, fg_3039 = 3,
              fg_4049 = 4, fg_50 = 5, fg_miss = -1),
  dst  = list(dst_sack = 1, dst_int = 2, dst_fum_rec = 2, dst_td = 6, dst_safety = 2,
              dst_blk = 2, dst_ret_td = 6,
              dst_pa_0 = 10, dst_pa_1_6 = 7, dst_pa_7_13 = 4, dst_pa_14_20 = 1,
              dst_pa_21_27 = 0, dst_pa_28_34 = -1, dst_pa_35 = -4)
)

## Placeholders until the draft order is entered immediately before the draft
## (story 3 onward). Kept here so config.R already carries every knob.
user_team <- "Team 01"
user_slot <- 1L

## Filesystem layout. data/*.rds and state/*.rds are gitignored and rebuilt.
paths <- list(
  data        = "data",
  state       = "state",
  projections = file.path("data", "projections.rds"),
  raw_scrape  = file.path("data", "raw_scrape.rds"),
  draft_state = file.path("state", "draft.rds")
)
