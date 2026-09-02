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
  "/team", "/teams", "/status", "/rec", # views + real recommendations
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
if (!has(o1b, "recomendacoes (top"))                 fail("s4: /rec output missing")
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
rec_at    <- which(grepl("recomendacoes (top", o1d, fixed = TRUE))
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

## --- story 5: roster-aware recommendation foundation (offline) ----------
## Hand-built pick states (picks$overall == row, unique ids) drive
## recommend_players(); the snake schedule maps slot-1 picks to the user
## (Team 01), so the user roster is exactly the ids placed at those overalls.
## tempdir() only, no network.

## default weights: four names, sum to 1.
w5 <- default_decision_weights()
if (!identical(sort(names(w5)), sort(c("roster_value","wait_cost","tier_cliff","adp_value")))) {
  fail("s5: default_decision_weights names wrong")
}
if (abs(sum(w5) - 1) > 1e-9) fail("s5: default weights do not sum to 1")

## lineup_value: known roster -> known best lineup.
rl5 <- data.frame(pos    = c("QB","RB","RB","RB","WR","WR","TE"),
                  points = c(380, 250, 210, 190, 300, 240, 180),
                  stringsAsFactors = FALSE)
lv5 <- lineup_value(rl5, cfg$league)   # points fallback: 380 + 460 + 540 + 180 + FLEX(190)
if (abs(lv5 - 1750) > 1e-6)           fail("s5: lineup_value (points fallback) != 1750, got ", lv5)
if (lineup_value(rl5[0, ], cfg$league) != 0) fail("s5: empty roster lineup_value != 0")
## vor is the value currency when present -- a huge `points` must not override it.
if (lineup_value(data.frame(pos = "RB", vor = 100, points = 9999), cfg$league) != 100) {
  fail("s5: lineup_value did not prefer vor over points")
}

## Snake slot-1 overalls -> the user's pick numbers.
s5_sched  <- make_snake_schedule(12L, 14L)
s5_slot1  <- s5_sched$overall[s5_sched$slot == 1L]
s5_worst  <- function(exclude_pos = character(0)) {
  p <- snap$players[order(snap$players$points, snap$players$player_id), ]
  p$player_id[!(p$pos %in% exclude_pos)]
}
## Build the full ordered id vector: user_ids at slot-1 overalls, `pool` fills
## every other overall up to the user's last pick.
s5_ids <- function(user_ids, pool) {
  n_total <- if (length(user_ids)) s5_slot1[length(user_ids)] else 0L
  ids     <- character(n_total)
  at      <- s5_slot1[seq_along(user_ids)]
  ids[at] <- user_ids
  gaps    <- setdiff(seq_len(n_total), at)
  pool    <- setdiff(pool, user_ids)
  if (length(gaps) > length(pool)) fail("s5: filler pool too small")
  ids[gaps] <- pool[seq_along(gaps)]
  ids
}
s5_state <- function(user_ids, pool = s5_worst()) {
  st <- new_draft(snap, team_order, "Team 01", league = cfg$league)
  ids <- s5_ids(user_ids, pool)
  if (length(ids)) {
    st$picks <- data.frame(
      overall    = seq_along(ids),
      player_id  = as.character(ids),
      entered_at = as.POSIXct("2026-09-01 12:00:00", tz = "UTC") + seq_along(ids),
      stringsAsFactors = FALSE
    )
  }
  st
}
valid_labels <- c("TAKE NOW","ROSTER NEED","TIER CLIFF","BEST VALUE","CAN WAIT")

## (a) Empty roster, user on the clock.
st0 <- new_draft(snap, team_order, "Team 01", league = cfg$league)
r0  <- recommend_players(st0, snap)
if (!identical(names(r0), .warroom_rec_columns)) fail("s5: result columns/order wrong")
if (nrow(r0) != 10L)                        fail("s5: expected 10 recommendations, got ", nrow(r0))
if (any(r0$pos %in% c("K","DST")))          fail("s5: K/DST recommended in round 1")
if (!all(r0$label %in% valid_labels))       fail("s5: unknown label: ", paste(setdiff(r0$label, valid_labels), collapse = ", "))
if (!all(is.finite(r0$p_next) & r0$p_next >= 0 & r0$p_next <= 1)) fail("s5: p_next not finite in [0,1] with adp present")
if (!all(is.finite(r0$wait_cost) & r0$wait_cost >= 0))           fail("s5: wait_cost not finite and >= 0 with adp present")
if (!(r0$pos[1] %in% c("RB","WR")))         fail("s5: top pick not RB/WR on an empty roster")
if (any(r0$player_id %in% st0$picks$player_id)) fail("s5: drafted player recommended")

## (b) Determinism.
if (!identical(r0, recommend_players(st0, snap))) fail("s5: two calls not identical")

## (c) QB2 penalty: user holds 1 QB, all other starters open. A penalized second
## QB drops out of the top 10 entirely; widen n to inspect the reason string.
stq    <- s5_state(c("SYN-QB-001"))
rq_top <- recommend_players(stq, snap)
rq_all <- recommend_players(stq, snap, n = 400L)
qbr    <- rq_all[rq_all$pos == "QB", ]
if (nrow(qbr) == 0L)                         fail("s5: no QB candidate to check QB2")
if (!any(grepl("QB2", qbr$reason)))          fail("s5: QB2 penalty not explained")
if (any(rq_top$pos == "QB"))                 fail("s5: penalized QB2 still in top 10")

## (d) TE2 penalty (smaller than QB2): user holds 1 TE, other starters open.
stt <- s5_state(c("SYN-TE-001"))
ter <- recommend_players(stt, snap, n = 400L)
ter <- ter[ter$pos == "TE", ]
if (nrow(ter) == 0L || !any(grepl("TE2", ter$reason))) fail("s5: TE2 penalty not explained")

## (e) K/DST excluded well before the final rounds (mid draft, no squeeze).
rm5 <- recommend_players(s5_state(c("SYN-WR-001","SYN-RB-001","SYN-WR-002")), snap)
if (any(rm5$pos %in% c("K","DST")))          fail("s5: K/DST recommended mid draft")

## (f) K/DST forced + strand guard: 12-man roster, 2 picks left, only K & DST needed.
roster12 <- c("SYN-QB-001","SYN-RB-001","SYN-RB-002","SYN-WR-001","SYN-WR-002",
              "SYN-TE-001","SYN-RB-003","SYN-RB-004","SYN-RB-005","SYN-WR-003",
              "SYN-WR-004","SYN-TE-002")
rf5 <- recommend_players(s5_state(roster12, pool = s5_worst(c("K","DST"))), snap)
if (nrow(rf5) == 0L)                         fail("s5: no recommendations when K/DST forced")
if (!all(rf5$pos %in% c("K","DST")))         fail("s5: non-mandatory (bench) candidate not stranded out")
if (!any(rf5$label %in% c("ROSTER NEED","TAKE NOW"))) fail("s5: forced K/DST not labelled a roster need")

## (g) Tier cliff: user has RB/WR/FLEX filled; opponents take RB 04-05, leaving
## only RB 06 in tier 1.
cliff_pool <- c("SYN-RB-004","SYN-RB-005", s5_worst(c("K","DST")))
rc5 <- recommend_players(
  s5_state(c("SYN-RB-001","SYN-RB-002","SYN-WR-001","SYN-WR-002","SYN-RB-003"),
           pool = cliff_pool), snap, n = 40L)
rb6 <- rc5[rc5$player_id == "SYN-RB-006", ]
if (nrow(rb6) != 1L)                          fail("s5: last-in-tier RB not in the ranking")
if (rb6$label != "TIER CLIFF" && !grepl("tier", rb6$reason)) {
  fail("s5: last-in-tier RB neither labelled TIER CLIFF nor explained by tier")
}
if (!("TIER CLIFF" %in% rc5$label))          fail("s5: no TIER CLIFF label in a thin-tier scenario")

## (h) BEST VALUE: deep into the draft, top players fell well past ADP.
deep_user <- c("SYN-QB-001","SYN-WR-001","SYN-RB-001")
rbv <- recommend_players(s5_state(deep_user, pool = s5_worst()), snap)
if (!("BEST VALUE" %in% rbv$label))          fail("s5: no BEST VALUE label deep in the draft")
if (any(rbv$adp_value[rbv$label == "BEST VALUE"] < 8)) fail("s5: BEST VALUE with adp_value < 8")

## (i) Draft complete -> zero-row frame with the full column set.
full5 <- s5_state(NULL)
full5$picks <- data.frame(
  overall    = 1:168,
  player_id  = snap$players$player_id[1:168],
  entered_at = as.POSIXct("2026-09-01 12:00:00", tz = "UTC") + 1:168,
  stringsAsFactors = FALSE
)
rcomp <- recommend_players(full5, snap)
if (nrow(rcomp) != 0L)                       fail("s5: completed draft returned rows")
if (!identical(names(rcomp), .warroom_rec_columns)) fail("s5: empty result columns wrong")
if (!identical(vapply(rcomp, class, ""), vapply(r0, class, ""))) {
  fail("s5: empty result column types differ from a populated result")
}

## (j) Snapshot without an adp column -> adp NA, adp_value 0, no crash.
snap_noadp <- snap
snap_noadp$players$adp    <- NULL
snap_noadp$players$adp_sd <- NULL
rna <- recommend_players(st0, snap_noadp)
if (nrow(rna) == 0L)                         fail("s5: no recs without adp column")
if (!all(is.na(rna$adp)) || !all(rna$adp_value == 0)) fail("s5: adp fallback wrong")

## (k) n caps the result; n larger than the eligible set returns fewer rows.
r3 <- recommend_players(st0, snap, n = 3L)
if (nrow(r3) != 3L)                          fail("s5: n = 3 did not cap the result")
## 13-man roster needing only DST, 1 pick left, and 22 of 24 DSTs already gone:
## the strand + squeeze filters leave exactly 2 eligible players.
roster13 <- c("SYN-QB-001","SYN-RB-001","SYN-RB-002","SYN-WR-001","SYN-WR-002",
              "SYN-TE-001","SYN-RB-003","SYN-K-001","SYN-RB-004","SYN-RB-005",
              "SYN-WR-003","SYN-WR-004","SYN-TE-002")
dst_gone  <- sprintf("SYN-DST-%03d", 1:22)
r_few <- recommend_players(
  s5_state(roster13, pool = c(dst_gone, s5_worst(c("K","DST")))), snap, n = 10L)
if (nrow(r_few) != 2L)                       fail("s5: n > eligible not honored, got ", nrow(r_few))
if (!all(r_few$pos == "DST"))                fail("s5: squeeze left a non-DST candidate")

## (l) /rec in the terminal renders the real table (label + score).
s5t_path <- file.path(tempdir(), "warroom-s5t", "draft.rds")
unlink(dirname(s5t_path), recursive = TRUE)
o5t <- s4_run(c(team_line, "/rec", "/quit"), state_path = s5t_path)
if (!has(o5t, "recomendacoes (top"))         fail("s5: /rec header missing")
if (!any(grepl("score", o5t, fixed = TRUE))) fail("s5: /rec output has no score column")
if (!any(vapply(valid_labels, function(l) any(grepl(l, o5t, fixed = TRUE)), logical(1)))) {
  fail("s5: /rec output shows no label")
}
unlink(dirname(s5t_path), recursive = TRUE)

cat("story 5 offline checks OK -- lineup value + marginal roster value + guardrails + labels\n")

## --- story 6: market-aware wait intelligence (offline) -----------------
## p_next / wait_cost / four-term decision_score. Pure, offline, deterministic,
## no Monte Carlo. Reuses snap, team_order, cfg, fail, s4_run, team_line, has,
## s5_state, st0, snap_noadp, full5 from the story-5 scope. tempdir() only.

## (6a) Pick pessoal, snapshot com adp: p_next in [0,1], wait_cost >= 0 finite,
## and deterministic across two calls (p_next + wait_cost + decision_score).
s6_r0 <- recommend_players(st0, snap, n = 400L)
if (!all(is.finite(s6_r0$p_next) & s6_r0$p_next >= 0 & s6_r0$p_next <= 1)) {
  fail("s6: p_next not finite in [0,1] on an empty roster with adp present")
}
if (any(is.nan(s6_r0$p_next)) || any(is.infinite(s6_r0$p_next))) fail("s6: p_next NaN/Inf")
if (!all(is.finite(s6_r0$wait_cost) & s6_r0$wait_cost >= 0)) fail("s6: wait_cost not finite >= 0")
if (any(is.nan(s6_r0$wait_cost)) || any(is.infinite(s6_r0$wait_cost))) fail("s6: wait_cost NaN/Inf")
if (!identical(s6_r0, recommend_players(st0, snap, n = 400L))) {
  fail("s6: two calls not identical (p_next / wait_cost / order)")
}

## (6b) Monotonicity: within a position, a low-adp player is less likely to
## survive to the following pick than a high-adp one.
s6_rb  <- s6_r0[s6_r0$pos == "RB" & is.finite(s6_r0$adp), ]
if (nrow(s6_rb) < 2L) fail("s6: not enough RB rows to check p_next monotonicity")
s6_lo  <- s6_rb[which.min(s6_rb$adp), ]
s6_hi  <- s6_rb[which.max(s6_rb$adp), ]
if (!(s6_lo$p_next < s6_hi$p_next)) {
  fail("s6: low-adp RB p_next not below high-adp RB p_next")
}

## (6c) Numerical stability far beyond adp: SYN-RB-001 (adp ~2) is still on the
## board at pick 1 -- both tails are ~1e-8, the log-space ratio must stay finite.
s6_r1 <- s6_r0[s6_r0$player_id == "SYN-RB-001", ]
if (nrow(s6_r1) != 1L) fail("s6: SYN-RB-001 missing from the pick-1 board")
if (!is.finite(s6_r1$p_next) || s6_r1$p_next < 0 || s6_r1$p_next > 1) {
  fail("s6: SYN-RB-001 p_next not finite in [0,1]")
}
if (!any(grepl("p_next", s6_r0$reason)))       fail("s6: no reason names a low p_next")
if (!any(grepl("custo de esperar", s6_r0$reason))) fail("s6: no reason names a wait cost")

## (6d) Position drying: nearly every available RB has adp far below the
## following pick -> high wait_cost on the RB candidate and, at rank 1 with a
## high score, the TAKE NOW label; w_wait then changes the ordering.
dry_pool <- c(sprintf("SYN-WR-%03d", 10:72), s5_worst(c("K", "DST")))
st_dry   <- s5_state(c("SYN-RB-001", "SYN-RB-002", "SYN-QB-001",
                       "SYN-TE-001", "SYN-RB-003", "SYN-RB-004"), pool = dry_pool)
r_dry    <- recommend_players(st_dry, snap, n = 15L)
wr_dry   <- r_dry[r_dry$pos == "WR", ]
if (nrow(wr_dry) == 0L)                         fail("s6: no WR candidate in the drying scenario")
if (max(wr_dry$wait_cost, na.rm = TRUE) < 5)    fail("s6: drying position did not raise wait_cost")
if (r_dry$label[1] != "TAKE NOW" && !("TAKE NOW" %in% r_dry$label)) {
  fail("s6: drying position did not yield a TAKE NOW label")
}
w_nowait <- default_decision_weights(); w_nowait["wait_cost"] <- 0
r_nowait <- recommend_players(st_dry, snap, weights = w_nowait, n = 15L)
if (identical(r_dry$player_id, r_nowait$player_id)) {
  fail("s6: w_wait = 0 did not change the ordering when a position is drying")
}

## (6e) Deep position: many survivors with high p_next -> some low wait_cost
## candidates and a CAN WAIT label on the pick-1 board.
if (!any(s6_r0$wait_cost < 5))                  fail("s6: no low-wait_cost candidate on a deep board")
if (!("CAN WAIT" %in% s6_r0$label))             fail("s6: no CAN WAIT label on a deep board")
if (!any(s6_r0$p_next >= .warroom_can_wait_pnext)) fail("s6: no comfortably-surviving candidate on a deep board")

## (6f) Snapshot without an adp column: p_next / wait_cost all NA, score still
## finite and non-negative (three terms, no special case).
r_noadp6 <- recommend_players(st0, snap_noadp)
if (!all(is.na(r_noadp6$p_next)) || !all(is.na(r_noadp6$wait_cost))) {
  fail("s6: p_next / wait_cost not all NA without an adp column")
}
if (!all(is.finite(r_noadp6$decision_score) & r_noadp6$decision_score >= 0)) {
  fail("s6: decision_score not finite / non-negative without adp")
}

## (6g) No following user pick: state at the very last overall (pick 168), the
## user on the clock, no pick after it -> p_next / wait_cost NA, score finite.
s6_last  <- new_draft(snap, team_order, "Team 01", league = cfg$league)
s6_sched <- make_snake_schedule(12L, 14L)
s6_u13   <- c("SYN-QB-001", "SYN-RB-001", "SYN-RB-002", "SYN-WR-001", "SYN-WR-002",
              "SYN-TE-001", "SYN-RB-003", "SYN-K-001", "SYN-DST-001",
              "SYN-QB-002", "SYN-WR-003", "SYN-RB-004", "SYN-TE-002")
s6_slot1 <- s6_sched$overall[s6_sched$slot == 1L]
s6_slot1 <- s6_slot1[s6_slot1 <= 167L]                    # 13 user overalls in 1..167
if (length(s6_slot1) != length(s6_u13)) fail("s6: slot-1 overall count != 13")
s6_others <- setdiff(snap$players$player_id, s6_u13)
s6_ids    <- character(167L)
s6_ids[s6_slot1] <- s6_u13
s6_ids[setdiff(1:167, s6_slot1)] <- s6_others[seq_len(167L - length(s6_slot1))]
s6_last$picks <- data.frame(
  overall = 1:167, player_id = s6_ids,
  entered_at = as.POSIXct("2026-09-01 12:00:00", tz = "UTC") + 1:167,
  stringsAsFactors = FALSE)
s6_vlast <- derive_draft_view(s6_last, snap)
if (!identical(s6_vlast$current_overall, 168L))  fail("s6: last-pick state not at overall 168")
if (!identical(s6_vlast$team_on_clock, "Team 01")) fail("s6: user not on the clock at overall 168")
if (!is.na(.warroom_following_user_pick(s6_last, 168L))) fail("s6: following pick not NA at the last overall")
r_last <- recommend_players(s6_last, snap)
if (nrow(r_last) == 0L)                          fail("s6: no recs at the user's final pick")
if (!all(is.na(r_last$p_next)) || !all(is.na(r_last$wait_cost))) {
  fail("s6: p_next / wait_cost not NA when the user has no pick after this one")
}
if (!all(is.finite(r_last$decision_score)))      fail("s6: decision_score not finite at the final pick")

## (6h) Per-player adp NA: those candidates get p_next / wait_cost NA; others,
## with a real adp, are still computed.
snap_pna <- snap
s6_na_id <- c("SYN-WR-005", "SYN-WR-006")
snap_pna$players$adp[snap_pna$players$player_id %in% s6_na_id] <- NA_real_
r_pna <- recommend_players(st0, snap_pna, n = 400L)
if (!all(r_pna$player_id %in% s6_na_id | is.finite(r_pna$p_next))) {
  fail("s6: a candidate with a real adp still has NA p_next")
}
if (!all(is.na(r_pna$p_next[r_pna$player_id %in% s6_na_id]))) {
  fail("s6: an adp-NA candidate has a non-NA p_next")
}
if (!all(is.na(r_pna$wait_cost[r_pna$player_id %in% s6_na_id]))) {
  fail("s6: an adp-NA candidate has a non-NA wait_cost")
}

## (6i) Draft complete -> zero-row frame with the full column set (full5 from s5).
if (nrow(recommend_players(full5, snap)) != 0L)  fail("s6: completed draft returned rows")

## (6j) /rec in the terminal shows p_next and wait alongside score / label.
s6t_path <- file.path(tempdir(), "warroom-s6t", "draft.rds")
unlink(dirname(s6t_path), recursive = TRUE)
o6t <- s4_run(c(team_line, "/rec", "/quit"), state_path = s6t_path)
if (!has(o6t, "recomendacoes (top"))            fail("s6: /rec header missing")
if (!has(o6t, "p_next"))                         fail("s6: /rec output has no p_next")
if (!has(o6t, "wait "))                          fail("s6: /rec output has no wait column")
unlink(dirname(s6t_path), recursive = TRUE)

## (6k) No RNG / Monte Carlo / network markers in the recommendation source.
s6_src <- readLines(.warroom_find_file("R/recommendation.R"), warn = FALSE)
if (any(grepl("monte|rnorm|runif|\\bsample\\(|replicate|\\bboot\\b", s6_src))) {
  fail("s6: recommendation.R names an RNG / Monte Carlo symbol")
}
if (any(grepl("shiny|http[s]?://|readRDS|saveRDS|scrape", s6_src))) {
  fail("s6: recommendation.R names a shiny / network / file-IO symbol")
}

cat("story 6 offline checks OK -- p_next + expected_best_next + wait_cost + four-term score\n")

## --- story 7: mock simulator and calibration (offline) -------------------
## opponent_pick / simulate_draft / compare_strategies / calibrate_weights.
## Reuses snap, team_order, cfg, fail, expect_error from the earlier scope.
## No network; deterministic seeds only. Covers the story-7 I/O matrix.

## (7a) opponent_pick(): the returned player_id is always a row of `available`
## (never a re-draft, since `available` excludes drafted players by construction).
s7_root <- new_draft(snap, team_order, "Team 01", league = cfg$league)
s7_view <- derive_draft_view(s7_root, snap)
s7_mv   <- .warroom_market_value(snap$players, seed = 1L)
if (is.null(names(s7_mv)) || length(s7_mv) != nrow(snap$players)) {
  fail("s7: .warroom_market_value did not return a fully named vector")
}
op1 <- opponent_pick(s7_view$available, s7_view$rosters[["Team 02"]], cfg$league, s7_mv)
if (!(op1 %in% s7_view$available$player_id)) {
  fail("s7: opponent_pick returned a player not in `available`")
}
expect_error(opponent_pick(s7_view$available[0, , drop = FALSE], NULL, cfg$league, s7_mv),
            "opponent_pick: no eligible candidate")

## (7b) Full simulated draft, "warroom" strategy: 168 picks, no duplicate,
## every one of the 12 rosters valid (14 players, no mandatory slot empty).
sim_w <- simulate_draft(snap, team_order, "Team 01", seed = 1L, strategy = "warroom",
                        league = cfg$league)
if (nrow(sim_w$state$picks) != 168L) {
  fail("s7: warroom sim did not complete 168 picks, got ", nrow(sim_w$state$picks))
}
if (anyDuplicated(sim_w$state$picks$player_id)) fail("s7: warroom sim drafted a duplicate player")
if (!identical(names(sim_w$rosters_valid), team_order)) fail("s7: rosters_valid not named by team_order")
if (!all(sim_w$rosters_valid)) {
  fail("s7: warroom sim left invalid roster(s): ",
       paste(names(sim_w$rosters_valid)[!sim_w$rosters_valid], collapse = ", "))
}
for (tm in team_order) {
  r <- derive_draft_view(sim_w$state, snap)$rosters[[tm]]
  if (nrow(r) != 14L) fail("s7: ", tm, " does not have 14 players, got ", nrow(r))
  if (.warroom_unfilled_mandatory(r, cfg$league)$total != 0L) {
    fail("s7: ", tm, " has an unfilled mandatory slot")
  }
}

## (7c) Determinism: two identical calls -> identical() state and metrics.
sim_w2 <- simulate_draft(snap, team_order, "Team 01", seed = 1L, strategy = "warroom",
                         league = cfg$league)
if (!identical(sim_w$state, sim_w2$state))     fail("s7: two simulate_draft() calls produced different state")
if (!identical(sim_w$metrics, sim_w2$metrics)) fail("s7: two simulate_draft() calls produced different metrics")

## (7c2) Different seeds must produce different outcomes -- guards against a
## regression where .warroom_market_value() silently ignores `seed`.
sim_w_seed2 <- simulate_draft(snap, team_order, "Team 01", seed = 2L, strategy = "warroom",
                              league = cfg$league)
if (identical(sim_w$state$picks$player_id, sim_w_seed2$state$picks$player_id)) {
  fail("s7: seed 1 and seed 2 produced identical simulate_draft() outcomes")
}

## (7c3) .warroom_sim_starter_ids() cross-check: the starter set it picks for
## sim_w's user roster must sum (vor if present else points, matching
## .warroom_value_of()) to the same value lineup_value() reports for that
## roster. Guards against the two independent "who starts" selections drifting.
sim_w_roster      <- derive_draft_view(sim_w$state, snap)$rosters[["Team 01"]]
sim_w_starter_ids <- .warroom_sim_starter_ids(sim_w_roster, cfg$league)
sim_w_starter_val <- sum(.warroom_value_of(sim_w_roster)[sim_w_roster$player_id %in% sim_w_starter_ids])
sim_w_lineup_val  <- lineup_value(sim_w_roster, cfg$league)
if (abs(sim_w_starter_val - sim_w_lineup_val) > 1e-6) {
  fail("s7: .warroom_sim_starter_ids() value sum (", sim_w_starter_val,
       ") does not match lineup_value() (", sim_w_lineup_val, ")")
}

## (7d) adp / vor strategies also complete 168 picks with valid rosters.
sim_a <- simulate_draft(snap, team_order, "Team 01", seed = 1L, strategy = "adp", league = cfg$league)
sim_v <- simulate_draft(snap, team_order, "Team 01", seed = 1L, strategy = "vor", league = cfg$league)
if (nrow(sim_a$state$picks) != 168L) fail("s7: adp sim did not complete 168 picks")
if (nrow(sim_v$state$picks) != 168L) fail("s7: vor sim did not complete 168 picks")
if (anyDuplicated(sim_a$state$picks$player_id)) fail("s7: adp sim drafted a duplicate player")
if (anyDuplicated(sim_v$state$picks$player_id)) fail("s7: vor sim drafted a duplicate player")
if (!all(sim_a$rosters_valid)) fail("s7: adp sim left an invalid roster")
if (!all(sim_v$rosters_valid)) fail("s7: vor sim left an invalid roster")

## (7e) RNG isolation: simulate_draft() never leaks .Random.seed to the caller.
set.seed(42L)
rs_before <- get(".Random.seed", envir = .GlobalEnv)
invisible(simulate_draft(snap, team_order, "Team 01", seed = 2L, strategy = "adp",
                         league = cfg$league))
rs_after <- get(".Random.seed", envir = .GlobalEnv)
if (!identical(rs_before, rs_after)) fail("s7: simulate_draft() leaked RNG state to the caller")

## (7f) Three-strategy comparison, same seed (same market draw -- fair
## comparison): 3 rows, every documented metric column, all_rosters_valid logical.
cmp7 <- compare_strategies(snap, team_order, "Team 01", seed = 1L,
                           weights = default_decision_weights())
if (nrow(cmp7) != 3L) fail("s7: compare_strategies did not return 3 rows, got ", nrow(cmp7))
if (!setequal(cmp7$strategy, c("adp", "vor", "warroom"))) {
  fail("s7: compare_strategies strategy column wrong: ", paste(cmp7$strategy, collapse = ", "))
}
cmp7_cols <- c("strategy", "starter_points", "starter_vor", "bench_vor",
              "n_QB", "n_RB", "n_WR", "n_TE", "n_K", "n_DST",
              "adp_surplus", "reach_count", "roster_valid", "qb_round", "te_round",
              "all_rosters_valid")
if (!all(cmp7_cols %in% names(cmp7))) {
  fail("s7: compare_strategies missing column(s): ",
       paste(setdiff(cmp7_cols, names(cmp7)), collapse = ", "))
}
if (!is.logical(cmp7$all_rosters_valid)) fail("s7: all_rosters_valid not logical")
if (!all(is.finite(cmp7$starter_vor)))   fail("s7: starter_vor not finite for every strategy")

## (7g) Strand guard: 12-man roster missing only K + DST, 2 picks remaining,
## round deliberately early (5) -- the K/DST grace-round rule alone would
## exclude them, but the strand guard must still admit exactly K/DST.
roster12_ids <- c("SYN-QB-001","SYN-RB-001","SYN-RB-002","SYN-WR-001","SYN-WR-002",
                  "SYN-TE-001","SYN-RB-003","SYN-RB-004","SYN-RB-005","SYN-WR-003",
                  "SYN-WR-004","SYN-TE-002")
roster12_s7 <- snap$players[snap$players$player_id %in% roster12_ids, , drop = FALSE]
avail_s7    <- snap$players[!(snap$players$player_id %in% roster12_ids), , drop = FALSE]
elig7 <- .warroom_eligible_sim_candidates(avail_s7, roster12_s7, cfg$league, round_on_clock = 5L)
if (nrow(elig7) == 0L)                    fail("s7: strand guard left no eligible K/DST candidate")
if (!all(elig7$pos %in% c("K", "DST")))   fail("s7: strand guard did not restrict to K/DST")
op7 <- opponent_pick(avail_s7, roster12_s7, cfg$league,
                     .warroom_market_value(snap$players, seed = 1L))
pl7 <- snap$players$pos[snap$players$player_id == op7]
if (!(pl7 %in% c("K", "DST"))) fail("s7: opponent_pick ignored the strand guard, picked ", pl7)

## Positional cap, isolated from the strand guard: a bigger league (more
## rounds) so 8 RBs is not yet mandatory-tight; RB (at its cap) must be
## excluded while WR (under its cap) and K/DST (round too early, not tight)
## behave as expected.
cap_league <- cfg$league
cap_league$rounds <- 20L
roster_cap_ids <- c("SYN-QB-001", "SYN-WR-001", "SYN-WR-002", "SYN-TE-001",
                    sprintf("SYN-RB-%03d", 1:8))
roster_cap <- snap$players[snap$players$player_id %in% roster_cap_ids, , drop = FALSE]
avail_cap  <- snap$players[!(snap$players$player_id %in% roster_cap_ids), , drop = FALSE]
elig_cap   <- .warroom_eligible_sim_candidates(avail_cap, roster_cap, cap_league,
                                               round_on_clock = 9L)
if (any(elig_cap$pos == "RB"))            fail("s7: positional cap did not exclude RB at its cap")
if (!any(elig_cap$pos == "WR"))           fail("s7: positional cap wrongly excluded WR under its cap")
if (any(elig_cap$pos %in% c("K", "DST"))) fail("s7: K/DST offered before the grace rounds without a strand")

## (7h) default_weight_grid(): every row sums to 1, no negative adp_value.
wg7 <- default_weight_grid()
if (nrow(wg7) == 0L) fail("s7: default_weight_grid produced no rows")
if (!all(c("roster_value","wait_cost","tier_cliff","adp_value") %in% names(wg7))) {
  fail("s7: default_weight_grid missing weight column(s)")
}
if (any(wg7$adp_value < 0)) fail("s7: default_weight_grid kept a negative-adp_value row")
wg7_sums <- wg7$roster_value + wg7$wait_cost + wg7$tier_cliff + wg7$adp_value
if (any(abs(wg7_sums - 1) > 1e-9)) fail("s7: default_weight_grid rows do not sum to 1")

## Exact hypothesis breakpoints (operations.md "Calibration") -- catches an
## accidental transposition of the grid's ranges.
if (!isTRUE(all.equal(sort(unique(wg7$roster_value)), c(0.40, 0.50, 0.60)))) {
  fail("s7: default_weight_grid roster_value breakpoints wrong: ",
       paste(sort(unique(wg7$roster_value)), collapse = ", "))
}
if (!isTRUE(all.equal(sort(unique(wg7$wait_cost)), c(0.20, 0.30, 0.40)))) {
  fail("s7: default_weight_grid wait_cost breakpoints wrong: ",
       paste(sort(unique(wg7$wait_cost)), collapse = ", "))
}
if (!isTRUE(all.equal(sort(unique(wg7$tier_cliff)), c(0.10, 0.15, 0.20)))) {
  fail("s7: default_weight_grid tier_cliff breakpoints wrong: ",
       paste(sort(unique(wg7$tier_cliff)), collapse = ", "))
}

## (7i) Calibration, minimal grid (2 rows, 1 seed, 1 slot): 2 rows, finite
## mean_fitness/risk_score, ordered by risk_score descending.
grid7 <- wg7[1:2, , drop = FALSE]
cal7  <- calibrate_weights(snap, team_order, seeds = 1L, slots = 1L, grid = grid7)
if (nrow(cal7) != 2L) fail("s7: calibrate_weights did not return 2 rows, got ", nrow(cal7))
if (!all(c("mean_fitness","sd_fitness","risk_score","all_valid") %in% names(cal7))) {
  fail("s7: calibrate_weights missing aggregate column(s)")
}
if (!all(is.finite(cal7$mean_fitness)) || !all(is.finite(cal7$risk_score))) {
  fail("s7: calibrate_weights produced non-finite mean_fitness/risk_score")
}
if (is.unsorted(rev(cal7$risk_score)))  fail("s7: calibrate_weights not ordered by risk_score descending")
if (!all(cal7$sd_fitness == 0))         fail("s7: single-run sd_fitness should be 0")

## (7i2) Multi-run aggregation across seeds x slots (2 grid rows, seeds = c(1,2),
## slots = c(1,6) -> 4 runs per row). The only other calibrate_weights() test
## above forces seeds = 1L, slots = 1L, so `fits` always has length 1 and the
## `fits <- c(fits, fit)` accumulation across the nested slot/seed loop is never
## actually exercised there. This guards a regression like `fits <- fit`
## (dropping accumulation) or an off-by-one in `team_order[[slot]]`.
cal7b <- calibrate_weights(snap, team_order, seeds = c(1L, 2L), slots = c(1L, 6L), grid = grid7)
if (nrow(cal7b) != 2L) fail("s7: calibrate_weights (multi-run) did not return 2 rows, got ", nrow(cal7b))
if (!all(is.finite(cal7b$sd_fitness)) || any(cal7b$sd_fitness < 0)) {
  fail("s7: calibrate_weights (multi-run) sd_fitness not finite / non-negative")
}
if (!all(is.finite(cal7b$mean_fitness))) fail("s7: calibrate_weights (multi-run) mean_fitness not finite")

## Independently recompute grid row 1's fitness across its 4 (slot, seed)
## combinations via direct simulate_draft() calls, and cross-check the manually
## computed mean against calibrate_weights()'s own mean_fitness for that row
## (rows are reordered by risk_score, so match on the weight columns).
manual_weights <- c(
  roster_value = grid7$roster_value[1],
  wait_cost    = grid7$wait_cost[1],
  tier_cliff   = grid7$tier_cliff[1],
  adp_value    = grid7$adp_value[1]
)
manual_fits <- numeric(0)
for (slot in c(1L, 6L)) {
  for (sd in c(1L, 2L)) {
    res_m <- simulate_draft(snap, team_order, team_order[[slot]], seed = sd,
                            strategy = "warroom", weights = manual_weights)
    m <- res_m$metrics
    fit_m <- m$starter_vor +
      .warroom_calib_bench_frac * m$bench_vor +
      .warroom_calib_adp_frac   * m$adp_surplus -
      .warroom_calib_invalid_penalty * (!isTRUE(m$roster_valid))
    manual_fits <- c(manual_fits, fit_m)
  }
}
row1_idx <- which(abs(cal7b$roster_value - grid7$roster_value[1]) < 1e-9 &
                  abs(cal7b$wait_cost   - grid7$wait_cost[1])   < 1e-9 &
                  abs(cal7b$tier_cliff  - grid7$tier_cliff[1])  < 1e-9)
if (length(row1_idx) != 1L) fail("s7: could not locate grid row 1 in calibrate_weights() (multi-run) output")
if (abs(mean(manual_fits) - cal7b$mean_fitness[row1_idx]) > 1e-6) {
  fail("s7: manually recomputed mean_fitness (", mean(manual_fits),
       ") does not match calibrate_weights() mean_fitness (",
       cal7b$mean_fitness[row1_idx], ") for grid row 1")
}

## (7j) make simulate: scripts/simulate.R's default (reduced) path exits 0
## and prints the three strategies.
sim_script_out <- tryCatch(
  system2("Rscript", c("scripts/simulate.R"), stdout = TRUE, stderr = TRUE),
  error = function(e) fail("s7: could not run scripts/simulate.R: ", conditionMessage(e))
)
sim_script_status <- attr(sim_script_out, "status")
if (!is.null(sim_script_status) && sim_script_status != 0L) {
  fail("s7: scripts/simulate.R (default) exited ", sim_script_status, ": ",
       paste(utils::tail(sim_script_out, 20L), collapse = "\n"))
}
if (!any(grepl("warroom", sim_script_out, fixed = TRUE))) {
  fail("s7: scripts/simulate.R output does not mention the warroom strategy")
}

## (7k) No RNG / genetic-algorithm markers outside simulation.R: recommend_players()
## and simulate.R stay purely analytic / grid-search (SPEC "Non-goals", AGENTS.md).
s7_rec_src <- readLines(.warroom_find_file("R/recommendation.R"), warn = FALSE)
if (any(grepl("monte|rnorm|runif|\\bsample\\(|genetic|\\bGA\\b", s7_rec_src))) {
  fail("s7: recommendation.R names an RNG / genetic-algorithm symbol")
}
s7_sim_src <- readLines(.warroom_find_file("R/simulation.R"), warn = FALSE)
if (any(grepl("genetic|evolution|GA\\(", s7_sim_src))) {
  fail("s7: simulation.R names a genetic/evolutionary optimizer symbol")
}

cat("story 7 offline checks OK -- opponent_pick + simulate_draft + compare_strategies + calibrate_weights\n")

## --- story 8: thin Shiny war room (offline) ------------------------------
## Drive app.R's server() via shiny::testServer(), covering every row of the
## story-8 I/O & Edge-Case matrix, plus roster_slots() unit checks and the
## static-analysis acceptance criteria (no redefinitions, no pnorm/rnorm/
## runif, no network). Reuses snap, team_order, cfg, fail, expect_error from
## the earlier scope. tempdir() only, no network.

source("app.R")   # defines ui, server, %||%, .warroom_app_config()
if (!is.function(server)) fail("s8: app.R did not define server() as a function")
app_obj <- shiny::shinyApp(ui, server)
if (!inherits(app_obj, "shiny.appobj")) fail("s8: shinyApp(ui, server) did not return a shiny.appobj")

## server()'s signature must match run_draft()'s dependency-injection pattern
## (Boundaries & Constraints).
if (!identical(names(formals(server)),
               c("input", "output", "session", "snapshot", "state_path", "config"))) {
  fail("s8: server() formals do not match the injectable signature")
}

## shiny::testServer() (this shiny version) only forwards `args` to a MODULE
## server (first formal named "id"); a plain server function like ours makes
## it stop with "Arguments were provided to a server function." Bake
## snapshot/state_path/config in as literal formal defaults instead -- same
## tempdir()-fixture guarantee (data/ and state/ are never touched), just
## supplied a different way.
.s8_bake_server <- function(snapshot, state_path, config) {
  srv <- server
  formals(srv)$snapshot   <- snapshot
  formals(srv)$state_path <- state_path
  formals(srv)$config     <- config
  srv
}

## (8a) No state/draft.rds -> new_draft() with default team_order / config
## user_team, saved immediately; banner shows R01 overall 1.
s8a_path <- file.path(tempdir(), "warroom-s8a", "draft.rds")
unlink(dirname(s8a_path), recursive = TRUE)
shiny::testServer(.s8_bake_server(snap, s8a_path, cfg), {
  b <- output$banner
  if (!grepl("R01", b, fixed = TRUE) || !grepl("overall 1", b, fixed = TRUE)) {
    fail("s8: new-draft banner wrong: ", b)
  }
})
if (!file.exists(s8a_path)) fail("s8: new draft not saved on first load")
d8a <- load_state(s8a_path)
if (nrow(d8a$picks) != 0L) fail("s8: fresh state should have 0 picks")
if (!identical(d8a$user_team, cfg$user_team)) fail("s8: user_team not taken from config.R")
if (!identical(d8a$team_order, sprintf("Team %02d", seq_len(cfg$league$teams)))) {
  fail("s8: team_order not the default 'Team NN' sequence")
}

## (8b) Existing state/draft.rds -> load_state() used; banner reflects
## derive_draft_view().
s8b_path <- file.path(tempdir(), "warroom-s8b", "draft.rds")
unlink(dirname(s8b_path), recursive = TRUE)
pre <- new_draft(snap, team_order, "Team 01", league = cfg$league)
pre <- record_pick(pre, snap$players$player_id[1], snap)
pre <- record_pick(pre, snap$players$player_id[2], snap)
save_state(pre, s8b_path)
shiny::testServer(.s8_bake_server(snap, s8b_path, cfg), {
  if (!identical(state()$picks, pre$picks)) {
    fail("s8: resumed state picks differ from the pre-existing file")
  }
  v <- derive_draft_view(state(), snap)
  if (!identical(v$current_overall, 3L)) fail("s8: resumed view current_overall wrong")
  b <- output$banner
  if (!grepl("overall 3", b, fixed = TRUE)) {
    fail("s8: resumed banner does not reflect derive_draft_view(): ", b)
  }
})

## (8c) Draft a player via input$draft_btn -> record_pick() + save_state();
## player disappears from view()$available; server reactive recommendation
## order is identical() to the direct terminal call (equivalence row).
s8c_path <- file.path(tempdir(), "warroom-s8c", "draft.rds")
unlink(dirname(s8c_path), recursive = TRUE)
shiny::testServer(.s8_bake_server(snap, s8c_path, cfg), {
  term_rec <- recommend_players(state(), snap)
  if (!identical(recs()$player_id, term_rec$player_id)) {
    fail("s8: server reactive recommendation order differs from recommend_players()")
  }
  if (!identical(recs(), term_rec)) {
    fail("s8: server reactive recommendation values differ from recommend_players()")
  }
  pid <- view()$available$player_id[1]
  session$setInputs(player_choice = pid)
  session$setInputs(draft_btn = 1)
  if (nrow(state()$picks) != 1L)          fail("s8: draft_btn did not record a pick")
  if (state()$picks$player_id[1] != pid)  fail("s8: draft_btn recorded the wrong player")
  if (pid %in% view()$available$player_id) fail("s8: drafted player still shows as available")

  ## record_pick() rejects a re-draft of the same player -> showNotification,
  ## state unchanged (no crash of the reactive session).
  session$setInputs(player_choice = pid)
  session$setInputs(draft_btn = 2)
  if (nrow(state()$picks) != 1L) fail("s8: rejected re-draft changed the pick count")
})
d8c <- load_state(s8c_path)   # accepted pick persisted outside the session
if (nrow(d8c$picks) != 1L) fail("s8: pick registered via draft_btn not persisted to disk")

## (8d) Undo with no picks -> undo_pick() error caught, state unchanged. Undo
## with a pick -> removed, player back in available, persisted.
s8d_path <- file.path(tempdir(), "warroom-s8d", "draft.rds")
unlink(dirname(s8d_path), recursive = TRUE)
shiny::testServer(.s8_bake_server(snap, s8d_path, cfg), {
  before <- state()
  session$setInputs(undo_btn = 1)   # no picks yet
  if (!identical(state()$picks, before$picks)) {
    fail("s8: undo_btn on an empty draft changed state")
  }

  pid <- view()$available$player_id[1]
  session$setInputs(player_choice = pid)
  session$setInputs(draft_btn = 1)
  if (nrow(state()$picks) != 1L) fail("s8: setup pick before undo failed")

  session$setInputs(undo_btn = 2)
  if (nrow(state()$picks) != 0L) fail("s8: undo_btn did not remove the pick")
  if (!(pid %in% view()$available$player_id)) fail("s8: undone player not back in available")
})
d8d <- load_state(s8d_path)
if (nrow(d8d$picks) != 0L) fail("s8: undo not persisted (state file still has the undone pick)")

## (8e) Equivalence rehearsal, mid-draft roster: same state/draft.rds +
## snapshot, terminal recommend_players() vs the server's reactive ->
## identical() player_id order (and full frame).
s8e_path <- file.path(tempdir(), "warroom-s8e", "draft.rds")
unlink(dirname(s8e_path), recursive = TRUE)
mid8 <- new_draft(snap, team_order, "Team 01", league = cfg$league)
for (i in 1:15) mid8 <- record_pick(mid8, snap$players$player_id[i], snap)
save_state(mid8, s8e_path)
term_mid_rec  <- recommend_players(mid8, snap)
mid8_view     <- derive_draft_view(mid8, snap)
mid8_roster   <- mid8_view$rosters[["Team 01"]]
mid8_slots    <- roster_slots(mid8_roster, mid8$league)
mid8_top_qb   <- available_board(mid8_view, pos = "QB", n = 1L)
mid8_top_rb   <- available_board(mid8_view, pos = "RB", n = 1L)
shiny::testServer(.s8_bake_server(snap, s8e_path, cfg), {
  if (!identical(recs()$player_id, term_mid_rec$player_id)) {
    fail("s8: mid-draft server recommendation order differs from the terminal call")
  }
  if (!identical(recs(), term_mid_rec)) {
    fail("s8: mid-draft server recommendation values differ from the terminal call")
  }

  ## output$roster_table (verification-gap "Regression gap": roster_slots()'s
  ## only real call site was never rendered by a test) -- cross-check the
  ## rendered HTML against a direct roster_slots() call on the same roster, so
  ## a swapped pontos/vor column or a broken match() alignment would fail here.
  rt <- output$roster_table
  for (i in seq_len(nrow(mid8_roster))) {
    pid <- mid8_roster$player_id[i]
    slot_i <- mid8_slots$slot[mid8_slots$player_id == pid]
    row_re <- sprintf(
      "<td> %s </td>.*<td> %s </td>.*<td> %s </td>.*<td align=\"right\"> %s </td>.*<td align=\"right\"> %s </td>",
      slot_i, mid8_roster$player[i], mid8_roster$pos[i],
      sprintf("%.2f", mid8_roster$points[i]), sprintf("%.2f", mid8_roster$vor[i]))
    if (!grepl(row_re, rt)) {
      fail("s8: roster_table does not render the expected slot/player/pos/pontos/vor row for ", pid)
    }
  }

  ## output$recent_picks_table -- last pick (overall 15) must appear, ordered
  ## before an earlier pick (overall 14).
  rp <- output$recent_picks_table
  pl15 <- snap$players[snap$players$player_id == mid8$picks$player_id[15], ]
  pl14 <- snap$players[snap$players$player_id == mid8$picks$player_id[14], ]
  if (!grepl(sprintf(">  15 </td> <td> %s </td> <td> %s </td>", pl15$player, pl15$pos),
            rp, fixed = FALSE)) {
    fail("s8: recent_picks_table missing/wrong row for the most recent pick")
  }
  pos15 <- regexpr(paste0(">  15 </td>"), rp, fixed = TRUE)
  pos14 <- regexpr(paste0(">  14 </td>"), rp, fixed = TRUE)
  if (pos15 < 0 || pos14 < 0 || pos15 > pos14) {
    fail("s8: recent_picks_table not ordered most-recent-first")
  }
  if (!grepl(pl15$player, rp, fixed = TRUE) || !grepl("Team 10", rp, fixed = TRUE)) {
    fail("s8: recent_picks_table missing expected team for the most recent pick")
  }

  ## output$available_table + input$pos_filter -- filtering by position
  ## actually narrows the board (previously undriven by any test).
  session$setInputs(pos_filter = "QB")
  av_qb <- output$available_table
  if (!grepl(mid8_top_qb$player[1], av_qb, fixed = TRUE)) {
    fail("s8: available_table (QB filter) missing the top available QB")
  }
  if (grepl(mid8_top_rb$player[1], av_qb, fixed = TRUE)) {
    fail("s8: available_table (QB filter) leaked a non-QB player -- filter not applied")
  }
})

## (8f) Draft complete -> banner shows "DRAFT COMPLETO", recommendations empty.
s8f_path <- file.path(tempdir(), "warroom-s8f", "draft.rds")
unlink(dirname(s8f_path), recursive = TRUE)
full8 <- new_draft(snap, team_order, "Team 01", league = cfg$league)
full8$picks <- data.frame(
  overall = 1:168, player_id = snap$players$player_id[1:168],
  entered_at = as.POSIXct("2026-09-01 12:00:00", tz = "UTC") + 1:168,
  stringsAsFactors = FALSE
)
save_state(full8, s8f_path)
shiny::testServer(.s8_bake_server(snap, s8f_path, cfg), {
  b <- output$banner
  if (!grepl("DRAFT COMPLETO", b, fixed = TRUE)) fail("s8: completed-draft banner wrong: ", b)
  if (nrow(recs()) != 0L) fail("s8: completed-draft recommendations not empty")
})

## (8g) roster_slots(): reuses .warroom_sim_starter_ids() twice (real FLEX,
## then FLEX = 0L) to isolate who occupies FLEX; K/DST always land in BENCH,
## same convention as lineup_value()/.warroom_best_lineup().
r8 <- data.frame(
  player_id = c("q1", "r1", "r2", "r3", "w1", "w2", "t1", "k1", "d1"),
  pos       = c("QB", "RB", "RB", "RB", "WR", "WR", "TE", "K", "DST"),
  vor       = c(50, 40, 35, 30, 45, 20, 15, 5, 5),
  points    = c(300, 250, 240, 230, 260, 200, 180, 130, 140),
  stringsAsFactors = FALSE
)
sl8 <- roster_slots(r8, cfg$league)
if (!identical(names(sl8), c("player_id", "slot"))) fail("s8: roster_slots() columns wrong")
if (!identical(sort(sl8$player_id), sort(r8$player_id))) {
  fail("s8: roster_slots() dropped or added rows")
}
slot_of <- function(pid) sl8$slot[sl8$player_id == pid]
if (slot_of("q1") != "QB")                          fail("s8: roster_slots(): QB starter wrong")
if (slot_of("r1") != "RB" || slot_of("r2") != "RB") fail("s8: roster_slots(): RB starters wrong")
if (slot_of("r3") != "FLEX") {
  fail("s8: roster_slots(): 3rd RB should occupy FLEX, got ", slot_of("r3"))
}
if (slot_of("w1") != "WR" || slot_of("w2") != "WR") fail("s8: roster_slots(): WR starters wrong")
if (slot_of("t1") != "TE")                          fail("s8: roster_slots(): TE starter wrong")
if (slot_of("k1") != "BENCH" || slot_of("d1") != "BENCH") {
  fail("s8: roster_slots(): K/DST should be BENCH (lineup_value() never starts them)")
}
if (nrow(roster_slots(NULL, cfg$league)) != 0L)      fail("s8: roster_slots(NULL) not 0 rows")
if (nrow(roster_slots(r8[0, ], cfg$league)) != 0L)   fail("s8: roster_slots(0-row) not 0 rows")

## (8h) Static analysis: app.R redefines no core formula/function, names no
## RNG symbol, and makes no network / scrape call (Acceptance Criteria).
app_src <- readLines("app.R", warn = FALSE)
if (any(grepl("pnorm\\(|rnorm\\(|runif\\(|rbinom\\(|rpois\\(|rexp\\(|\\bsample\\(",
             app_src))) {
  fail("s8: app.R names an RNG symbol")
}
redefined <- grepl(
  "^(recommend_players|lineup_value|derive_draft_view|record_pick|undo_pick|save_state|load_state|roster_slots)\\s*<-",
  app_src)
if (any(redefined)) {
  fail("s8: app.R redefines a core function: ", paste(app_src[redefined], collapse = " | "))
}
if (any(grepl("ffanalytics|http[s]?://|\\bscrape\\b|httr::|curl::|RCurl::|download\\.file\\(",
             app_src))) {
  fail("s8: app.R names a network / scrape symbol")
}

cat("story 8 offline checks OK -- app.R server() + roster_slots() + terminal/Shiny equivalence\n")

## --- Summary (I/O matrix: "smoke offline") -------------------------------
cat(sprintf("smoke OK -- %d players in %s\n", n, snapshot_path))
for (p in names(pos_tab)) cat(sprintf("  %-3s %3d\n", p, pos_tab[[p]]))
cat(sprintf("snapshot size: %.1f KB\n", file.size(snapshot_path) / 1024))
quit(status = 0L, save = "no")
