#!/usr/bin/env Rscript
## tests/smoke.R -- offline walking-skeleton smoke test (CAP-2).
##
## Rebuilds the synthetic projection fixture, writes data/projections.rds, and
## validates the data/projections.rds runtime contract from rds-contracts.md.
## No network, no scrapers. Exits 0 on success, 1 on any failed assertion.
## Orchestration only -- every rule lives in R/projections.R.

source("R/load_core.R")
load_core()

## config.R values, loaded once, reused for cross-checks below.
cfg <- .warroom_load_config()

fail <- function(...) {
  message("SMOKE FAIL: ", ...)
  quit(status = 1L, save = "no")
}

## Run expr, require that it raises an error, return the error message.
expect_error <- function(expr, label) {
  msg <- tryCatch({ force(expr); NULL }, error = function(e) conditionMessage(e))
  if (is.null(msg)) fail(label, ": expected an error, got none")
  invisible(msg)
}

## Run expr, require that it signals a warning; return value + warning message.
expect_warning <- function(expr, label) {
  w <- NULL
  val <- withCallingHandlers(
    force(expr),
    warning = function(cond) {
      w <<- conditionMessage(cond)
      invokeRestart("muffleWarning")
    }
  )
  if (is.null(w)) fail(label, ": expected a warning, got none")
  list(value = val, message = w)
}

## --- Build the fixture (I/O matrix: "Build da fixture") --------------------
snap <- build_synthetic_projections()

if (!all(.warroom_projection_keys %in% names(snap))) {
  fail("fixture missing contract keys: ",
       paste(setdiff(.warroom_projection_keys, names(snap)), collapse = ", "))
}
if (!identical(snap$schema_version, 1L))  fail("schema_version is not 1L")
if (!inherits(snap$created_at, "POSIXct")) fail("created_at is not POSIXct")
if (!is.numeric(snap$season) || snap$season %% 1 != 0) fail("season is not an integer")
if (!identical(snap$method, "robust"))    fail("method is not 'robust'")

expected_baseline <- cfg$vor_baseline
if (!identical(snap$vor_baseline[names(expected_baseline)], expected_baseline)) {
  fail("snapshot vor_baseline does not match config.R")
}

players <- snap$players
n <- nrow(players)
if (n < 200L) fail("fixture has ", n, " players, need >= 200")
if (anyDuplicated(players$player_id)) fail("duplicate player_id in the fixture")

pos_tab <- table(factor(players$pos, levels = c("QB", "RB", "WR", "TE", "K", "DST")))
if (any(pos_tab == 0L)) {
  fail("fixture missing position(s): ",
       paste(names(pos_tab)[pos_tab == 0L], collapse = ", "))
}

## --- Determinism (I/O matrix: identical between executions) ----------------
snap2 <- build_synthetic_projections()
if (!identical(snap$players, snap2$players)) fail("two fixture builds produced different tables")

## --- Persist + reload (I/O matrix: "Grava snapshot", "Validacao OK") ------
dir.create("data", showWarnings = FALSE, recursive = TRUE)
snapshot_path <- file.path("data", "projections.rds")
if (file.exists(snapshot_path)) {
  invisible(file.copy(snapshot_path, paste0(snapshot_path, ".bak"), overwrite = TRUE))
}
saveRDS(snap, snapshot_path)

loaded <- load_projections(snapshot_path)
if (!identical(loaded$players, snap$players)) fail("reloaded snapshot differs from the built one")
if (!isTRUE(validate_projections(loaded)))    fail("validate_projections did not return TRUE")

## --- Negative cases -------------------------------------------------------
## Duplicate player_id -> error citing the id.
dup <- snap
dup$players$player_id[2] <- dup$players$player_id[1]
msg <- expect_error(validate_projections(dup), "duplicate player_id")
if (!grepl(dup$players$player_id[1], msg, fixed = TRUE)) {
  fail("duplicate-id error does not name the id: ", msg)
}

## Required field absent -> error naming the field.
no_pos <- snap
no_pos$players$pos <- NULL
msg <- expect_error(validate_projections(no_pos), "missing pos column")
if (!grepl("pos", msg, fixed = TRUE)) fail("missing-field error does not name 'pos': ", msg)

## player_id column absent -> error naming the field.
no_id <- snap
no_id$players$player_id <- NULL
msg <- expect_error(validate_projections(no_id), "missing player_id column")
if (!grepl("player_id", msg, fixed = TRUE)) fail("missing-field error omits 'player_id': ", msg)

## Required field NA -> error naming the field.
na_points <- snap
na_points$players$points[5] <- NA_real_
msg <- expect_error(validate_projections(na_points), "NA in points")
if (!grepl("points", msg, fixed = TRUE)) fail("NA error does not name 'points': ", msg)

## NA in player_id -> error naming the field.
na_id <- snap
na_id$players$player_id[7] <- NA_character_
msg <- expect_error(validate_projections(na_id), "NA in player_id")
if (!grepl("player_id", msg, fixed = TRUE)) fail("NA error does not name 'player_id': ", msg)

## Non-finite points -> error naming the field.
inf_points <- snap
inf_points$players$points[9] <- Inf
msg <- expect_error(validate_projections(inf_points), "non-finite points")
if (!grepl("points", msg, fixed = TRUE)) fail("non-finite error does not name 'points': ", msg)

## points non-numeric -> error naming the field.
chr_points <- snap
chr_points$players$points <- as.character(chr_points$players$points)
msg <- expect_error(validate_projections(chr_points), "non-numeric points")
if (!grepl("points", msg, fixed = TRUE)) fail("non-numeric error does not name 'points': ", msg)

## Invalid pos enum value -> error listing the value.
bad_pos <- snap
bad_pos$players$pos[3] <- "OL"
msg <- expect_error(validate_projections(bad_pos), "invalid pos value")
if (!grepl("OL", msg, fixed = TRUE)) fail("invalid-pos error does not list 'OL': ", msg)

## Missing list key -> error naming the key.
missing_key <- snap
missing_key$scoring <- NULL
msg <- expect_error(validate_projections(missing_key), "missing list key")
if (!grepl("scoring", msg, fixed = TRUE)) fail("missing-key error does not name 'scoring': ", msg)

## schema_version not 1L -> error.
bad_ver <- snap
bad_ver$schema_version <- 2L
msg <- expect_error(validate_projections(bad_ver), "wrong schema_version")
if (!grepl("schema_version", msg, fixed = TRUE)) fail("version error omits 'schema_version': ", msg)

## created_at not POSIXct -> error.
bad_ts <- snap
bad_ts$created_at <- "2026-09-01"
msg <- expect_error(validate_projections(bad_ts), "created_at not POSIXct")
if (!grepl("created_at", msg, fixed = TRUE)) fail("timestamp error omits 'created_at': ", msg)

## players not a data frame -> error.
bad_players <- snap
bad_players$players <- list(1, 2, 3)
expect_error(validate_projections(bad_players), "players not a data frame")

## players an empty data frame -> error.
empty_players <- snap
empty_players$players <- snap$players[0, , drop = FALSE]
expect_error(validate_projections(empty_players), "players has no rows")

## load_projections() on a missing path -> error naming the path.
missing_path <- file.path(tempdir(), "no-such-projections.rds")
msg <- expect_error(load_projections(missing_path), "load from missing path")
if (!grepl("no-such-projections.rds", msg, fixed = TRUE)) fail("missing-path error omits the path: ", msg)

## --- story 2: warroom_scoring() (offline, no scrape package) -------------
## Copy-and-override merge: overridden leaf wins, untouched leaf survives, an
## unnamed list (pts_bracket) is replaced wholesale, an unknown key errors.
base_scoring <- list(
  pass = list(pass_yds = 0.04, pass_tds = 4, pass_int = -3),
  rec  = list(rec = 0, rec_yds = 0.1, rec_tds = 6),
  kick = list(fg_4049 = 4, fg_50 = 5),
  pts_bracket = list(
    list(threshold = 0, points = 10),
    list(threshold = 6, points = 7)
  )
)
ovr_scoring <- list(
  rec  = list(rec = 1),
  pass = list(pass_int = -2),
  pts_bracket = list(list(threshold = 0, points = 12))
)
merged <- warroom_scoring(base_scoring, ovr_scoring)
if (!identical(merged$rec$rec, 1))          fail("warroom_scoring: rec override not applied")
if (!identical(merged$rec$rec_yds, 0.1))    fail("warroom_scoring: untouched rec leaf lost")
if (!identical(merged$rec$rec_tds, 6))      fail("warroom_scoring: untouched rec leaf lost")
if (!identical(merged$pass$pass_int, -2))   fail("warroom_scoring: nested override not applied")
if (!identical(merged$pass$pass_yds, 0.04)) fail("warroom_scoring: untouched pass leaf lost")
if (!identical(merged$kick, base_scoring$kick)) fail("warroom_scoring: unmentioned section changed")
if (length(merged$pts_bracket) != 1L ||
    !identical(merged$pts_bracket[[1]]$points, 12)) {
  fail("warroom_scoring: pts_bracket not replaced wholesale")
}
msg <- expect_error(
  warroom_scoring(base_scoring, list(bogus = list(x = 1))),
  "warroom_scoring: unknown top-level key"
)
if (!grepl("bogus", msg, fixed = TRUE)) fail("warroom_scoring: error does not name 'bogus': ", msg)
msg <- expect_error(
  warroom_scoring(base_scoring, list(rec = list(nonsense = 1))),
  "warroom_scoring: unknown nested key"
)
if (!grepl("rec$nonsense", msg, fixed = TRUE)) {
  fail("warroom_scoring: nested error does not name 'rec$nonsense': ", msg)
}

## overrides = NULL -> base returned unchanged (no-op merge).
if (!identical(warroom_scoring(base_scoring, NULL), base_scoring)) {
  fail("warroom_scoring: NULL overrides did not return base unchanged")
}

## A NULL override value would DELETE a base rule -> error naming the key path.
msg <- expect_error(
  warroom_scoring(base_scoring, list(pass = list(pass_int = NULL))),
  "warroom_scoring: NULL override value"
)
if (!grepl("pass$pass_int", msg, fixed = TRUE)) {
  fail("warroom_scoring: NULL-value error does not name 'pass$pass_int': ", msg)
}

## Scalar override where the base sub-section is a named list -> shape error.
msg <- expect_error(
  warroom_scoring(base_scoring, list(rec = 5)),
  "warroom_scoring: shape mismatch"
)
if (!grepl("rec", msg, fixed = TRUE)) {
  fail("warroom_scoring: shape-mismatch error does not name 'rec': ", msg)
}

## --- story 2: normalize_projections() (offline, no scrape package) -------
## Data frame shaped like the scrape adapter's projection table + player info + ADP.
mk_proj_table <- function(n = 8L, with_adp = TRUE, avg_types = "robust") {
  idx <- seq_len(n)
  df <- data.frame(
    avg_type    = rep(avg_types, length.out = n),
    id          = sprintf("FF-%04d", idx),
    first_name  = sprintf("First%02d", idx),
    last_name   = sprintf("Last%02d", idx),
    team        = rep(c("KC", "BUF", "SF", "DAL"), length.out = n),
    pos         = rep(c("qb", "rb", "wr", "te", "k", "dst"), length.out = n),
    points      = round(300 - 5 * idx, 1),
    sd_pts      = round(10 + idx, 1),
    floor       = round(280 - 5 * idx, 1),
    ceiling     = round(320 - 5 * idx, 1),
    points_vor  = round(120 - 5 * idx, 1),
    floor_vor   = round(100 - 5 * idx, 1),
    ceiling_vor = round(140 - 5 * idx, 1),
    rank        = idx,
    pos_rank    = idx,
    tier        = as.integer(ceiling(idx / 3)),
    stringsAsFactors = FALSE
  )
  if (with_adp) {
    df$adp    <- round(idx + 0.5, 1)
    df$adp_sd <- round(3 + 0.1 * idx, 1)
  }
  df
}

norm_cfg <- list(season = cfg$season, method = cfg$method,
                 vor_baseline = cfg$vor_baseline)

## Happy path: valid table -> contract list that passes validate_projections().
pt <- mk_proj_table()
nsnap <- normalize_projections(pt, cfg = norm_cfg, scoring = snap$scoring,
                               created_at = as.POSIXct("2026-09-01", tz = "UTC"))
if (!all(.warroom_projection_keys %in% names(nsnap))) fail("normalize: missing contract keys")
if (!identical(nsnap$schema_version, 1L))   fail("normalize: schema_version not 1L")
if (!identical(nsnap$season, as.integer(cfg$season))) fail("normalize: season mismatch")
if (!identical(nsnap$method, cfg$method))   fail("normalize: method mismatch")
if (!identical(nsnap$vor_baseline, cfg$vor_baseline)) fail("normalize: vor_baseline mismatch")
if (nrow(nsnap$players) != nrow(pt))        fail("normalize: row count changed")
if (!all(c("player_id", "player", "nfl_team", "pos", "points",
           "source_sd", "source_low", "source_high", "vor", "low_vor",
           "high_vor", "overall_rank", "pos_rank", "tier", "adp", "adp_sd")
         %in% names(nsnap$players))) {
  fail("normalize: mapped columns missing: ",
       paste(setdiff(c("player_id", "player", "nfl_team", "pos", "points",
                       "source_sd", "source_low", "source_high", "vor", "low_vor",
                       "high_vor", "overall_rank", "pos_rank", "tier", "adp", "adp_sd"),
                     names(nsnap$players)), collapse = ", "))
}
if (!identical(nsnap$players$player_id, pt$id)) fail("normalize: player_id not mapped from id")
if (!identical(nsnap$players$player[1], "First01 Last01")) fail("normalize: player name not built")
if (!all(nsnap$players$pos %in% .warroom_valid_pos)) fail("normalize: pos not upper-cased into enum")
if (!identical(nsnap$players$source_sd, pt$sd_pts))  fail("normalize: source_sd not mapped from sd_pts")
if (!identical(nsnap$players$vor, pt$points_vor))    fail("normalize: vor not mapped from points_vor")
if (!isTRUE(validate_projections(nsnap)))    fail("normalize: snapshot fails validate_projections")

## Mapped columns are coerced to fixed types (real scrape tables vary).
if (!is.integer(nsnap$players$overall_rank)) fail("normalize: overall_rank not coerced to integer")
if (!is.integer(nsnap$players$tier))         fail("normalize: tier not coerced to integer")
if (!is.character(nsnap$players$nfl_team))   fail("normalize: nfl_team not coerced to character")
if (!is.numeric(nsnap$players$adp))          fail("normalize: adp not coerced to numeric")

## Rows come out ordered by overall_rank.
if (is.unsorted(nsnap$players$overall_rank)) fail("normalize: players not ordered by overall_rank")

## A merged scoring object round-trips into the snapshot untouched.
nsnap_sc <- normalize_projections(pt, cfg = norm_cfg,
                                  scoring = warroom_scoring(base_scoring, ovr_scoring))
if (!identical(nsnap_sc$scoring, merged)) fail("normalize: scoring object not stamped through verbatim")

## avg_type stacking: extra "average" rows are filtered to method rows only.
pt_stacked <- rbind(
  transform(mk_proj_table(6L), avg_type = "robust"),
  transform(mk_proj_table(6L), avg_type = "average",
            id = sprintf("FF-AVG-%04d", seq_len(6L)))
)
nsnap_s <- normalize_projections(pt_stacked, cfg = norm_cfg, scoring = snap$scoring)
if (nrow(nsnap_s$players) != 6L) fail("normalize: avg_type filter kept non-robust rows")
if (any(grepl("AVG", nsnap_s$players$player_id))) fail("normalize: 'average' rows leaked through")

## Duplicate player_id -> error citing the id.
pt_dup <- mk_proj_table(5L)
pt_dup$id[2] <- pt_dup$id[1]
msg <- expect_error(
  normalize_projections(pt_dup, cfg = norm_cfg, scoring = snap$scoring),
  "normalize: duplicate id"
)
if (!grepl(pt_dup$id[1], msg, fixed = TRUE)) fail("normalize: dup error does not name the id: ", msg)

## Missing required source column `points` -> error naming it.
pt_nopts <- mk_proj_table(5L)
pt_nopts$points <- NULL
msg <- expect_error(
  normalize_projections(pt_nopts, cfg = norm_cfg, scoring = snap$scoring),
  "normalize: missing points column"
)
if (!grepl("points", msg, fixed = TRUE)) fail("normalize: missing-col error omits 'points': ", msg)

## Missing `id` -> error naming it.
pt_noid <- mk_proj_table(5L)
pt_noid$id <- NULL
msg <- expect_error(
  normalize_projections(pt_noid, cfg = norm_cfg, scoring = snap$scoring),
  "normalize: missing id column"
)
if (!grepl("id", msg, fixed = TRUE)) fail("normalize: missing-col error omits 'id': ", msg)

## Missing `pos` -> error naming it.
pt_nopos <- mk_proj_table(5L)
pt_nopos$pos <- NULL
msg <- expect_error(
  normalize_projections(pt_nopos, cfg = norm_cfg, scoring = snap$scoring),
  "normalize: missing pos column"
)
if (!grepl("pos", msg, fixed = TRUE)) fail("normalize: missing-col error omits 'pos': ", msg)

## ADP absent -> snapshot without adp/adp_sd, still valid, with a warning.
pt_noadp <- mk_proj_table(5L, with_adp = FALSE)
res <- expect_warning(
  normalize_projections(pt_noadp, cfg = norm_cfg, scoring = snap$scoring),
  "normalize: adp-absent warning"
)
if (!grepl("adp", res$message, fixed = TRUE)) fail("normalize: adp warning omits 'adp': ", res$message)
if (any(c("adp", "adp_sd") %in% names(res$value$players))) {
  fail("normalize: adp/adp_sd columns present despite missing source")
}
if (!isTRUE(validate_projections(res$value))) fail("normalize: adp-less snapshot fails validation")

## Partial ADP (only one of the pair) -> both dropped, warning says which was present.
pt_halfadp <- mk_proj_table(5L)
pt_halfadp$adp_sd <- NULL
res <- expect_warning(
  normalize_projections(pt_halfadp, cfg = norm_cfg, scoring = snap$scoring),
  "normalize: partial-adp warning"
)
if (!grepl("adp", res$message, fixed = TRUE)) fail("normalize: partial-adp warning omits 'adp': ", res$message)
if (any(c("adp", "adp_sd") %in% names(res$value$players))) {
  fail("normalize: partial adp not fully dropped")
}
if (!isTRUE(validate_projections(res$value))) fail("normalize: partial-adp snapshot fails validation")

## Invalid pos value survives mapping and is rejected by validate_projections().
pt_badpos <- mk_proj_table(5L)
pt_badpos$pos[3] <- "OL"
msg <- expect_error(
  normalize_projections(pt_badpos, cfg = norm_cfg, scoring = snap$scoring),
  "normalize: invalid pos"
)
if (!grepl("OL", msg, fixed = TRUE)) fail("normalize: invalid-pos error omits 'OL': ", msg)

cat("story 2 offline checks OK -- warroom_scoring + normalize_projections\n")

## --- story 3: snake schedule, draft state, RDS persistence (offline) -----
## Every row of the story-3 I/O & Edge-Case matrix. tempdir() only -- state/ is
## never touched. No network.

team_order <- sprintf("Team %02d", 1:12)

## Schedule: 168 turns, correct serpentine reversals, round/pick_in_round values.
sched <- make_snake_schedule(cfg$league$teams, cfg$league$rounds)
if (!identical(nrow(sched), 168L)) fail("schedule: expected 168 rows, got ", nrow(sched))
if (!identical(names(sched), c("overall", "round", "pick_in_round", "slot"))) {
  fail("schedule: wrong columns: ", paste(names(sched), collapse = ", "))
}
if (!identical(sched$overall, 1:168))       fail("schedule: overall not sequential 1..168")
if (sched$slot[1] != 1L || sched$slot[12] != 12L) fail("schedule: round 1 not ascending 1..12")
if (sched$slot[13] != 12L) fail("schedule: pick 13 should be slot 12, got ", sched$slot[13])
if (sched$slot[24] != 1L)  fail("schedule: pick 24 should be slot 1, got ", sched$slot[24])
if (sched$slot[25] != 1L)  fail("schedule: pick 25 should be slot 1, got ", sched$slot[25])
if (sched$round[13] != 2L)         fail("schedule: pick 13 round != 2, got ", sched$round[13])
if (sched$pick_in_round[13] != 1L) fail("schedule: pick 13 pick_in_round != 1, got ", sched$pick_in_round[13])
if (sched$round[25] != 3L)         fail("schedule: pick 25 round != 3")
if (sched$pick_in_round[24] != 12L) fail("schedule: pick 24 pick_in_round != 12")

## make_snake_schedule rejects NA / < 1 / non-scalar / fractional.
expect_error(make_snake_schedule(NA_integer_, 14L), "schedule NA teams")
expect_error(make_snake_schedule(0L, 14L),          "schedule teams < 1")
expect_error(make_snake_schedule(c(12L, 12L), 14L), "schedule non-scalar teams")
msg <- expect_error(make_snake_schedule(12.9, 14L), "schedule fractional teams")
if (!grepl("whole number", msg)) fail("schedule: fractional-teams error wording: ", msg)
expect_error(make_snake_schedule(12L, 14.5),        "schedule fractional rounds")

## new_draft happy path.
d0 <- new_draft(snap, team_order, "Team 01")
if (!identical(names(d0), .warroom_state_keys)) {
  fail("new_draft: state keys wrong: ", paste(names(d0), collapse = ", "))
}
if (!identical(d0$schema_version, 1L)) fail("new_draft: schema_version not 1L")
if (!identical(d0$projection_created_at, snap$created_at)) {
  fail("new_draft: projection_created_at != snapshot created_at")
}
if (nrow(d0$picks) != 0L) fail("new_draft: picks not empty")
if (!identical(names(d0$picks), c("overall", "player_id", "entered_at"))) {
  fail("new_draft: picks columns wrong: ", paste(names(d0$picks), collapse = ", "))
}
if (!is.integer(d0$picks$overall))          fail("new_draft: picks$overall not integer")
if (!is.character(d0$picks$player_id))      fail("new_draft: picks$player_id not character")
if (!inherits(d0$picks$entered_at, "POSIXct")) fail("new_draft: picks$entered_at not POSIXct")
if (!identical(d0$league$teams, 12L) || !identical(d0$league$rounds, 14L)) {
  fail("new_draft: league teams/rounds wrong")
}
if (is.null(names(d0$league$roster))) fail("new_draft: roster not a named vector")
if (!is.integer(d0$league$roster))   fail("new_draft: roster not coerced to integer")
if (!identical(d0$user_team, "Team 01")) fail("new_draft: user_team not stored")
if (!identical(d0$seed, 1L))             fail("new_draft: default seed not 1L")

## new_draft with explicit seed + explicit (non-config) league.
custom_league <- list(teams = 4L, rounds = 3L,
                      roster = c(QB = 1L, RB = 1L, FLEX = 1L),
                      flex_positions = c("RB", "WR"))
dc <- new_draft(snap, sprintf("T%d", 1:4), "T2", seed = 7L, league = custom_league)
if (!identical(dc$seed, 7L))          fail("new_draft: explicit seed not stored")
if (!identical(dc$league$teams, 4L) || !identical(dc$league$rounds, 3L)) {
  fail("new_draft: explicit league not used")
}
if (nrow(make_snake_schedule(dc$league$teams, dc$league$rounds)) != 12L) {
  fail("new_draft: custom-league schedule size wrong")
}

## new_draft: team_order / user_team / seed / snapshot invalid.
expect_error(new_draft(snap, team_order[1:11], "Team 01"), "new_draft short team_order")
dup_order <- team_order; dup_order[12] <- dup_order[1]
msg <- expect_error(new_draft(snap, dup_order, "Team 01"), "new_draft dup team_order")
if (!grepl("duplicate", msg)) fail("new_draft: dup error message: ", msg)
na_order <- team_order; na_order[5] <- NA_character_
msg <- expect_error(new_draft(snap, na_order, "Team 01"), "new_draft NA team_order")
if (!grepl("NA", msg)) fail("new_draft: NA-team_order error wording: ", msg)
msg <- expect_error(new_draft(snap, team_order, "Nobody"), "new_draft bad user_team")
if (!grepl("Nobody", msg)) fail("new_draft: user_team error omits the name: ", msg)
msg <- expect_error(new_draft(snap, team_order, "Team 01", seed = 1.5), "new_draft fractional seed")
if (!grepl("whole number", msg)) fail("new_draft: fractional-seed error wording: ", msg)
bad_snap <- snap; bad_snap$players <- list(1, 2)
msg <- expect_error(new_draft(bad_snap, team_order, "Team 01"), "new_draft bad snapshot players")
if (!grepl("player_id", msg)) fail("new_draft: bad-snapshot error omits player_id: ", msg)

## record_pick happy path.
pid1 <- snap$players$player_id[1]
pid2 <- snap$players$player_id[2]
d1 <- record_pick(d0, pid1, snap,
                  entered_at = as.POSIXct("2026-09-01 13:00:00", tz = "UTC"))
if (nrow(d1$picks) != 1L)          fail("record_pick: expected 1 pick")
if (d1$picks$overall[1] != 1L)     fail("record_pick: overall of first pick != 1")
if (d1$picks$player_id[1] != pid1) fail("record_pick: player_id not stored")
d2 <- record_pick(d1, pid2, snap)
if (nrow(d2$picks) != 2L || d2$picks$overall[2] != 2L) fail("record_pick: second pick wrong")

## record_pick entered_at handling.
d_str <- record_pick(d0, pid1, snap, entered_at = "2026-09-01 13:00:00")
if (!inherits(d_str$picks$entered_at, "POSIXct")) fail("record_pick: string entered_at not POSIXct")
if (format(d_str$picks$entered_at[1], "%Y-%m-%d %H:%M:%S") != "2026-09-01 13:00:00") {
  fail("record_pick: string entered_at not parsed to the expected instant")
}
expect_error(record_pick(d0, pid1, snap, entered_at = rep(Sys.time(), 2)), "record_pick entered_at length")
expect_error(record_pick(d0, pid1, snap, entered_at = as.POSIXct(NA)),     "record_pick entered_at NA")
expect_error(record_pick(d0, pid1, snap, entered_at = "not a date"),       "record_pick entered_at unparseable")

## record_pick negative cases.
msg <- expect_error(record_pick(d1, "SYN-NOPE-999", snap), "record_pick unknown id")
if (!grepl("SYN-NOPE-999", msg)) fail("record_pick: unknown-id error omits id: ", msg)
msg <- expect_error(record_pick(d1, pid1, snap), "record_pick repeat id")
if (!grepl(pid1, msg, fixed = TRUE)) fail("record_pick: repeat-id error omits id: ", msg)

## Draft full: 168 picks, another record_pick -> error citing 168.
fixed_ea <- rep(as.POSIXct("2026-09-01 12:00:00", tz = "UTC"), 200)
full_state <- d0
full_state$picks <- data.frame(
  overall    = 1:168,
  player_id  = snap$players$player_id[1:168],
  entered_at = fixed_ea[1:168],
  stringsAsFactors = FALSE
)
msg <- expect_error(record_pick(full_state, snap$players$player_id[169], snap),
                    "record_pick draft full")
if (!grepl("168", msg)) fail("record_pick: full-draft error omits 168: ", msg)

## undo_pick + availability.
u1 <- undo_pick(d2)
if (nrow(u1$picks) != 1L)               fail("undo_pick: expected 1 pick after undo")
if (u1$picks$player_id[1] != pid1)      fail("undo_pick: removed the wrong pick")
if (!identical(u1$picks$player_id, d1$picks$player_id) ||
    !identical(u1$picks$overall, d1$picks$overall)) {
  fail("undo_pick: result does not match the pre-second-pick picks")
}
u1v <- derive_draft_view(u1, snap)
if (!(pid2 %in% u1v$available$player_id)) fail("undo_pick: undone player not back in available")
if (pid2 %in% unlist(lapply(u1v$rosters, function(r) r$player_id))) {
  fail("undo_pick: undone player still sits in a roster")
}
## undo then draft a different player -> overall renumbers.
pid3 <- snap$players$player_id[3]
u1b <- record_pick(u1, pid3, snap)
if (!identical(u1b$picks$overall, 1:2))     fail("undo+record: overall not renumbered to 1:2")
if (u1b$picks$player_id[2] != pid3)         fail("undo+record: wrong player at slot 2")
expect_error(undo_pick(d0), "undo_pick empty")

## derive_draft_view mid-draft (round 1).
v2 <- derive_draft_view(d2, snap)
if (!identical(v2$current_overall, 3L)) fail("view: current_overall != 3 after 2 picks")
if (isTRUE(v2$is_complete))             fail("view: is_complete TRUE at pick 3")
if (v2$team_on_clock != "Team 03")      fail("view: team_on_clock != Team 03, got ", v2$team_on_clock)
if (!identical(v2$round_on_clock, 1L))  fail("view: round_on_clock != 1 at pick 3")
if (!identical(v2$slot_on_clock, 3L))   fail("view: slot_on_clock != 3 at pick 3")
if (!identical(sort(v2$drafted_ids), sort(c(pid1, pid2)))) fail("view: drafted_ids wrong")
if (nrow(v2$available) != nrow(snap$players) - 2L)         fail("view: available count wrong")
if (any(v2$available$player_id %in% c(pid1, pid2)))        fail("view: drafted players still available")
if (!identical(names(v2$rosters), team_order))            fail("view: rosters not named by team_order")
if (nrow(v2$rosters[["Team 01"]]) != 1L || v2$rosters[["Team 01"]]$player_id != pid1) {
  fail("view: Team 01 roster wrong")
}
if (nrow(v2$rosters[["Team 02"]]) != 1L || v2$rosters[["Team 02"]]$player_id != pid2) {
  fail("view: Team 02 roster wrong")
}
if (nrow(v2$rosters[["Team 05"]]) != 0L) fail("view: team with no picks should have a 0-row roster")
if (length(setdiff(names(d2), .warroom_state_keys)) != 0L) {
  fail("view: state carries non-contract keys: ",
       paste(setdiff(names(d2), .warroom_state_keys), collapse = ", "))
}

## derive_draft_view serpentine past round 1: build 12/13/14-pick states.
mk_state <- function(k) {
  st <- d0
  st$picks <- data.frame(overall = seq_len(k),
                         player_id = snap$players$player_id[seq_len(k)],
                         entered_at = fixed_ea[seq_len(k)],
                         stringsAsFactors = FALSE)
  st
}
v12 <- derive_draft_view(mk_state(12L), snap)   # pick 13 on the clock
if (!identical(v12$current_overall, 13L))  fail("view: current_overall != 13 after 12 picks")
if (v12$team_on_clock != "Team 12")        fail("view: pick 13 should be Team 12, got ", v12$team_on_clock)
if (!identical(v12$round_on_clock, 2L))    fail("view: pick 13 round_on_clock != 2")
if (!identical(v12$slot_on_clock, 12L))    fail("view: pick 13 slot_on_clock != 12")
v13 <- derive_draft_view(mk_state(13L), snap)   # pick 14 on the clock
if (v13$team_on_clock != "Team 11")        fail("view: pick 14 should be Team 11, got ", v13$team_on_clock)
if (!identical(v13$slot_on_clock, 11L))    fail("view: pick 14 slot_on_clock != 11")
## pick 13 belongs to slot 12 -> Team 12, so Team 12 holds picks 12 AND 13.
if (nrow(v13$rosters[["Team 12"]]) != 2L)  fail("view: Team 12 should hold 2 picks after 13 picks")
if (!identical(sort(v13$rosters[["Team 12"]]$player_id),
               sort(snap$players$player_id[c(12L, 13L)]))) {
  fail("view: round-2 pick 13 did not land in Team 12's roster")
}
if (nrow(v13$rosters[["Team 01"]]) != 1L)  fail("view: Team 01 should still hold only pick 1 after 13 picks")
v14 <- derive_draft_view(mk_state(14L), snap)   # pick 15 on the clock
if (v14$team_on_clock != "Team 10")        fail("view: pick 15 should be Team 10, got ", v14$team_on_clock)

## derive_draft_view at the end (168 picks).
vend <- derive_draft_view(full_state, snap)
if (!isTRUE(vend$is_complete))      fail("view: is_complete not TRUE at 168 picks")
if (!is.na(vend$current_overall))   fail("view: current_overall not NA at end")
if (!is.na(vend$team_on_clock))     fail("view: team_on_clock not NA at end")

## next_user_pick: snake turn + exhaustion.
if (!identical(next_user_pick(d0), 1L))  fail("next_user_pick: empty draft (Team 01) should be 1")
if (!identical(next_user_pick(d1), 24L)) fail("next_user_pick: after pick 1 expected 24, got ", next_user_pick(d1))
d_t12 <- new_draft(snap, team_order, "Team 12")
if (!identical(next_user_pick(d_t12), 12L)) fail("next_user_pick: Team 12 first pick should be 12")
st12 <- d_t12
st12$picks <- data.frame(overall = 1:12, player_id = snap$players$player_id[1:12],
                         entered_at = fixed_ea[1:12], stringsAsFactors = FALSE)
if (!identical(next_user_pick(st12), 13L)) {
  fail("next_user_pick: Team 12 back-to-back should be 13, got ", next_user_pick(st12))
}
if (!is.na(next_user_pick(full_state))) fail("next_user_pick: exhausted (Team 01, 168 picks) should be NA")

## save_state / load_state: round trip, atomic .bak, no stray .tmp, dir created.
sp <- file.path(tempdir(), "warroom-s3", "draft.rds")
unlink(dirname(sp), recursive = TRUE)
save_state(d0, sp)
if (!file.exists(sp))                    fail("save_state: file not written")
if (file.exists(paste0(sp, ".bak")))     fail("save_state: .bak created on first save")
if (!identical(load_state(sp), d0))      fail("load_state: first round trip differs")

save_state(d2, sp)
if (!file.exists(paste0(sp, ".bak")))    fail("save_state: .bak not created on second save")
if (file.exists(paste0(sp, ".tmp")))     fail("save_state: stray .tmp left behind")
if (!identical(readRDS(paste0(sp, ".bak")), d0)) fail("save_state: .bak does not hold the previous state")
d2_reloaded <- load_state(sp)
if (!identical(d2_reloaded$picks, d2$picks)) fail("load_state: picks not preserved in order")
if (!identical(d2_reloaded, d2))             fail("load_state: full state round trip differs")
if (length(setdiff(names(readRDS(sp)), .warroom_state_keys)) != 0L) {
  fail("save_state: persisted state carries non-contract keys: ",
       paste(setdiff(names(readRDS(sp)), .warroom_state_keys), collapse = ", "))
}

## save_state pre-write validation: malformed state -> error, no file, no .tmp.
malp <- file.path(tempdir(), "warroom-s3-mal", "draft.rds")
unlink(dirname(malp), recursive = TRUE)
mal_state <- d0; mal_state$schema_version <- 99L
expect_error(save_state(mal_state, malp), "save_state rejects malformed state")
if (file.exists(malp))               fail("save_state: wrote target despite invalid state")
if (file.exists(paste0(malp, ".tmp"))) fail("save_state: left a .tmp despite invalid state")

## load_state missing path.
msg <- expect_error(load_state(file.path(tempdir(), "no-such-draft.rds")), "load_state missing")
if (!grepl("no-such-draft.rds", msg, fixed = TRUE)) fail("load_state: missing-path error omits path: ", msg)

## load_state corrupt / non-RDS file -> error naming the path.
corrupt <- file.path(tempdir(), "s3-corrupt.rds")
writeLines("this is not an RDS file", corrupt)
msg <- expect_error(load_state(corrupt), "load_state corrupt file")
if (!grepl("s3-corrupt.rds", msg, fixed = TRUE)) fail("load_state: corrupt-file error omits path: ", msg)

## load_state bad schema: version, missing key, malformed picks in several ways.
mk_bad <- function(mut, name) {
  b <- d0; b <- mut(b)
  p <- file.path(tempdir(), name); saveRDS(b, p); p
}
msg <- expect_error(load_state(mk_bad(function(b) { b$schema_version <- 2L; b }, "s3-bad-ver.rds")),
                    "load_state bad schema_version")
if (!grepl("schema_version", msg)) fail("load_state: bad-version error omits schema_version: ", msg)

msg <- expect_error(load_state(mk_bad(function(b) { b$team_order <- NULL; b }, "s3-bad-key.rds")),
                    "load_state missing key")
if (!grepl("team_order", msg)) fail("load_state: missing-key error omits team_order: ", msg)

msg <- expect_error(load_state(mk_bad(function(b) { b$league$teams <- 12.5; b }, "s3-bad-league.rds")),
                    "load_state malformed league")
if (!grepl("league\\$teams", msg)) fail("load_state: malformed-league error omits league$teams: ", msg)

bad_seq <- function(b) {
  b$picks <- data.frame(overall = c(1L, 3L), player_id = c("a", "b"),
                        entered_at = fixed_ea[1:2], stringsAsFactors = FALSE)
  b
}
msg <- expect_error(load_state(mk_bad(bad_seq, "s3-bad-seq.rds")), "load_state non-sequential overall")
if (!grepl("row number", msg)) fail("load_state: non-sequential-overall error wording: ", msg)

bad_dup <- function(b) {
  b$picks <- data.frame(overall = c(1L, 2L), player_id = c("dupe", "dupe"),
                        entered_at = fixed_ea[1:2], stringsAsFactors = FALSE)
  b
}
msg <- expect_error(load_state(mk_bad(bad_dup, "s3-bad-dup.rds")), "load_state dup player_id")
if (!grepl("duplicate", msg) || !grepl("dupe", msg, fixed = TRUE)) {
  fail("load_state: dup-player_id error wording: ", msg)
}

bad_cap <- function(b) {
  b$picks <- data.frame(overall = seq_len(169), player_id = sprintf("p%03d", 1:169),
                        entered_at = fixed_ea[rep(1L, 169)], stringsAsFactors = FALSE)
  b
}
msg <- expect_error(load_state(mk_bad(bad_cap, "s3-bad-cap.rds")), "load_state over capacity")
if (!grepl("168", msg)) fail("load_state: over-capacity error omits 168: ", msg)

bad_pid_type <- function(b) {
  b$picks <- data.frame(overall = 1L, player_id = 1L,
                        entered_at = fixed_ea[1], stringsAsFactors = FALSE)
  b
}
msg <- expect_error(load_state(mk_bad(bad_pid_type, "s3-bad-pidtype.rds")), "load_state non-character player_id")
if (!grepl("player_id", msg)) fail("load_state: non-character-player_id error omits player_id: ", msg)

bad_ea_type <- function(b) {
  b$picks <- data.frame(overall = 1L, player_id = "a",
                        entered_at = as.Date("2026-09-01"), stringsAsFactors = FALSE)
  b
}
msg <- expect_error(load_state(mk_bad(bad_ea_type, "s3-bad-eatype.rds")), "load_state non-POSIXct entered_at")
if (!grepl("entered_at", msg)) fail("load_state: non-POSIXct-entered_at error omits entered_at: ", msg)

## Full round trip: new_draft -> several record_pick -> save -> load -> view.
rt <- new_draft(snap, team_order, "Team 01")
for (i in 1:10) rt <- record_pick(rt, snap$players$player_id[i], snap)
rtp <- file.path(tempdir(), "warroom-s3-rt", "draft.rds")
unlink(dirname(rtp), recursive = TRUE)
save_state(rt, rtp)
rt2 <- load_state(rtp)
if (!identical(rt2$picks, rt$picks)) fail("round trip: picks changed")
rv <- derive_draft_view(rt2, snap)
if (!identical(rv$current_overall, 11L))              fail("round trip: view current_overall != 11")
if (length(rv$drafted_ids) != 10L)                    fail("round trip: drafted_ids count wrong")
if (nrow(rv$available) != nrow(snap$players) - 10L)   fail("round trip: available count wrong")

cat("story 3 offline checks OK -- schedule + draft state + RDS persistence\n")

## --- story 4: operational terminal draft (offline) ----------------------
## Drive scripts/draft.R's run_draft() with canned input/output connections.
## Covers every row of the story-4 I/O & Edge-Case matrix, plus a full reduced
## rehearsal with one stop (/quit) and resume. tempdir() only, no network.

source("scripts/draft.R")   # defines run_draft(); sys.nframe() guard prevents exec

s4_dir  <- file.path(tempdir(), "warroom-s4")
unlink(s4_dir, recursive = TRUE)
s4_path <- file.path(s4_dir, "draft.rds")
team_line <- paste(sprintf("Team %02d", 1:12), collapse = ",")

## Run run_draft() over a canned script; return the captured output lines.
s4_run <- function(lines, state_path = s4_path) {
  ci <- textConnection(lines)
  co <- textConnection("s4_out", open = "w", local = TRUE)
  run_draft(con = ci, out = co, snapshot = snap, state_path = state_path)
  close(co); close(ci)
  s4_out
}
has <- function(out, pat) any(grepl(pat, out, fixed = TRUE))

## (1a) New draft; /undo with no picks; invalid team orders are caught earlier.
o1a <- s4_run(c(team_line, "/undo", "/status", "/quit"))
if (!has(o1a, "== novo draft =="))   fail("s4: new-draft banner missing")
if (!has(o1a, "nada a desfazer"))    fail("s4: /undo on empty draft not handled")
if (!file.exists(s4_path))           fail("s4: new draft not saved")
d_new <- load_state(s4_path)
if (nrow(d_new$picks) != 0L)         fail("s4: new draft should have 0 picks")
if (!identical(d_new$user_team, "Team 01")) fail("s4: user_team not derived from user_slot")
if (length(setdiff(names(d_new), .warroom_state_keys)) != 0L) {
  fail("s4: saved state carries non-contract keys")
}

## Invalid team order -> caught, re-prompt, then a valid line proceeds.
o_bad <- s4_run(c("A,B,C", paste(sprintf("T%02d", 1:12), collapse = ","), "/quit"),
                state_path = file.path(tempdir(), "warroom-s4-bad", "draft.rds"))
if (!has(o_bad, "ordem invalida")) fail("s4: short team order not rejected")

## (1b) Resume the 0-pick draft and exercise resolution + every command.
o1b <- s4_run(c(
  "RB Synthetic 01",     # pick 1 Team 01 (user) -- exact
  "te synthe",           # pick 2 Team 02 -- prefix tier, ambiguous
  "2",                   #   choose the 2nd TE
  "r synthetic 40",      # pick 3 Team 03 -- substring tier (prefix empty), unique
  "rb synthetc 03",      # pick 4 Team 04 -- fuzzy (typo), unique
  "qb synthetic 1",      # pick 5 Team 05 -- ambiguous (QB 10-19)
  "1",                   #   choose the 1st
  "xyzzy",               # pick 6 -- no match
  "RB Synthetic 01",     # pick 6 -- already drafted -> resolves to none
  "/board", "/board rb", "/board xx",   # board, filtered, invalid pos
  "/team", "/teams", "/status", "/rec", # views + degraded rec
  "WR Synthetic 01",     # pick 6 Team 06 -- exact
  "/undo",               # undo pick 6
  "WR Synthetic 02",     # pick 6 Team 06 again
  "/save",               # explicit save
  "K Synthetic 01",      # pick 7 Team 07
  "DST Synthetic 04",    # pick 8 Team 08
  "/quit"                # stop mid-draft
))
if (!has(o1b, "== retomando"))                       fail("s4: resume banner missing")
if (!has(o1b, "varios jogadores casam 'te synthe'")) fail("s4: prefix-tier disambiguation missing")
if (!has(o1b, "varios jogadores casam 'qb synthetic 1'")) fail("s4: ambiguous+number missing")
if (!has(o1b, "nenhum jogador disponivel casa 'xyzzy'")) fail("s4: no-match not reported")
if (!has(o1b, "nenhum jogador disponivel casa 'RB Synthetic 01'")) fail("s4: already-drafted name not rejected")
if (!has(o1b, "melhores disponiveis:"))              fail("s4: /board missing")
if (!has(o1b, "melhores disponiveis (RB)"))          fail("s4: /board rb missing")
if (!has(o1b, "unknown position 'XX'"))              fail("s4: /board xx not validated")
if (!has(o1b, "R01  overall"))                       fail("s4: /status banner missing")
if (!has(o1b, "recomendacoes chegam na story 5"))    fail("s4: degraded /rec missing")
if (!has(o1b, "desfeito o ultimo pick"))             fail("s4: /undo not confirmed")
if (!has(o1b, "salvo em"))                           fail("s4: /save not confirmed")
if (!has(o1b, "Team 01:"))                           fail("s4: /team header missing")
if (!has(o1b, "Team 12:"))                           fail("s4: /teams did not list every team")

d1b <- load_state(s4_path)
if (nrow(d1b$picks) != 8L)                        fail("s4: expected 8 picks after 1b, got ", nrow(d1b$picks))
if (d1b$picks$player_id[1] != "SYN-RB-001")       fail("s4: pick 1 not RB Synthetic 01")
if ("SYN-WR-001" %in% d1b$picks$player_id)        fail("s4: undone WR Synthetic 01 still recorded")
if (!("SYN-WR-002" %in% d1b$picks$player_id))     fail("s4: WR Synthetic 02 not recorded")
if (!("SYN-WR-040" %in% d1b$picks$player_id))     fail("s4: substring match WR Synthetic 40 not recorded")
if (!("SYN-RB-003" %in% d1b$picks$player_id))     fail("s4: fuzzy match RB Synthetic 03 not recorded")
if (!file.exists(paste0(s4_path, ".bak")))        fail("s4: no .bak after repeated saves")
if (!identical(d1b$picks$overall, 1:8))           fail("s4: picks$overall not 1..8")

## (1c) Command-loop edge cases on a fresh draft: /help, blank line, out-of-range
## disambiguation number, and EOF mid-loop (no trailing /quit) -> clean save.
s4c_path <- file.path(tempdir(), "warroom-s4c", "draft.rds")
unlink(dirname(s4c_path), recursive = TRUE)
o1c <- s4_run(c(
  team_line,
  "/help",               # help text
  "",                    # blank line -> reprompt, no crash
  "te synthe", "99",     # ambiguous + out-of-range number -> no pick
  "te synthe", "999999", # again, huge number
  "QB Synthetic 04"      # a real pick, then input ends WITHOUT /quit -> EOF quit
), state_path = s4c_path)
if (!has(o1c, "comandos: /rec"))          fail("s4: /help not shown")
if (!has(o1c, "numero fora do range"))    fail("s4: out-of-range disambiguation not handled")
d1c <- load_state(s4c_path)               # EOF must have saved
if (nrow(d1c$picks) != 1L)                fail("s4: EOF mid-loop did not save exactly the 1 real pick")
if (d1c$picks$player_id[1] != "SYN-QB-004") fail("s4: EOF-run recorded the wrong pick")
unlink(dirname(s4c_path), recursive = TRUE)

## (1d) Auto-recommendation on the user's turn must appear BEFORE the first pick
## prompt, independently of any /rec command.
s4d_path <- file.path(tempdir(), "warroom-s4d", "draft.rds")
unlink(dirname(s4d_path), recursive = TRUE)
invisible(s4_run(team_line_only <- c(team_line, "/quit"), state_path = s4d_path))
o1d <- s4_run(c("QB Synthetic 03"), state_path = s4d_path)  # resume; user (Team 01) on the clock, no /rec
rec_at    <- which(grepl("recomendacoes chegam na story 5", o1d, fixed = TRUE))
prompt_at <- which(grepl("pick 1 > ", o1d, fixed = TRUE))
if (!length(rec_at))                       fail("s4: no auto-recommendation on the user's turn")
if (length(prompt_at) && rec_at[1] > prompt_at[1]) fail("s4: recommendation printed after the pick prompt")
unlink(dirname(s4d_path), recursive = TRUE)

## (1e) Invalid team orders at the adapter: 13 names and a duplicate name.
o_bad2 <- s4_run(c(paste(sprintf("Team %02d", 1:13), collapse = ","),
                   sub("Team 02", "Team 01",
                       paste(sprintf("Team %02d", 1:12), collapse = ",")),
                   paste(sprintf("Team %02d", 1:12), collapse = ","), "/quit"),
                 state_path = file.path(tempdir(), "warroom-s4-bad2", "draft.rds"))
if (sum(grepl("ordem invalida", o_bad2)) < 2L) fail("s4: 13-name / duplicate order not both rejected")
unlink(file.path(tempdir(), "warroom-s4-bad2"), recursive = TRUE)

## (2) Resume and complete the rehearsal to all 168 picks.
o2 <- s4_run(snap$players$player)   # every full name; drafted ones resolve to none
if (!has(o2, "=== DRAFT COMPLETO -- 168 picks ==="))  fail("s4: rehearsal did not complete 168 picks")
d_final <- load_state(s4_path)
if (nrow(d_final$picks) != 168L)                      fail("s4: final draft not 168 picks")
if (anyDuplicated(d_final$picks$player_id))           fail("s4: duplicate pick in completed draft")
vf <- derive_draft_view(d_final, snap)
if (!isTRUE(vf$is_complete))                          fail("s4: final view not is_complete")
if (!is.na(vf$current_overall))                       fail("s4: completed draft still has a current pick")
if (length(setdiff(names(readRDS(s4_path)), .warroom_state_keys)) != 0L) {
  fail("s4: completed-draft state carries non-contract keys")
}

## resolve_player / available_board direct unit checks.
vroot <- derive_draft_view(new_draft(snap, sprintf("Team %02d", 1:12), "Team 01"), snap)
r_ex <- resolve_player("WR Synthetic 05", vroot$available)
if (r_ex$status != "unique" || nrow(r_ex$players) != 1L) fail("s4: exact resolve not unique")
r_no <- resolve_player("no such guy", vroot$available)
if (r_no$status != "none")                               fail("s4: bad query should resolve to none")
r_amb <- resolve_player("te synthe", vroot$available)
if (r_amb$status != "ambiguous" || nrow(r_amb$players) < 2L) fail("s4: prefix should be ambiguous")
if (!identical(order(-r_amb$players$points, r_amb$players$player_id, method = "radix"),
               seq_len(nrow(r_amb$players)))) fail("s4: resolve_player order not deterministic")
expect_error(available_board(vroot, pos = "OL"), "available_board invalid pos")
bd_rb <- available_board(vroot, pos = "RB", n = 5L)
if (nrow(bd_rb) != 5L || any(bd_rb$pos != "RB"))          fail("s4: available_board filter/cap wrong")
if (!identical(bd_rb$overall_rank, sort(bd_rb$overall_rank))) fail("s4: available_board not ordered")

## resolve_player: a drafted exact name that is also the prefix of an available
## name must still surface that available name (not short-circuit to "none");
## a drafted exact name with no prefix/substring hit does resolve to "none".
mini <- data.frame(
  player_id = c("a", "b", "c"),
  player    = c("Mike Williams", "Mike Williams Jr", "Joe Burrow"),
  pos       = c("WR", "WR", "QB"), points = c(200, 150, 300),
  overall_rank = 1:3, stringsAsFactors = FALSE
)
r_pfx <- resolve_player("mike williams", mini[2:3, ], mini)   # "Mike Williams" drafted
if (r_pfx$status != "unique" || r_pfx$players$player_id != "b") {
  fail("s4: drafted exact name suppressed an available prefix match")
}
r_gone <- resolve_player("joe burrow", mini[1:2, ], mini)      # "Joe Burrow" drafted
if (r_gone$status != "none") fail("s4: drafted exact name with no other match should be none")

## resolve_player never matches a blank normalized name.
blank <- data.frame(player_id = c("x", "y"), player = c("!!!", "Real Player"),
                    pos = c("WR", "WR"), points = c(10, 20), stringsAsFactors = FALSE)
if (resolve_player("z", blank, blank)$status != "none") fail("s4: short query matched a blank name")

unlink(s4_dir, recursive = TRUE)
unlink(file.path(tempdir(), "warroom-s4-bad"), recursive = TRUE)
cat("story 4 offline checks OK -- terminal loop + name resolution + rehearsal\n")

## --- Summary (I/O matrix: "smoke offline") -------------------------------
cat(sprintf("smoke OK -- %d players in %s\n", n, snapshot_path))
for (p in names(pos_tab)) cat(sprintf("  %-3s %3d\n", p, pos_tab[[p]]))
cat(sprintf("snapshot size: %.1f KB\n", file.size(snapshot_path) / 1024))
quit(status = 0L, save = "no")
