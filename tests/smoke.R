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
## League format now lives in config/league.yml (read on the live path), not
## config.R. `rounds` is derived = sum(roster) = 15 for the initial league.
league <- load_league()

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

## --- league resolver: config/league.yml -> derived rounds (offline) ------
## load_league() reads the YAML league file and derives rounds = sum(roster).
lg <- load_league()
if (!identical(lg$teams, 12L))             fail("league: teams != 12")
if (!identical(lg$rounds, 15L))            fail("league: rounds not derived to 15, got ", lg$rounds)
if (!identical(lg$rounds, as.integer(sum(lg$roster)))) fail("league: rounds != sum(roster)")
if (!identical(names(lg$roster), .warroom_roster_slots)) fail("league: roster slot set wrong")
if (!is.integer(lg$roster))               fail("league: roster not coerced to integer")
if (!identical(as.character(lg$flex_positions), c("RB", "WR"))) fail("league: flex_positions wrong")

lg_dir <- file.path(tempdir(), "warroom-league"); dir.create(lg_dir, showWarnings = FALSE)
wl <- function(txt, name) { p <- file.path(lg_dir, name); writeLines(txt, p); p }
## A complete, valid roster block to vary one line at a time.
full_roster <- c("roster:", "  QB: 1", "  RB: 2", "  WR: 2", "  TE: 1",
                 "  FLEX: 1", "  K: 1", "  DST: 1", "  BENCH: 6")
lyml <- function(teams = "teams: 12", roster = full_roster,
                 flex = "flex_positions: [RB, WR]", name) {
  wl(c(teams, roster, flex), name)
}

msg <- expect_error(load_league(file.path(lg_dir, "nope.yml")), "league: missing file")
if (!grepl("nope.yml", msg, fixed = TRUE)) fail("league: missing-file error omits path: ", msg)

msg <- expect_error(load_league(lyml(roster = character(0), name = "no-roster.yml")),
                    "league: no roster key")
if (!grepl("roster", msg)) fail("league: missing-roster error omits 'roster': ", msg)

msg <- expect_error(load_league(lyml(
  roster = setdiff(full_roster, "  FLEX: 1"), name = "no-flex-slot.yml")),
  "league: missing a roster slot")
if (!grepl("FLEX", msg)) fail("league: missing-slot error omits FLEX: ", msg)

msg <- expect_error(load_league(lyml(
  roster = c(full_roster, "  IR: 2"), name = "unknown-slot.yml")),
  "league: unknown roster slot")
if (!grepl("IR", msg)) fail("league: unknown-slot error omits IR: ", msg)

msg <- expect_error(load_league(lyml(
  roster = c("roster:", "  QB: 1.5", "  RB: 2", "  WR: 2", "  TE: 1",
             "  FLEX: 1", "  K: 1", "  DST: 1", "  BENCH: 6"),
  name = "frac-roster.yml")), "league: fractional roster slot")
if (!grepl("non-integral", msg)) fail("league: fractional-roster error wording: ", msg)

msg <- expect_error(load_league(lyml(
  roster = c("roster:", "  QB: 1", "  RB: -1", "  WR: 2", "  TE: 1",
             "  FLEX: 1", "  K: 1", "  DST: 1", "  BENCH: 6"),
  name = "neg-roster.yml")), "league: negative roster slot")
if (!grepl("negative", msg)) fail("league: negative-roster error wording: ", msg)

msg <- expect_error(load_league(lyml(teams = "teams: 0", name = "bad-teams.yml")),
                    "league: teams < 1")
if (!grepl("whole number", msg)) fail("league: bad-teams error wording: ", msg)

msg <- expect_error(load_league(lyml(flex = "flex_positions: []", name = "no-flexpos.yml")),
                    "league: empty flex_positions with FLEX slots")
if (!grepl("flex_positions is empty", msg)) fail("league: empty-flexpos error wording: ", msg)

msg <- expect_error(load_league(lyml(flex = "flex_positions: [QB, RB]", name = "bad-flexpos.yml")),
                    "league: ineligible flex position")
if (!grepl("ineligible", msg)) fail("league: ineligible-flexpos error wording: ", msg)

msg <- expect_error(load_league(lyml(
  roster = c("roster:", "  QB: 1", "  RB: 2", "  WR: 2", "  TE: 0",
             "  FLEX: 1", "  K: 1", "  DST: 1", "  BENCH: 7"),
  flex = "flex_positions: [RB, WR, TE]", name = "flex-no-slot.yml")),
  "league: flex position with no roster slot")
if (!grepl("no roster slot", msg)) fail("league: flex-no-slot error wording: ", msg)

## A zero FLEX slot makes flex_positions irrelevant -- no error even if empty.
lg_noflex <- load_league(lyml(
  roster = c("roster:", "  QB: 1", "  RB: 2", "  WR: 3", "  TE: 1",
             "  FLEX: 0", "  K: 1", "  DST: 1", "  BENCH: 6"),
  flex = "flex_positions: []", name = "ok-zero-flex.yml"))
if (!identical(lg_noflex$rounds, 15L)) fail("league: zero-FLEX rounds not 15")

## --- story 3: snake schedule, draft state, RDS persistence (offline) -----
## Every row of the story-3 I/O & Edge-Case matrix. tempdir() only -- state/ is
## never touched. No network.

team_order <- sprintf("Team %02d", 1:12)

## Schedule: 180 turns (12 x 15), correct serpentine reversals, round/pick_in_round.
if (!identical(league$rounds, 15L)) fail("league: rounds should derive to 15, got ", league$rounds)
sched <- make_snake_schedule(league$teams, league$rounds)
if (!identical(nrow(sched), 180L)) fail("schedule: expected 180 rows, got ", nrow(sched))
if (!identical(names(sched), c("overall", "round", "pick_in_round", "slot"))) {
  fail("schedule: wrong columns: ", paste(names(sched), collapse = ", "))
}
if (!identical(sched$overall, 1:180))       fail("schedule: overall not sequential 1..180")
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
if (!identical(d0$league$teams, 12L) || !identical(d0$league$rounds, 15L)) {
  fail("new_draft: league teams/rounds wrong")
}
if (is.null(names(d0$league$roster))) fail("new_draft: roster not a named vector")
if (!is.integer(d0$league$roster))   fail("new_draft: roster not coerced to integer")
if (!identical(d0$user_team, "Team 01")) fail("new_draft: user_team not stored")
if (!identical(d0$seed, 1L))             fail("new_draft: default seed not 1L")

## new_draft with explicit seed + explicit (non-config) league. `rounds` is not
## a key -- it is derived as sum(roster) = 3, and a `rounds` key would be ignored.
## An explicit league may list only the slots it uses; the rest default to 0.
custom_league <- list(teams = 4L,
                      roster = c(QB = 1L, RB = 1L, FLEX = 1L),
                      flex_positions = c("RB"))
dc <- new_draft(snap, sprintf("T%d", 1:4), "T2", seed = 7L, league = custom_league)
if (!identical(dc$seed, 7L))          fail("new_draft: explicit seed not stored")
if (!identical(dc$league$teams, 4L) || !identical(dc$league$rounds, 3L)) {
  fail("new_draft: explicit league not used / rounds not derived to 3")
}
if (!identical(names(dc$league$roster), .warroom_roster_slots)) {
  fail("new_draft: explicit league roster not filled to the full slot set")
}
if (!identical(unname(dc$league$roster["WR"]), 0L)) fail("new_draft: absent slot not filled with 0")
## A `rounds` key in an explicit league is ignored -- still derived from roster.
dc2 <- new_draft(snap, sprintf("T%d", 1:4), "T2",
                 league = c(custom_league, list(rounds = 99L)))
if (!identical(dc2$league$rounds, 3L)) fail("new_draft: explicit rounds key not ignored")
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

## Draft full: 180 picks, another record_pick -> error citing 180.
fixed_ea <- rep(as.POSIXct("2026-09-01 12:00:00", tz = "UTC"), 220)
full_state <- d0
full_state$picks <- data.frame(
  overall    = 1:180,
  player_id  = snap$players$player_id[1:180],
  entered_at = fixed_ea[1:180],
  stringsAsFactors = FALSE
)
msg <- expect_error(record_pick(full_state, snap$players$player_id[181], snap),
                    "record_pick draft full")
if (!grepl("180", msg)) fail("record_pick: full-draft error omits 180: ", msg)

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

## derive_draft_view at the end (180 picks).
vend <- derive_draft_view(full_state, snap)
if (!isTRUE(vend$is_complete))      fail("view: is_complete not TRUE at 180 picks")
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
if (!is.na(next_user_pick(full_state))) fail("next_user_pick: exhausted (Team 01, 180 picks) should be NA")

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
  b$picks <- data.frame(overall = seq_len(181), player_id = sprintf("p%03d", 1:181),
                        entered_at = fixed_ea[rep(1L, 181)], stringsAsFactors = FALSE)
  b
}
msg <- expect_error(load_state(mk_bad(bad_cap, "s3-bad-cap.rds")), "load_state over capacity")
if (!grepl("180", msg)) fail("load_state: over-capacity error omits 180: ", msg)

## load_state rejects a state whose league$rounds != sum(roster) (rounds derived).
msg <- expect_error(
  load_state(mk_bad(function(b) { b$league$rounds <- 14L; b }, "s3-bad-rounds.rds")),
  "load_state rounds != sum(roster)")
if (!grepl("sum of the roster", msg)) fail("load_state: derived-rounds error wording: ", msg)

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

## (2) Resume and complete the rehearsal to all 180 picks.
o2 <- s4_run(snap$players$player)   # every full name; drafted ones resolve to none
if (!has(o2, "=== DRAFT COMPLETO -- 180 picks ==="))  fail("s4: rehearsal did not complete 180 picks")
d_final <- load_state(s4_path)
if (nrow(d_final$picks) != 180L)                      fail("s4: final draft not 180 picks")
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

## Draft<->snapshot binding: resuming against a snapshot whose created_at does
## not match the one the draft was started on is refused before the loop.
snap_future <- snap
snap_future$created_at <- snap$created_at + 3600
bind_state  <- new_draft(snap_future, team_order, "Team 01", league = league)
bind_path   <- file.path(tempdir(), "warroom-s4-bind", "draft.rds")
unlink(dirname(bind_path), recursive = TRUE)
save_state(bind_state, bind_path)
bci <- textConnection("/quit"); bco <- textConnection("s4_bind_out", open = "w", local = TRUE)
msg <- expect_error(run_draft(con = bci, out = bco, snapshot = snap, state_path = bind_path),
                    "s4: resume against a mismatched snapshot")
tryCatch({ close(bco); close(bci) }, error = function(e) NULL)
if (!grepl("wrong snapshot", msg)) fail("s4: binding-mismatch error wording: ", msg)
## Resuming with the snapshot the draft WAS bound to works (covered elsewhere for
## the 0-pick case; here just confirm the same file is fine with its own snapshot).
bci2 <- textConnection("/quit"); bco2 <- textConnection("s4_bind_ok", open = "w", local = TRUE)
run_draft(con = bci2, out = bco2, snapshot = snap_future, state_path = bind_path)
close(bco2); close(bci2)
if (!any(grepl("retomando", s4_bind_ok, fixed = TRUE))) fail("s4: bound snapshot did not resume")
unlink(dirname(bind_path), recursive = TRUE)

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
lv5 <- lineup_value(rl5, league)   # points fallback: 380 + 460 + 540 + 180 + FLEX(190)
if (abs(lv5 - 1750) > 1e-6)           fail("s5: lineup_value (points fallback) != 1750, got ", lv5)
if (lineup_value(rl5[0, ], league) != 0) fail("s5: empty roster lineup_value != 0")
## vor is the value currency when present -- a huge `points` must not override it.
if (lineup_value(data.frame(pos = "RB", vor = 100, points = 9999), league) != 100) {
  fail("s5: lineup_value did not prefer vor over points")
}

## Snake slot-1 overalls -> the user's pick numbers.
s5_sched  <- make_snake_schedule(league$teams, league$rounds)
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
  st <- new_draft(snap, team_order, "Team 01", league = league)
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
st0 <- new_draft(snap, team_order, "Team 01", league = league)
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

## (f) K/DST forced + strand guard: 13-man roster, 2 picks left in a 15-round
## draft, only K & DST still mandatory -> nothing else is eligible.
roster_pre_kdst <- c("SYN-QB-001","SYN-RB-001","SYN-RB-002","SYN-WR-001","SYN-WR-002",
                     "SYN-TE-001","SYN-RB-003","SYN-RB-004","SYN-RB-005","SYN-WR-003",
                     "SYN-WR-004","SYN-TE-002","SYN-WR-005")
rf5 <- recommend_players(s5_state(roster_pre_kdst, pool = s5_worst(c("K","DST"))), snap)
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
  overall    = 1:180,
  player_id  = snap$players$player_id[1:180],
  entered_at = as.POSIXct("2026-09-01 12:00:00", tz = "UTC") + 1:180,
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
## 14-man roster needing only DST, 1 pick left in a 15-round draft, and 22 of 24
## DSTs already gone: the strand + squeeze filters leave exactly 2 eligible.
roster14 <- c("SYN-QB-001","SYN-RB-001","SYN-RB-002","SYN-WR-001","SYN-WR-002",
              "SYN-TE-001","SYN-RB-003","SYN-K-001","SYN-RB-004","SYN-RB-005",
              "SYN-WR-003","SYN-WR-004","SYN-TE-002","SYN-WR-005")
dst_gone  <- sprintf("SYN-DST-%03d", 1:22)
r_few <- recommend_players(
  s5_state(roster14, pool = c(dst_gone, s5_worst(c("K","DST")))), snap, n = 10L)
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

## (6g) No following user pick: state just before the user's very last pick,
## the user on the clock, no pick after it -> p_next / wait_cost NA, score finite.
s6_last  <- new_draft(snap, team_order, "Team 01", league = league)
s6_sched <- make_snake_schedule(league$teams, league$rounds)
user_overalls <- s6_sched$overall[s6_sched$slot == 1L]     # Team 01's picks (15)
last_user     <- max(user_overalls)                         # round 15, slot 1
n_before      <- last_user - 1L                             # picks already made
s6_uN    <- user_overalls[-length(user_overalls)]           # the earlier user overalls
s6_u_ids <- c("SYN-QB-001", "SYN-RB-001", "SYN-RB-002", "SYN-WR-001", "SYN-WR-002",
              "SYN-TE-001", "SYN-RB-003", "SYN-K-001", "SYN-DST-001",
              "SYN-QB-002", "SYN-WR-003", "SYN-RB-004", "SYN-TE-002", "SYN-RB-005")
if (length(s6_uN) != length(s6_u_ids)) fail("s6: user pre-final overall count wrong")
s6_others <- setdiff(snap$players$player_id, s6_u_ids)
s6_ids    <- character(n_before)
s6_ids[s6_uN] <- s6_u_ids
s6_ids[setdiff(seq_len(n_before), s6_uN)] <- s6_others[seq_len(n_before - length(s6_uN))]
s6_last$picks <- data.frame(
  overall = seq_len(n_before), player_id = s6_ids,
  entered_at = as.POSIXct("2026-09-01 12:00:00", tz = "UTC") + seq_len(n_before),
  stringsAsFactors = FALSE)
s6_vlast <- derive_draft_view(s6_last, snap)
if (!identical(s6_vlast$current_overall, last_user)) fail("s6: not at the user's last overall")
if (!identical(s6_vlast$team_on_clock, "Team 01"))   fail("s6: user not on the clock at the last overall")
if (!is.na(.warroom_following_user_pick(s6_last, last_user))) fail("s6: following pick not NA at the last overall")
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

## (6j) /rec in the terminal shows p_next and wait alongside score / label; on
## the user's turn there is no off-turn banner.
s6t_path <- file.path(tempdir(), "warroom-s6t", "draft.rds")
unlink(dirname(s6t_path), recursive = TRUE)
o6t <- s4_run(c(team_line, "/rec", "/quit"), state_path = s6t_path)
if (!has(o6t, "recomendacoes (top"))            fail("s6: /rec header missing")
if (!has(o6t, "p_next"))                         fail("s6: /rec output has no p_next")
if (!has(o6t, "wait "))                          fail("s6: /rec output has no wait column")
if (has(o6t, "voce nao esta na vez"))            fail("s6: off-turn banner shown on the user's own turn")
unlink(dirname(s6t_path), recursive = TRUE)

## (6j2) /rec off-turn (after the user's pick 1, Team 02 on the clock) prints the
## banner in the terminal.
s6t2_path <- file.path(tempdir(), "warroom-s6t2", "draft.rds")
unlink(dirname(s6t2_path), recursive = TRUE)
o6t2 <- s4_run(c(team_line, "RB Synthetic 01", "/rec", "/quit"), state_path = s6t2_path)
if (!has(o6t2, "voce nao esta na vez"))          fail("s6: off-turn /rec banner missing in terminal")
unlink(dirname(s6t2_path), recursive = TRUE)

## (6k) No RNG / Monte Carlo / network markers in the recommendation source.
s6_src <- readLines(.warroom_find_file("R/recommendation.R"), warn = FALSE)
if (any(grepl("monte|rnorm|runif|\\bsample\\(|replicate|\\bboot\\b", s6_src))) {
  fail("s6: recommendation.R names an RNG / Monte Carlo symbol")
}
if (any(grepl("shiny|http[s]?://|readRDS|saveRDS|scrape", s6_src))) {
  fail("s6: recommendation.R names a shiny / network / file-IO symbol")
}

## (6l) Off-turn guard: recommend_players() called when the user is NOT on the
## clock marks the frame and annotates the top reason -- p_next/adp_value assume
## the user picks now, so the caller must be told.
ot_on  <- new_draft(snap, team_order, "Team 01", league = league)   # overall 1, user on clock
ot_off <- record_pick(ot_on, snap$players$player_id[1], snap)       # overall 2, Team 02 on clock
r_on  <- recommend_players(ot_on, snap)
r_off <- recommend_players(ot_off, snap)
if (!identical(attr(r_on, "off_turn"), FALSE))  fail("s6: on-turn recs marked off_turn")
if (!identical(attr(r_off, "off_turn"), TRUE))  fail("s6: off-turn recs not marked off_turn")
if (grepl("assumindo seu proximo pick", r_on$reason[1], fixed = TRUE)) {
  fail("s6: on-turn top reason carries the off-turn annotation")
}
if (!grepl("assumindo seu proximo pick", r_off$reason[1], fixed = TRUE)) {
  fail("s6: off-turn top reason not annotated: ", r_off$reason[1])
}
## A finished draft is over, not "off turn" -- empty result, off_turn FALSE.
ot_done <- ot_on
ot_done$picks <- data.frame(
  overall = 1:180, player_id = snap$players$player_id[1:180],
  entered_at = as.POSIXct("2026-09-01 12:00:00", tz = "UTC") + 1:180,
  stringsAsFactors = FALSE)
r_done <- recommend_players(ot_done, snap)
if (nrow(r_done) != 0L)                          fail("s6: finished draft returned recs")
if (!identical(attr(r_done, "off_turn"), FALSE)) fail("s6: finished draft marked off_turn")

cat("story 6 offline checks OK -- p_next + expected_best_next + wait_cost + four-term score\n")

## --- story 7: mock simulator and calibration (offline) -------------------
## opponent_pick / simulate_draft / compare_strategies / calibrate_weights.
## Reuses snap, team_order, cfg, fail, expect_error from the earlier scope.
## No network; deterministic seeds only. Covers the story-7 I/O matrix.

## (7a) opponent_pick(): the returned player_id is always a row of `available`
## (never a re-draft, since `available` excludes drafted players by construction).
s7_root <- new_draft(snap, team_order, "Team 01", league = league)
s7_view <- derive_draft_view(s7_root, snap)
s7_mv   <- .warroom_market_value(snap$players, seed = 1L)
if (is.null(names(s7_mv)) || length(s7_mv) != nrow(snap$players)) {
  fail("s7: .warroom_market_value did not return a fully named vector")
}
op1 <- opponent_pick(s7_view$available, s7_view$rosters[["Team 02"]], league, s7_mv)
if (!(op1 %in% s7_view$available$player_id)) {
  fail("s7: opponent_pick returned a player not in `available`")
}
expect_error(opponent_pick(s7_view$available[0, , drop = FALSE], NULL, league, s7_mv),
            "opponent_pick: no eligible candidate")

## (7b) Full simulated draft, "warroom" strategy: 180 picks, no duplicate,
## every one of the 12 rosters valid (15 players, no mandatory slot empty).
sim_w <- simulate_draft(snap, team_order, "Team 01", seed = 1L, strategy = "warroom",
                        league = league)
if (nrow(sim_w$state$picks) != 180L) {
  fail("s7: warroom sim did not complete 180 picks, got ", nrow(sim_w$state$picks))
}
if (anyDuplicated(sim_w$state$picks$player_id)) fail("s7: warroom sim drafted a duplicate player")
if (!identical(names(sim_w$rosters_valid), team_order)) fail("s7: rosters_valid not named by team_order")
if (!all(sim_w$rosters_valid)) {
  fail("s7: warroom sim left invalid roster(s): ",
       paste(names(sim_w$rosters_valid)[!sim_w$rosters_valid], collapse = ", "))
}
for (tm in team_order) {
  r <- derive_draft_view(sim_w$state, snap)$rosters[[tm]]
  if (nrow(r) != 15L) fail("s7: ", tm, " does not have 15 players, got ", nrow(r))
  if (.warroom_unfilled_mandatory(r, league)$total != 0L) {
    fail("s7: ", tm, " has an unfilled mandatory slot")
  }
}

## (7c) Determinism: two identical calls -> identical() state and metrics.
sim_w2 <- simulate_draft(snap, team_order, "Team 01", seed = 1L, strategy = "warroom",
                         league = league)
if (!identical(sim_w$state, sim_w2$state))     fail("s7: two simulate_draft() calls produced different state")
if (!identical(sim_w$metrics, sim_w2$metrics)) fail("s7: two simulate_draft() calls produced different metrics")

## (7c2) Different seeds must produce different outcomes -- guards against a
## regression where .warroom_market_value() silently ignores `seed`.
sim_w_seed2 <- simulate_draft(snap, team_order, "Team 01", seed = 2L, strategy = "warroom",
                              league = league)
if (identical(sim_w$state$picks$player_id, sim_w_seed2$state$picks$player_id)) {
  fail("s7: seed 1 and seed 2 produced identical simulate_draft() outcomes")
}

## (7c3) .warroom_sim_starter_ids() cross-check: the starter set it picks for
## sim_w's user roster must sum (vor if present else points, matching
## .warroom_value_of()) to the same value lineup_value() reports for that
## roster. Guards against the two independent "who starts" selections drifting.
sim_w_roster      <- derive_draft_view(sim_w$state, snap)$rosters[["Team 01"]]
sim_w_starter_ids <- .warroom_sim_starter_ids(sim_w_roster, league)
sim_w_starter_val <- sum(.warroom_value_of(sim_w_roster)[sim_w_roster$player_id %in% sim_w_starter_ids])
sim_w_lineup_val  <- lineup_value(sim_w_roster, league)
if (abs(sim_w_starter_val - sim_w_lineup_val) > 1e-6) {
  fail("s7: .warroom_sim_starter_ids() value sum (", sim_w_starter_val,
       ") does not match lineup_value() (", sim_w_lineup_val, ")")
}

## (7d) adp / vor strategies also complete 180 picks with valid rosters.
sim_a <- simulate_draft(snap, team_order, "Team 01", seed = 1L, strategy = "adp", league = league)
sim_v <- simulate_draft(snap, team_order, "Team 01", seed = 1L, strategy = "vor", league = league)
if (nrow(sim_a$state$picks) != 180L) fail("s7: adp sim did not complete 180 picks")
if (nrow(sim_v$state$picks) != 180L) fail("s7: vor sim did not complete 180 picks")
if (anyDuplicated(sim_a$state$picks$player_id)) fail("s7: adp sim drafted a duplicate player")
if (anyDuplicated(sim_v$state$picks$player_id)) fail("s7: vor sim drafted a duplicate player")
if (!all(sim_a$rosters_valid)) fail("s7: adp sim left an invalid roster")
if (!all(sim_v$rosters_valid)) fail("s7: vor sim left an invalid roster")

## (7e) RNG isolation: simulate_draft() never leaks .Random.seed to the caller.
set.seed(42L)
rs_before <- get(".Random.seed", envir = .GlobalEnv)
invisible(simulate_draft(snap, team_order, "Team 01", seed = 2L, strategy = "adp",
                         league = league))
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

## (7g) Strand guard: 13-man roster missing only K + DST, 2 picks remaining in a
## 15-round draft, round deliberately early (5) -- the K/DST grace-round rule
## alone would exclude them, but the strand guard must still admit exactly K/DST.
roster13_ids <- c("SYN-QB-001","SYN-RB-001","SYN-RB-002","SYN-WR-001","SYN-WR-002",
                  "SYN-TE-001","SYN-RB-003","SYN-RB-004","SYN-RB-005","SYN-WR-003",
                  "SYN-WR-004","SYN-TE-002","SYN-WR-005")
roster13_s7 <- snap$players[snap$players$player_id %in% roster13_ids, , drop = FALSE]
avail_s7    <- snap$players[!(snap$players$player_id %in% roster13_ids), , drop = FALSE]
elig7 <- .warroom_eligible_sim_candidates(avail_s7, roster13_s7, league, round_on_clock = 5L)
if (nrow(elig7) == 0L)                    fail("s7: strand guard left no eligible K/DST candidate")
if (!all(elig7$pos %in% c("K", "DST")))   fail("s7: strand guard did not restrict to K/DST")
op7 <- opponent_pick(avail_s7, roster13_s7, league,
                     .warroom_market_value(snap$players, seed = 1L))
pl7 <- snap$players$pos[snap$players$player_id == op7]
if (!(pl7 %in% c("K", "DST"))) fail("s7: opponent_pick ignored the strand guard, picked ", pl7)

## Positional cap, isolated from the strand guard: a bigger league (more
## rounds) so 8 RBs is not yet mandatory-tight; RB (at its cap) must be
## excluded while WR (under its cap) and K/DST (round too early, not tight)
## behave as expected.
cap_league <- league
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

## output$status_strip is a renderUI -> testServer hands back either a
## processed list(html=, deps=) or the raw tag object; flatten both to a string.
.strip_html <- function(o) {
  h <- if (is.list(o) && !is.null(o$html)) o$html else o
  paste(as.character(h), collapse = "\n")
}

## count non-overlapping fixed-string occurrences in a rendered HTML blob.
.html_count <- function(h, needle) {
  m <- gregexpr(needle, h, fixed = TRUE)[[1]]
  if (length(m) == 1L && m[1] == -1L) 0L else length(m)
}

## story 16: the player picker is textInput("player_query") resolved through
## resolve_player() against view()$available -- not a selectize of player_id.
## A test that used to set input$player_choice <- <player_id> now types the
## player's full name (an exact normalised match -> a unique hit) and fires the
## same do_pick() path via input$draft_btn or input$search_row_1.
.s16_query_for <- function(snapshot, pid) {
  snapshot$players$player[match(pid, snapshot$players$player_id)]
}

## (8a) No state/draft.rds -> new_draft() with default team_order / config
## user_team, saved immediately; status strip shows PICK 1 / Round 01.
s8a_path <- file.path(tempdir(), "warroom-s8a", "draft.rds")
unlink(dirname(s8a_path), recursive = TRUE)
shiny::testServer(.s8_bake_server(snap, s8a_path, cfg), {
  b <- .strip_html(output$status_strip)
  if (!grepl("PICK 1", b, fixed = TRUE) || !grepl("Round 01", b, fixed = TRUE)) {
    fail("s8: new-draft status strip wrong: ", b)
  }
})
if (!file.exists(s8a_path)) fail("s8: new draft not saved on first load")
d8a <- load_state(s8a_path)
if (nrow(d8a$picks) != 0L) fail("s8: fresh state should have 0 picks")
if (!identical(d8a$user_team, cfg$user_team)) fail("s8: user_team not taken from config.R")
if (!identical(d8a$team_order, sprintf("Team %02d", seq_len(league$teams)))) {
  fail("s8: team_order not the default 'Team NN' sequence")
}

## (8b) Existing state/draft.rds -> load_state() used; status strip reflects
## derive_draft_view().
s8b_path <- file.path(tempdir(), "warroom-s8b", "draft.rds")
unlink(dirname(s8b_path), recursive = TRUE)
pre <- new_draft(snap, team_order, "Team 01", league = league)
pre <- record_pick(pre, snap$players$player_id[1], snap)
pre <- record_pick(pre, snap$players$player_id[2], snap)
save_state(pre, s8b_path)
shiny::testServer(.s8_bake_server(snap, s8b_path, cfg), {
  if (!identical(state()$picks, pre$picks)) {
    fail("s8: resumed state picks differ from the pre-existing file")
  }
  v <- derive_draft_view(state(), snap)
  if (!identical(v$current_overall, 3L)) fail("s8: resumed view current_overall wrong")
  b <- .strip_html(output$status_strip)
  if (!grepl("PICK 3", b, fixed = TRUE)) {
    fail("s8: resumed status strip does not reflect derive_draft_view(): ", b)
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
  session$setInputs(player_query = .s16_query_for(snap, pid))
  session$setInputs(draft_btn = 1)
  if (nrow(state()$picks) != 1L)          fail("s8: draft_btn did not record a pick")
  if (state()$picks$player_id[1] != pid)  fail("s8: draft_btn recorded the wrong player")
  if (pid %in% view()$available$player_id) fail("s8: drafted player still shows as available")

  ## story 16: once a player is drafted the search box no longer surfaces them
  ## (resolve_player() returns "none"), so a "Registrar" with that same query
  ## takes the empty-selection branch -- no pick, no crash of the reactive
  ## session (the already-drafted branch itself is covered in s13c / s14).
  session$setInputs(player_query = .s16_query_for(snap, pid))
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
  session$setInputs(player_query = .s16_query_for(snap, pid))
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
mid8 <- new_draft(snap, team_order, "Team 01", league = league)
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
  ## mid8 (15 picks) has an opponent on the clock -> the off-turn note renders.
  if (!grepl("nao esta na vez", output$recs_note, fixed = TRUE)) {
    fail("s8: off-turn recs_note not rendered when an opponent is on the clock")
  }

  ## output$roster_table is now the story-12 grouped renderUI panel (was a
  ## renderTable). Cross-check the rendered markup: the fixed 3-group shell, one
  ## .roster-row per league roster slot (sum(roster) == 15), and every player
  ## Team 01 holds rendered as a filled row -- name in a .name span and the
  ## "pos <midpoint> nfl_team" meta joined from the same snapshot row (no
  ## points/vor number anywhere). A broken match() alignment or a dropped
  ## nfl_team join would fail here. Midpoint built via intToUtf8() to keep
  ## this file ASCII-clean.
  mid_dot <- intToUtf8(183L)   # U+00B7 middle dot -- keep this file ASCII
  rt <- .strip_html(output$roster_table)
  if (!grepl('class="roster-panel"', rt, fixed = TRUE)) {
    fail("s8: roster_table did not render the grouped .roster-panel: ", rt)
  }
  if (.html_count(rt, '<div class="roster-group">') != 3L) {
    fail("s8: roster panel should render exactly 3 groups (Titulares/FLEX/Banco)")
  }
  if (.html_count(rt, '<div class="roster-row') != sum(mid8$league$roster)) {
    fail("s8: roster panel rows != sum(roster) = ", sum(mid8$league$roster))
  }
  if (grepl("pontos", rt, fixed = TRUE) ||
      grepl(sprintf("%.2f", mid8_roster$points[1]), rt, fixed = TRUE)) {
    fail("s8: roster panel still shows a points/vor number")
  }
  for (i in seq_len(nrow(mid8_roster))) {
    if (!grepl(sprintf('<span class="name">%s</span>', mid8_roster$player[i]),
               rt, fixed = TRUE)) {
      fail("s8: roster panel missing the filled .name row for ", mid8_roster$player_id[i])
    }
    if (!grepl(sprintf('<span class="meta">%s %s %s</span>',
                       mid8_roster$pos[i], mid_dot, mid8_roster$nfl_team[i]),
               rt, fixed = TRUE)) {
      fail("s8: roster panel meta not 'pos <midpoint> nfl_team' for ",
           mid8_roster$player_id[i])
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

## (8f) Draft complete -> status strip shows "DRAFT COMPLETO", recommendations empty.
s8f_path <- file.path(tempdir(), "warroom-s8f", "draft.rds")
unlink(dirname(s8f_path), recursive = TRUE)
full8 <- new_draft(snap, team_order, "Team 01", league = league)
full8$picks <- data.frame(
  overall = 1:180, player_id = snap$players$player_id[1:180],
  entered_at = as.POSIXct("2026-09-01 12:00:00", tz = "UTC") + 1:180,
  stringsAsFactors = FALSE
)
save_state(full8, s8f_path)
shiny::testServer(.s8_bake_server(snap, s8f_path, cfg), {
  b <- .strip_html(output$status_strip)
  if (!grepl("DRAFT COMPLETO", b, fixed = TRUE)) fail("s8: completed-draft status strip wrong: ", b)
  if (nrow(recs()) != 0L) fail("s8: completed-draft recommendations not empty")
})

## (8f2) Draft<->snapshot binding at Shiny startup: same check the terminal makes
## on resume -- a state file bound to a different snapshot created_at is refused.
s8bind_path <- file.path(tempdir(), "warroom-s8bind", "draft.rds")
unlink(dirname(s8bind_path), recursive = TRUE)
snap_future8 <- snap; snap_future8$created_at <- snap$created_at + 3600
save_state(new_draft(snap_future8, team_order, "Team 01", league = league), s8bind_path)
msg <- expect_error(
  shiny::testServer(.s8_bake_server(snap, s8bind_path, cfg), { output$status_strip }),
  "s8: Shiny startup against a mismatched snapshot")
if (!grepl("wrong snapshot", msg)) fail("s8: Shiny binding-mismatch error wording: ", msg)
unlink(dirname(s8bind_path), recursive = TRUE)

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
sl8 <- roster_slots(r8, league)
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
if (nrow(roster_slots(NULL, league)) != 0L)      fail("s8: roster_slots(NULL) not 0 rows")
if (nrow(roster_slots(r8[0, ], league)) != 0L)   fail("s8: roster_slots(0-row) not 0 rows")

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

## --- story 9: dark terminal shell (offline, CSS + header only) -----------
## www/styles.css is a static dark-shell stylesheet built from the DESIGN.md
## tokens; app.R loads it via tags$head(tags$link(...)) and swaps the big
## titlePanel for a lean one-line header. Appearance only -- every story-8
## outputId / inputId and the whole fluidPage tree survive as-is, and no new
## render, reactive, core call, RNG symbol or theming package is introduced.
## Reuses `fail` and the `ui` object from story 8's source("app.R").

if (!file.exists("www/styles.css")) fail("s9: www/styles.css missing")
css9 <- readLines("www/styles.css", warn = FALSE)
if (length(css9) == 0L || !any(nzchar(trimws(css9)))) fail("s9: www/styles.css is empty")
css9_txt <- paste(css9, collapse = "\n")
for (tok in c("#0B0F14", "#57D68D", "#67B7FF", "ui-monospace", "2px")) {
  if (!grepl(tok, css9_txt, fixed = TRUE)) fail("s9: styles.css missing token '", tok, "'")
}
if (!grepl("color-scheme", css9_txt, fixed = TRUE)) fail("s9: styles.css missing color-scheme")
if (!grepl(":root", css9_txt, fixed = TRUE)) fail("s9: styles.css has no :root token block")

## www/styles.css is now on the live-draft path -- AGENTS.md forbids any network
## fetch there. No @import, no url(http...), no remote font src.
if (grepl("@import|url\\(\\s*['\"]?https?:|src:\\s*url\\(\\s*['\"]?https?:",
          css9_txt, perl = TRUE)) {
  fail("s9: styles.css pulls a remote asset (@import / url(http...)) -- network on the live path")
}

app9 <- readLines("app.R", warn = FALSE)
app9_txt <- paste(app9, collapse = "\n")
if (!grepl("tags\\$head\\(", app9_txt) || !grepl('href = "styles\\.css"|href="styles\\.css"', app9_txt)) {
  fail("s9: app.R does not load styles.css via tags$head(tags$link(...))")
}
if (any(grepl("titlePanel\\(", app9)))          fail("s9: app.R still uses titlePanel")
if (any(grepl('style *= *"[^"]*color: *#[bB]00', app9))) {
  fail("s9: app.R still uses the inline recs-note color style")
}
if (any(grepl("bslib|sass|bs_theme|includeCSS|shinythemes", app9))) {
  fail("s9: app.R introduced a forbidden theming dependency")
}

## htmltools hoists a nested tags$head into renderTags(ui)$head (exactly what
## Shiny drops into the served <head>); the fluidPage body stays in $html. Both
## halves of as.character(ui) are covered by concatenating them.
ui9_parts <- htmltools::renderTags(ui)
ui9 <- paste(as.character(ui9_parts$head), as.character(ui9_parts$html),
             as.character(ui), sep = "\n")
if (!grepl('href="styles.css"', ui9, fixed = TRUE)) {
  fail("s9: rendered ui <head> does not <link> styles.css")
}
## titlePanel() also injected <title windowTitle>; the plain div does not, so
## app.R must add it back explicitly.
if (!grepl("<title>Draft War Room</title>", ui9, fixed = TRUE)) {
  fail("s9: rendered ui <head> lost the <title> (was injected by titlePanel)")
}
## the lean header must still be there -- a regression deleting the line would
## otherwise slip past every other s9 check.
if (!grepl('class="app-header"', ui9, fixed = TRUE) ||
    !grepl(">Draft War Room<", ui9, fixed = TRUE)) {
  fail("s9: rendered ui lost the .app-header 'Draft War Room' label")
}
## recs_note wrapper carries the class, not an inline style.
if (!grepl('class="recs-note"', ui9, fixed = TRUE)) {
  fail("s9: recs_note wrapper is not rendered with class=\"recs-note\"")
}
if (grepl("color:#b00|color: #b00", ui9)) {
  fail("s9: rendered ui still carries the old inline recs-note color")
}
for (id in c("status_strip", "recs_note", "recs_table", "roster_table",
             "recent_picks_table", "available_table",
             "player_query", "search_results", "draft_btn", "undo_btn",
             "pos_filter")) {
  if (!grepl(id, ui9, fixed = TRUE)) fail("s9: rendered ui lost the story-8 id '", id, "'")
}
if (grepl("player_choice", ui9, fixed = TRUE)) fail("s9: rendered ui still carries player_choice")

## Matrix row 3: styles.css absent at runtime -> the page still assembles, no
## server error. The stylesheet is referenced by href only; nothing on the R
## path reads it. Copy the file to a backup (works across filesystems), delete
## the original, re-source app.R, then restore -- the `finally` guarantees the
## repo never loses www/styles.css even if the assertion body throws.
s9_css_bak <- file.path(tempdir(), "styles.css.s9bak")
if (!file.copy("www/styles.css", s9_css_bak, overwrite = TRUE)) {
  fail("s9: could not stage a backup of www/styles.css for the row-3 check")
}
s9_ok <- tryCatch({
  if (!file.remove("www/styles.css")) stop("could not remove www/styles.css")
  s9_env <- new.env(parent = globalenv())
  suppressMessages(sys.source("app.R", envir = s9_env))
  htmltools::renderTags(s9_env$ui)
  inherits(shiny::shinyApp(s9_env$ui, s9_env$server), "shiny.appobj")
}, error = function(e) structure(FALSE, msg = conditionMessage(e)),
   finally = {
     if (!file.exists("www/styles.css")) {
       file.copy(s9_css_bak, "www/styles.css", overwrite = TRUE)
     }
   })
if (!file.exists("www/styles.css")) {
  fail("s9: www/styles.css was not restored after the row-3 check")
}
if (!isTRUE(s9_ok)) {
  fail("s9: app assembly errored with www/styles.css absent: ", attr(s9_ok, "msg"))
}

cat("story 9 offline checks OK -- www/styles.css dark shell + app.R header, content unchanged\n")

## --- story 10: fixed status strip (offline, renderUI over derived views) ----
## app.R swaps h3(textOutput("banner")) for uiOutput("status_strip"), moved out
## of the fluidRow to be a direct child of fluidPage (sibling to .app-header) so
## position:sticky pins it against .container-fluid. output$status_strip is a
## single renderUI composed purely over derive_draft_view() / next_user_pick()
## + the last pick derived every render from picks + schedule + snapshot.
## Reuses `fail`, `ui`, `.s8_bake_server`, `.strip_html` from the story 8/9 blocks.

## UI tree: id="status_strip" is a pre-.row child of .container-fluid; the old
## id="banner" is gone; every other story-8 id survives.
ui10 <- as.character(htmltools::renderTags(ui)$html)
if (!grepl('id="status_strip"', ui10, fixed = TRUE)) {
  fail("s10: rendered ui has no id=\"status_strip\"")
}
if (grepl('id="banner"', ui10, fixed = TRUE)) {
  fail("s10: rendered ui still carries id=\"banner\"")
}
p_strip <- regexpr('id="status_strip"', ui10, fixed = TRUE)
p_row   <- regexpr('class="row"', ui10, fixed = TRUE)
if (p_strip < 0L || p_row < 0L || p_strip > p_row) {
  fail("s10: status_strip is not a child of .container-fluid ahead of any .row")
}
for (id in c("recs_note", "recs_table", "roster_table", "recent_picks_table",
             "available_table", "player_query", "search_results", "draft_btn",
             "undo_btn", "pos_filter")) {
  if (!grepl(id, ui10, fixed = TRUE)) fail("s10: rendered ui lost the story-8 id '", id, "'")
}

## www/styles.css: the sticky strip rule and the Tab-focus scroll padding are
## present; still no remote asset on the live path. Comments are stripped first
## so the sticky assertion tests the RULE, not the prose that mentions it (the
## exact loop-1 regression: it must fail if .status-strip becomes position:
## relative).
css10 <- paste(readLines("www/styles.css", warn = FALSE), collapse = "\n")
## (?s): CSS comments span newlines -- make `.` match them too.
css10_code <- gsub("(?s)/\\*.*?\\*/", "", css10, perl = TRUE)
for (tok in c(".status-strip", "scroll-padding-top")) {
  if (!grepl(tok, css10_code, fixed = TRUE)) fail("s10: styles.css missing '", tok, "'")
}
strip_rule <- regmatches(
  css10_code, regexpr("\\.status-strip\\s*\\{[^}]*\\}", css10_code, perl = TRUE))
if (length(strip_rule) != 1L || !grepl("position:\\s*sticky", strip_rule)) {
  fail("s10: .status-strip rule is not 'position: sticky' (loop-1 regression): ",
       paste(strip_rule, collapse = ""))
}
if (grepl("@import|url\\(\\s*['\"]?https?:|src:\\s*url\\(\\s*['\"]?https?:",
          css10_code, perl = TRUE)) {
  fail("s10: styles.css pulls a remote asset -- network on the live path")
}

## Fabricate a state with `k` sequential picks (same shortcut as 8f), no
## record_pick() loop needed for a formatting check.
.s10_state <- function(k) {
  st <- new_draft(snap, team_order, "Team 01", league = league)
  if (k > 0L) {
    st$picks <- data.frame(
      overall    = seq_len(k),
      player_id  = snap$players$player_id[seq_len(k)],
      entered_at = as.POSIXct("2026-09-01 12:00:00", tz = "UTC") + seq_len(k),
      stringsAsFactors = FALSE)
  }
  st
}

## I/O matrix rows: new draft (0), mid-draft opponent on clock (15), user on the
## clock (24 -> overall 25 is Team 01's), user with no picks left (170), overall
## 180 still LIVE (179 -> PICK 180, not complete: live/complete boundary), and
## the completed draft (180). All grep needles are de-accented for C-locale
## safety, matching the existing `grepl("ltimo", ...)` style.
for (sc in list(list(k = 0L,   tag = "new"),
                list(k = 15L,  tag = "mid"),
                list(k = 24L,  tag = "user-on-clock"),
                list(k = 170L, tag = "no-picks-left"),
                list(k = 179L, tag = "last-live"),
                list(k = 180L, tag = "complete"))) {
  k <- sc$k; tag <- sc$tag
  s10_path <- file.path(tempdir(), paste0("warroom-s10-", tag), "draft.rds")
  unlink(dirname(s10_path), recursive = TRUE)
  st10  <- .s10_state(k)
  save_state(st10, s10_path)
  v10   <- derive_draft_view(st10, snap)
  nup10 <- next_user_pick(st10)
  sch10 <- make_snake_schedule(st10$league$teams, st10$league$rounds)
  shiny::testServer(.s8_bake_server(snap, s10_path, cfg), {
    h <- .strip_html(output$status_strip)
    ## aria-label lives on the renderUI output div (not the static ui tree).
    if (!grepl('aria-label="Estado do draft"', h, fixed = TRUE)) {
      fail("s10[", tag, "]: status strip lost its aria-label: ", h)
    }
    ## the static saved line must never fall out of the strip.
    if (!grepl("sess", h, fixed = TRUE)) {
      fail("s10[", tag, "]: status strip lost the 'sessao local' saved line: ", h)
    }
    if (isTRUE(v10$is_complete)) {
      if (!grepl("DRAFT COMPLETO", h, fixed = TRUE) ||
          !grepl(sprintf("%d picks<", k), h, fixed = TRUE)) {
        fail("s10[", tag, "]: completed strip text wrong: ", h)
      }
      if (grepl("live-pick--current", h, fixed = TRUE)) {
        fail("s10[", tag, "]: live-pick--current must be absent on a completed draft")
      }
      ## no clock / proximo line on a completed draft (matrix: "sem Round / no relogio").
      if (grepl("no rel", h, fixed = TRUE) || grepl("ximo:", h, fixed = TRUE)) {
        fail("s10[", tag, "]: completed strip still shows the clock / proximo line: ", h)
      }
    } else {
      if (!grepl(sprintf("PICK %d<", v10$current_overall), h, fixed = TRUE)) {
        fail("s10[", tag, "]: strip missing 'PICK ", v10$current_overall, "': ", h)
      }
      if (!grepl("live-pick--current", h, fixed = TRUE)) {
        fail("s10[", tag, "]: live-pick--current missing on the live pick")
      }
      if (grepl("live-pick--done", h, fixed = TRUE)) {
        fail("s10[", tag, "]: live-pick--done present on a live pick")
      }
      if (!grepl(v10$team_on_clock, h, fixed = TRUE)) {
        fail("s10[", tag, "]: strip missing team on the clock '", v10$team_on_clock, "'")
      }
      if (!grepl(sprintf("Round %02d", v10$round_on_clock), h, fixed = TRUE)) {
        fail("s10[", tag, "]: strip missing 'Round ", sprintf("%02d", v10$round_on_clock), "'")
      }
      if (!grepl("ximo:", h, fixed = TRUE)) {
        fail("s10[", tag, "]: strip missing the 'Proximo:' line: ", h)
      }
      if (is.na(nup10)) {
        if (grepl("seu pick", h, fixed = TRUE)) {
          fail("s10[", tag, "]: strip still says 'seu pick' with no user picks left: ", h)
        }
      } else if (!grepl(sprintf("seu pick %d", nup10), h, fixed = TRUE)) {
        fail("s10[", tag, "]: strip missing 'seu pick ", nup10, "': ", h)
      }
    }
    ## "Ultimo" line -- derived from picks + schedule + snapshot, incl. nfl_team.
    if (k == 0L) {
      if (!grepl("ltimo", h, fixed = TRUE)) {
        fail("s10[", tag, "]: strip missing the 'Ultimo' label with 0 picks: ", h)
      }
      ## value must be the em-dash placeholder, not a stray name / meta / NA
      ## (needle written as a unicode escape so this file stays ASCII-clean).
      if (!grepl("\u2014", h, fixed = TRUE)) {
        fail("s10[", tag, "]: 0-pick last line is not the em-dash placeholder: ", h)
      }
      if (grepl("status-strip-last-meta", h, fixed = TRUE) ||
          grepl("NA", h, fixed = TRUE)) {
        fail("s10[", tag, "]: 0-pick last line leaked a player / meta / NA: ", h)
      }
    } else {
      lp10   <- snap$players[snap$players$player_id == st10$picks$player_id[k], ]
      team10 <- st10$team_order[sch10$slot[k]]
      for (piece in c(as.character(k), lp10$player, lp10$pos, lp10$nfl_team, team10)) {
        if (!grepl(piece, h, fixed = TRUE)) {
          fail("s10[", tag, "]: last-pick line missing '", piece, "': ", h)
        }
      }
    }
  })
}

## Static analysis (same spirit as 8h): the strip added no network / RNG symbol
## and no forbidden theming / JS dependency to app.R.
app10 <- readLines("app.R", warn = FALSE)
if (any(grepl("bslib|sass|includeCSS|shinyjs|Shiny\\.setInputValue",
              app10))) {
  fail("s10: app.R introduced a forbidden JS / theming dependency")
}
if (any(grepl("ffanalytics|http[s]?://|\\bscrape\\b|httr::|curl::|download\\.file\\(",
              app10))) {
  fail("s10: app.R names a network / scrape symbol")
}

cat("story 10 offline checks OK -- fixed status strip renderUI over derived views\n")

## --- story 11: smart candidate list (offline, renderUI over recs()) --------
## app.R swaps tableOutput("recs_table") for uiOutput("recs_table") plus a
## radioButtons("recs_pos_filter") badge row. output$recs_table is a renderUI
## that only formats the frame recommend_players() already returned -- no column
## or row order recomputed -- and the position badge subsets the cached recs()
## reactive, never re-calling recommend_players(). Reuses `fail`, `ui`, `snap`,
## `team_order`, `cfg`, `league`, `.s8_bake_server`, `.strip_html`.

.s11_count <- function(h, needle) {
  m <- gregexpr(needle, h, fixed = TRUE)[[1]]
  if (length(m) == 1L && m[1] == -1L) 0L else length(m)
}

## on-turn mid-draft: 23 picks -> overall 24 belongs to Team 01 (the user).
s11_path <- file.path(tempdir(), "warroom-s11", "draft.rds")
unlink(dirname(s11_path), recursive = TRUE)
mid11 <- new_draft(snap, team_order, "Team 01", league = league)
for (i in 1:23) mid11 <- record_pick(mid11, snap$players$player_id[i], snap)
save_state(mid11, s11_path)
term11 <- recommend_players(mid11, snap)
if (nrow(term11) < 5L) fail("s11: fixture mid-draft recs has < 5 rows -- precondition")
if (isTRUE(attr(term11, "off_turn"))) fail("s11: mid11 should be the user's own pick")
rb_players <- term11$player[term11$pos == "RB"]
if (!length(rb_players)) fail("s11: fixture mid-draft recs has no RB row -- precondition")
absent_pos <- setdiff(.warroom_pos_levels, term11$pos)[1]
if (is.na(absent_pos)) fail("s11: fixture recs cover every position -- need one absent")
## rank-01 nfl_team comes from the snapshot join, not the recs frame.
pl11_1 <- snap$players[match(term11$player_id[1], snap$players$player_id), ]
if (is.na(pl11_1$nfl_team) || !nzchar(pl11_1$nfl_team)) {
  fail("s11: fixture rank-01 player has no nfl_team -- precondition")
}

shiny::testServer(.s8_bake_server(snap, s11_path, cfg), {
  ## default badge "Todos": full smart list, ranked, no 1 highlighted.
  h <- .strip_html(output$recs_table)
  if (!grepl('class="smart-list"', h, fixed = TRUE)) fail("s11: no .smart-list rendered: ", h)
  if (!grepl('role="list"', h, fixed = TRUE)) fail("s11: .smart-list missing role=list")
  if (!grepl("aria-label=\"Recomenda", h, fixed = TRUE)) fail("s11: .smart-list missing aria-label")
  n_cand <- .s11_count(h, 'class="candidate')
  if (n_cand != nrow(term11)) {
    fail("s11: rendered ", n_cand, " candidate rows, recommend_players() returned ", nrow(term11))
  }
  if (n_cand < 5L) fail("s11: fewer than 5 candidate rows rendered")
  if (.s11_count(h, "candidate--top") != 1L) fail("s11: expected exactly one .candidate--top under Todos")
  if (.s11_count(h, "candidate--first") != 0L) fail("s11: candidate--first present under Todos")
  ## rank-01 shows pos followed by the snapshot nfl_team (P1: joined, not the frame).
  if (!grepl(sprintf('class="pos">%s %s<', term11$pos[1], pl11_1$nfl_team), h, fixed = TRUE)) {
    fail("s11: rank-01 pos cell does not show 'pos nfl_team': ", h)
  }
  if (!grepl(">01<", h, fixed = TRUE) || !grepl(">02<", h, fixed = TRUE)) {
    fail("s11: ranks 01/02 not rendered")
  }
  if (!grepl(term11$player[1], h, fixed = TRUE)) fail("s11: top player name missing")
  if (!grepl(term11$reason[1], h, fixed = TRUE)) fail("s11: top reason missing / altered")
  if (!grepl(sprintf(">%.1f<", term11$decision_score[1]), h, fixed = TRUE)) {
    fail("s11: top decision_score not rendered to 1 decimal")
  }
  if (regexpr(term11$player[1], h, fixed = TRUE) >
      regexpr(term11$player[2], h, fixed = TRUE)) {
    fail("s11: smart list reordered rows relative to recommend_players()")
  }

  ## position badge: subset recs(), never re-call recommend_players().
  before <- recs()
  session$setInputs(recs_pos_filter = "RB")
  if (!identical(recs(), before) || !identical(recs(), term11)) {
    fail("s11: recs() frame changed when the position badge changed")
  }
  h_rb <- .strip_html(output$recs_table)
  if (.s11_count(h_rb, 'class="candidate') != length(rb_players)) {
    fail("s11: RB badge did not narrow the list to the RB rows of recs()")
  }
  for (p in rb_players) if (!grepl(p, h_rb, fixed = TRUE)) fail("s11: RB row dropped: ", p)
  non_rb <- term11$player[term11$pos != "RB"]
  if (length(non_rb) && grepl(non_rb[1], h_rb, fixed = TRUE)) {
    fail("s11: RB badge leaked a non-RB row")
  }
  if (!grepl(">01<", h_rb, fixed = TRUE)) fail("s11: filtered list not re-ranked from 01")
  ## P11: no false action-green "Enter will register" marker on a filtered list.
  if (.s11_count(h_rb, "candidate--top") != 0L) fail("s11: candidate--top present under the RB filter")
  if (.s11_count(h_rb, "candidate--first") != 1L) fail("s11: expected one candidate--first under the RB filter")

  ## badge with no matching row -> empty text, badges still operable.
  session$setInputs(recs_pos_filter = absent_pos)
  h_none <- .strip_html(output$recs_table)
  if (grepl('class="candidate', h_none, fixed = TRUE)) fail("s11: no-match badge still rendered rows")
  if (!grepl(sprintf("Nenhum candidato %s nas recomenda", absent_pos), h_none)) {
    fail("s11: no-match empty text wrong: ", h_none)
  }

  session$setInputs(recs_pos_filter = "Todos")
  if (.s11_count(.strip_html(output$recs_table), 'class="candidate') != nrow(term11)) {
    fail("s11: returning to Todos did not restore the full list")
  }
})

## (11d) recs() empty (completed draft) -> "Nenhum candidato disponivel.", 0 rows.
s11f_path <- file.path(tempdir(), "warroom-s11f", "draft.rds")
unlink(dirname(s11f_path), recursive = TRUE)
full11 <- new_draft(snap, team_order, "Team 01", league = league)
full11$picks <- data.frame(
  overall = 1:180, player_id = snap$players$player_id[1:180],
  entered_at = as.POSIXct("2026-09-01 12:00:00", tz = "UTC") + 1:180,
  stringsAsFactors = FALSE)
save_state(full11, s11f_path)
shiny::testServer(.s8_bake_server(snap, s11f_path, cfg), {
  if (nrow(recs()) != 0L) fail("s11: completed-draft recs() not empty -- precondition")
  h <- .strip_html(output$recs_table)
  if (grepl('class="candidate', h, fixed = TRUE)) fail("s11: completed draft rendered candidate rows")
  if (!grepl("Nenhum candidato dispon", h)) fail("s11: completed-draft empty text wrong: ", h)
})

## (11e) optional columns absent from the synthetic snapshot: `tier` -> em-dash
## (never "NA"); `nfl_team` -> bare pos (no separator, no "NA").
s11n_path <- file.path(tempdir(), "warroom-s11n", "draft.rds")
unlink(dirname(s11n_path), recursive = TRUE)
snap_nt <- snap
snap_nt$players$tier <- NULL
snap_nt$players$nfl_team <- NULL
mid_nt <- new_draft(snap_nt, team_order, "Team 01", league = league)
for (i in 1:23) mid_nt <- record_pick(mid_nt, snap_nt$players$player_id[i], snap_nt)
save_state(mid_nt, s11n_path)
term_nt <- recommend_players(mid_nt, snap_nt)
if (!all(is.na(term_nt$tier))) fail("s11: dropping snapshot tier did not null the recs tier column")
shiny::testServer(.s8_bake_server(snap_nt, s11n_path, cfg), {
  h <- .strip_html(output$recs_table)
  if (!grepl('class="smart-list"', h, fixed = TRUE)) fail("s11: tier-less snapshot broke the smart list")
  if (grepl(">NA<", h, fixed = TRUE) || grepl("NA</span>", h, fixed = TRUE)) {
    fail("s11: smart list emitted the string 'NA' for a missing optional field: ", h)
  }
  if (!grepl("\u2014", h, fixed = TRUE)) fail("s11: missing tier not shown as the em-dash")
  ## rank-01 pos cell is the bare position -- no trailing separator / team.
  if (!grepl(sprintf('class="pos">%s</span>', term_nt$pos[1]), h, fixed = TRUE)) {
    fail("s11: nfl_team-less snapshot did not render a bare pos cell: ", h)
  }
})

## (11g) off-turn (matrix row): an opponent is on the clock but recs() is
## non-empty -> the smart list renders in full, output$recs_note carries the
## warning, and rank 01's reason keeps the "[assumindo seu proximo pick" prefix
## .warroom_recs_result() adds off-turn. 15 picks -> overall 16 is an opponent's
## (same fixture shape as 8e).
s11o_path <- file.path(tempdir(), "warroom-s11o", "draft.rds")
unlink(dirname(s11o_path), recursive = TRUE)
off11 <- new_draft(snap, team_order, "Team 01", league = league)
for (i in 1:15) off11 <- record_pick(off11, snap$players$player_id[i], snap)
save_state(off11, s11o_path)
term_off <- recommend_players(off11, snap)
if (!isTRUE(attr(term_off, "off_turn"))) fail("s11: 15-pick fixture is not off-turn -- precondition")
if (nrow(term_off) == 0L) fail("s11: off-turn recs empty -- precondition")
if (!grepl("[assumindo seu proximo pick", term_off$reason[1], fixed = TRUE)) {
  fail("s11: .warroom_recs_result() did not prefix the off-turn reason -- precondition")
}
shiny::testServer(.s8_bake_server(snap, s11o_path, cfg), {
  if (!isTRUE(attr(recs(), "off_turn"))) fail("s11: server recs() lost the off_turn attr")
  if (!grepl("nao esta na vez", output$recs_note, fixed = TRUE)) {
    fail("s11: off-turn recs_note not rendered: ", output$recs_note)
  }
  h <- .strip_html(output$recs_table)
  if (!grepl('class="smart-list"', h, fixed = TRUE)) fail("s11: off-turn smart list not rendered: ", h)
  if (.s11_count(h, 'class="candidate') != nrow(term_off)) {
    fail("s11: off-turn smart list row count differs from recommend_players()")
  }
  if (!grepl("[assumindo seu proximo pick", h, fixed = TRUE)) {
    fail("s11: off-turn rank 01 reason lost the assumes-you-pick-now prefix: ", h)
  }
})

## (11h) www/styles.css absent at runtime (matrix row): the smart list still
## assembles with no server error. Same swap-and-restore pattern as the story 9
## row-3 check -- the `finally` puts www/styles.css back even if the body throws,
## and the result is captured (not asserted inside) so fail()'s quit() cannot
## skip the restore.
s11css_path <- file.path(tempdir(), "warroom-s11css", "draft.rds")
unlink(dirname(s11css_path), recursive = TRUE)
s11css_state <- new_draft(snap, team_order, "Team 01", league = league)
for (i in 1:23) s11css_state <- record_pick(s11css_state, snap$players$player_id[i], snap)
save_state(s11css_state, s11css_path)
s11_css_bak <- file.path(tempdir(), "styles.css.s11bak")
if (!file.copy("www/styles.css", s11_css_bak, overwrite = TRUE)) {
  fail("s11: could not stage a backup of www/styles.css for the css-absent check")
}
s11_css_seen <- NULL
s11_css_ok <- tryCatch({
  if (!file.remove("www/styles.css")) stop("could not remove www/styles.css")
  s11_env <- new.env(parent = globalenv())
  suppressMessages(sys.source("app.R", envir = s11_env))
  srv <- s11_env$server
  formals(srv)$snapshot   <- snap
  formals(srv)$state_path <- s11css_path
  formals(srv)$config     <- cfg
  shiny::testServer(srv, {
    hh <- .strip_html(output$recs_table)
    s11_css_seen <<- grepl('class="smart-list"', hh, fixed = TRUE) &&
      .s11_count(hh, 'class="candidate') > 0L
  })
  isTRUE(s11_css_seen)
}, error = function(e) structure(FALSE, msg = conditionMessage(e)),
   finally = {
     if (!file.exists("www/styles.css")) {
       file.copy(s11_css_bak, "www/styles.css", overwrite = TRUE)
     }
   })
if (!file.exists("www/styles.css")) fail("s11: www/styles.css not restored after the css-absent check")
if (!isTRUE(s11_css_ok)) {
  fail("s11: smart list did not assemble with www/styles.css absent: ", attr(s11_css_ok, "msg"))
}

## (11f) static UI + CSS + app.R analysis (Acceptance Criteria).
ui11 <- as.character(htmltools::renderTags(ui)$html)
if (!grepl('id="recs_table"', ui11, fixed = TRUE)) fail("s11: rendered ui has no id=\"recs_table\"")
if (!grepl('id="recs_pos_filter"', ui11, fixed = TRUE)) fail("s11: rendered ui has no id=\"recs_pos_filter\"")
p_rt <- regexpr('id="recs_table"', ui11, fixed = TRUE)
if (grepl("<table", substr(ui11, p_rt, p_rt + 200L), fixed = TRUE)) {
  fail("s11: recs_table renders a static <table>")
}
for (id in c("status_strip", "recs_note", "roster_table", "recent_picks_table",
             "available_table", "player_query", "search_results", "draft_btn",
             "undo_btn", "pos_filter")) {
  if (!grepl(id, ui11, fixed = TRUE)) fail("s11: rendered ui lost the story 8-10 id '", id, "'")
}
## P7: the radio group has a real (visually-hidden) accessible name.
if (!grepl('id="recs_pos_filter-label"', ui11, fixed = TRUE) ||
    !grepl("Filtrar recomenda", ui11, fixed = TRUE)) {
  fail("s11: recs_pos_filter has no non-empty <label> for its accessible name")
}
css11 <- paste(readLines("www/styles.css", warn = FALSE), collapse = "\n")
css11_code <- gsub("(?s)/\\*.*?\\*/", "", css11, perl = TRUE)
for (tok in c(".smart-list", ".candidate", ".candidate--top", ".candidate--first",
              ".recs-filters", ".shiny-options-group", "name-text")) {
  if (!grepl(tok, css11_code, fixed = TRUE)) fail("s11: styles.css missing '", tok, "'")
}
## P5: the selected-badge treatment must not reuse the focus-blue outline.
if (grepl(":has\\(input:checked\\)[^}]*outline", css11_code, perl = TRUE) ||
    grepl("input:checked \\+ span[^}]*outline", css11_code, perl = TRUE)) {
  fail("s11: selected badge reuses an outline -- indistinguishable from the focus ring")
}
if (grepl("@import|url\\(\\s*['\"]?https?:|src:\\s*url\\(\\s*['\"]?https?:",
          css11_code, perl = TRUE)) {
  fail("s11: styles.css pulls a remote asset -- network on the live path")
}
app11 <- readLines("app.R", warn = FALSE)
if (any(grepl("bslib|sass|includeCSS|shinyjs|Shiny\\.setInputValue", app11))) {
  fail("s11: app.R introduced a forbidden JS / theming dependency")
}
if (any(grepl("pnorm\\(|rnorm\\(|runif\\(|\\bsample\\(", app11))) fail("s11: app.R names an RNG symbol")
if (any(grepl("ffanalytics|http[s]?://|\\bscrape\\b|httr::|curl::|download\\.file\\(", app11))) {
  fail("s11: app.R names a network / scrape symbol")
}
app11_code <- sub("#.*$", "", app11)
if (any(grepl("^\\s*recommend_players\\s*<-", app11_code))) fail("s11: app.R redefines recommend_players")
n_rp_calls <- sum(grepl("recommend_players\\(", app11_code))
if (n_rp_calls != 1L) {
  fail("s11: recommend_players() called ", n_rp_calls, " times in app.R code (expected 1)")
}

cat("story 11 offline checks OK -- smart candidate list renderUI + position badges\n")

## --- story 12: grouped roster panel (offline, renderUI over rosters + roster_slots) --
## app.R swaps tableOutput("roster_table") for uiOutput("roster_table") plus a
## renderUI that composes three fixed visual groups -- Titulares (QB RB WR TE K
## DST), FLEX, Banco -- with one row per league roster slot. Unfilled slots are
## explicit ("- aberto" for starters/FLEX, "-" for the bench). roster_slots() is
## the sole source for QB/RB/WR/TE/FLEX; K/DST are placed into their dedicated
## Titulares slots by pos identity; the bench excludes the K/DST so placed and
## its BENCH floor is a floor, not a cap. Multi-slot rows and the bench are
## ordered by vor (points fallback) desc. No points/vor number is shown.
## Reuses `fail`, `ui`, `snap`, `team_order`, `cfg`, `league`, `.s8_bake_server`,
## `.strip_html`, `.s11_count`, `.html_count`.

s12_open  <- paste0(intToUtf8(0x2014L), " aberto")   # "- aberto" (starters/FLEX)
s12_dash  <- intToUtf8(0x2014L)                       # "-"        (bench)
s12_mid   <- intToUtf8(0x00B7L)                       # "*"        (pos . team)
s12_sched <- make_snake_schedule(league$teams, league$rounds)
s12_t1_ov <- s12_sched$overall[s12_sched$slot == 1L]  # "Team 01" is slot 1

## Fabricate a contiguous-picks state whose Team 01 roster is exactly `pids`, in
## that order; every non-Team-01 pick is filler. Direct $picks assignment (same
## shortcut as .s10_state / 8f), so record_pick()'s feasibility guardrails do
## not constrain the fixture.
.s12_state <- function(pids, snapshot = snap) {
  st   <- new_draft(snapshot, team_order, "Team 01", league = league)
  pids <- as.character(pids)
  n    <- length(pids)
  if (n > 0L) {
    m       <- s12_t1_ov[n]
    is_t1   <- s12_sched$slot[seq_len(m)] == 1L
    fillers <- setdiff(snapshot$players$player_id, pids)
    if (sum(!is_t1) > length(fillers)) fail("s12: not enough filler players for the fixture")
    ids            <- character(m)
    ids[is_t1]     <- pids
    ids[!is_t1]    <- fillers[seq_len(sum(!is_t1))]
    st$picks <- data.frame(
      overall    = seq_len(m),
      player_id  = ids,
      entered_at = as.POSIXct("2026-09-01 12:00:00", tz = "UTC") + seq_len(m),
      stringsAsFactors = FALSE)
  }
  st
}

.s12_render <- function(st, snapshot = snap) {
  p <- file.path(tempdir(), "warroom-s12", "draft.rds")
  unlink(dirname(p), recursive = TRUE)
  save_state(st, p)
  out <- NULL
  shiny::testServer(.s8_bake_server(snapshot, p, cfg), {
    out <<- .strip_html(output$roster_table)
  })
  out
}

## HTML of the one .roster-group whose label div == `label`.
.s12_group <- function(h, label) {
  marker <- sprintf('<div class="roster-group-label">%s</div>', label)
  i <- regexpr(marker, h, fixed = TRUE)
  if (i < 0L) fail("s12: roster panel has no '", label, "' group: ", h)
  rest  <- substring(h, i)
  after <- substring(rest, nchar(marker) + 1L)
  nxt   <- regexpr('<div class="roster-group-label">', after, fixed = TRUE)
  if (nxt > 0L) substring(rest, 1L, nchar(marker) + nxt - 1L) else rest
}

## A filled row: <span class="slot">SLOT</span> then <span class="name">NAME</span>.
.s12_filled <- function(h, slot, name) {
  grepl(sprintf('<span class="slot">%s</span>[[:space:]]*<span class="name">%s</span>',
                slot, name), h)
}
## An empty row: <span class="slot">SLOT</span> then <span class="empty">PLACEHOLDER</span>.
.s12_empty <- function(h, slot, placeholder) {
  grepl(sprintf('<span class="slot">%s</span>[[:space:]]*<span class="empty">%s</span>',
                slot, placeholder), h, fixed = FALSE)
}

s12_name <- function(pid, snapshot = snap) {
  snapshot$players$player[match(pid, snapshot$players$player_id)]
}
s12_nfl <- function(pid, snapshot = snap) {
  snapshot$players$nfl_team[match(pid, snapshot$players$player_id)]
}

## (12a) Roster parcial: QB, 2 RB, 1 WR, 1 K.
h12 <- .s12_render(.s12_state(c("SYN-QB-001", "SYN-RB-001", "SYN-RB-002",
                                "SYN-WR-001", "SYN-K-001")))
if (!grepl('class="roster-panel"', h12, fixed = TRUE)) fail("s12: no .roster-panel: ", h12)
if (.html_count(h12, '<div class="roster-group">') != 3L) {
  fail("s12: partial roster did not render 3 groups")
}
if (.html_count(h12, '<div class="roster-row') != sum(league$roster)) {
  fail("s12: partial roster rows != sum(roster) = ", sum(league$roster))
}
g12t <- .s12_group(h12, "Titulares")
if (!.s12_filled(g12t, "QB", s12_name("SYN-QB-001"))) fail("s12: QB slot not filled")
if (!.s12_filled(g12t, "RB1", s12_name("SYN-RB-001"))) fail("s12: RB1 != highest-vor RB")
if (!.s12_filled(g12t, "RB2", s12_name("SYN-RB-002"))) fail("s12: RB2 != 2nd RB")
if (!.s12_filled(g12t, "WR1", s12_name("SYN-WR-001"))) fail("s12: WR1 not filled")
if (!.s12_empty(g12t, "WR2", s12_open)) fail("s12: WR2 not '- aberto'")
if (!.s12_empty(g12t, "TE", s12_open))  fail("s12: TE not '- aberto'")
if (!.s12_filled(g12t, "K", s12_name("SYN-K-001"))) fail("s12: K slot not filled (pos-identity placement)")
if (!.s12_empty(g12t, "DST", s12_open)) fail("s12: DST not '- aberto'")
if (!.s12_empty(.s12_group(h12, "FLEX"), "FLEX", s12_open)) fail("s12: FLEX not '- aberto'")
g12b <- .s12_group(h12, "Banco")
if (.html_count(g12b, '<div class="roster-row') != 6L) fail("s12: Banco not 6 rows (K must not count as bench)")
if (.html_count(g12b, sprintf('<span class="empty">%s</span>', s12_dash)) != 6L) {
  fail("s12: Banco not 6 '-' rows")
}
## (12a) nfl_team present (real fixture always carries it): a filled row's meta
## is "pos <mid> nfl_team".
if (!grepl(sprintf('<span class="meta">QB %s %s</span>', s12_mid, s12_nfl("SYN-QB-001")),
           h12, fixed = TRUE)) {
  fail("s12: filled-row meta is not 'pos <mid> nfl_team': ", h12)
}

## (12b) Roster vazio: 8 Titulares + 1 FLEX all "- aberto", 6 Banco "-", 3
## groups, total rows == sum(roster) == 15.
h12e <- .s12_render(.s12_state(character(0)))
if (.html_count(h12e, '<div class="roster-group">') != 3L) fail("s12: empty roster not 3 groups")
if (.html_count(h12e, '<div class="roster-row') != sum(league$roster)) {
  fail("s12: empty roster total rows != sum(roster): ", .html_count(h12e, '<div class="roster-row'))
}
if (.html_count(h12e, '<div class="roster-row') != 15L) fail("s12: initial league empty roster is not 15 rows")
if (.html_count(h12e, sprintf('<span class="empty">%s</span>', s12_open)) != 9L) {
  fail("s12: empty roster not 9 '- aberto' placeholders (8 Titulares + 1 FLEX)")
}
if (.html_count(h12e, sprintf('<span class="empty">%s</span>', s12_dash)) != 6L) {
  fail("s12: empty roster Banco not 6 '-' placeholders")
}
for (lab in c("QB", "RB1", "RB2", "WR1", "WR2", "TE", "K", "DST")) {
  if (!.s12_empty(.s12_group(h12e, "Titulares"), lab, s12_open)) {
    fail("s12: empty roster Titulares slot ", lab, " is not '- aberto'")
  }
}
if (grepl('class="name"', h12e, fixed = TRUE)) fail("s12: empty roster rendered a filled .name row")

## (12c) 3rd RB -> FLEX, RB passed OUT of vor order; RB1/RB2 must still be the
## two highest-vor RBs and the 3rd the FLEX.
h12f <- .s12_render(.s12_state(c("SYN-RB-003", "SYN-RB-001", "SYN-RB-002")))
g12ft <- .s12_group(h12f, "Titulares")
if (!.s12_filled(g12ft, "RB1", s12_name("SYN-RB-001"))) fail("s12: RB1 not the highest-vor RB when drafted out of order")
if (!.s12_filled(g12ft, "RB2", s12_name("SYN-RB-002"))) fail("s12: RB2 not the 2nd-highest-vor RB")
if (!.s12_filled(.s12_group(h12f, "FLEX"), "FLEX", s12_name("SYN-RB-003"))) {
  fail("s12: 3rd RB not placed in the FLEX row")
}

## (12d) K + DST drafted -> both in Titulares, neither in Banco; Banco 6 "-".
h12k <- .s12_render(.s12_state(c("SYN-QB-001", "SYN-K-001", "SYN-DST-001")))
g12kt <- .s12_group(h12k, "Titulares")
if (!.s12_filled(g12kt, "K", s12_name("SYN-K-001")))     fail("s12: K not in Titulares")
if (!.s12_filled(g12kt, "DST", s12_name("SYN-DST-001"))) fail("s12: DST not in Titulares")
g12kb <- .s12_group(h12k, "Banco")
if (grepl(s12_name("SYN-K-001"), g12kb, fixed = TRUE) ||
    grepl(s12_name("SYN-DST-001"), g12kb, fixed = TRUE)) {
  fail("s12: a placed K/DST leaked into the Banco group")
}
if (.html_count(g12kb, '<div class="roster-row') != 6L) fail("s12: Banco not 6 rows with K+DST placed")
if (.html_count(g12kb, sprintf('<span class="empty">%s</span>', s12_dash)) != 6L) {
  fail("s12: Banco not all '-' with K+DST placed")
}

## (12e) 2nd K -> 1st K slot takes the higher-vor K, the 2nd K shows on the
## bench in a filled BN row.
h12k2 <- .s12_render(.s12_state(c("SYN-K-001", "SYN-K-002")))
if (!.s12_filled(.s12_group(h12k2, "Titulares"), "K", s12_name("SYN-K-001"))) {
  fail("s12: K slot did not take the higher-vor K")
}
g12k2b <- .s12_group(h12k2, "Banco")
if (!.s12_filled(g12k2b, "BN", s12_name("SYN-K-002"))) {
  fail("s12: 2nd K not shown in a filled BN bench row")
}
if (grepl(sprintf('<span class="slot">K</span>[[:space:]]*<span class="name">%s</span>',
                  s12_name("SYN-K-002")), h12k2)) {
  fail("s12: 2nd K wrongly occupies the K starter slot")
}

## (12f) Over-draft of the bench: all starters + FLEX + 7 slot-BENCH players
## that are not K/DST -> Banco shows 7 rows, none empty, none truncated.
s12_over <- c("SYN-QB-001",
              "SYN-RB-001", "SYN-RB-002", "SYN-RB-003",
              "SYN-RB-004", "SYN-RB-005", "SYN-RB-006", "SYN-RB-007",
              "SYN-WR-001", "SYN-WR-002",
              "SYN-WR-003", "SYN-WR-004", "SYN-WR-005",
              "SYN-TE-001")
h12o  <- .s12_render(.s12_state(s12_over))
g12ob <- .s12_group(h12o, "Banco")
if (.html_count(g12ob, '<div class="roster-row') != 7L) {
  fail("s12: over-drafted bench not 7 rows: ", .html_count(g12ob, '<div class="roster-row'))
}
if (grepl("roster-row--empty", g12ob, fixed = TRUE)) fail("s12: over-drafted bench has an empty row")
if (grepl('class="empty"', g12ob, fixed = TRUE)) fail("s12: over-drafted bench has an empty-placeholder span")

## (12g) nfl_team absent from the snapshot -> filled-row meta is the bare pos,
## never "NA".
snap12_nt <- snap
snap12_nt$players$nfl_team <- NULL
h12nt <- .s12_render(.s12_state(c("SYN-QB-001"), snap12_nt), snap12_nt)
if (!grepl('<span class="meta">QB</span>', h12nt, fixed = TRUE)) {
  fail("s12: nfl_team-less snapshot did not render a bare-pos meta: ", h12nt)
}
if (grepl(">NA<", h12nt, fixed = TRUE) || grepl("NA</span>", h12nt, fixed = TRUE)) {
  fail("s12: roster panel emitted the string 'NA' for a missing nfl_team")
}

## (12h) Draft completo: 15 players fill every slot -> zero empty rows / zero
## placeholders, no error.
s12_full <- c("SYN-QB-001", "SYN-QB-002",
              "SYN-RB-001", "SYN-RB-002", "SYN-RB-003", "SYN-RB-004", "SYN-RB-005",
              "SYN-WR-001", "SYN-WR-002", "SYN-WR-003", "SYN-WR-004",
              "SYN-TE-001", "SYN-TE-002",
              "SYN-K-001", "SYN-DST-001")
h12c <- .s12_render(.s12_state(s12_full))
if (.html_count(h12c, '<div class="roster-row') != sum(league$roster)) {
  fail("s12: completed roster row count != sum(roster)")
}
if (grepl("roster-row--empty", h12c, fixed = TRUE)) fail("s12: completed roster still has an empty row")
if (grepl(s12_open, h12c, fixed = TRUE)) fail("s12: completed roster still shows '- aberto'")
if (grepl('class="empty"', h12c, fixed = TRUE)) fail("s12: completed roster still shows an empty placeholder")

## (12i) www/styles.css absent at runtime -> the panel still assembles with no
## server error. Same swap-and-restore as the story 9 / 11 css-absent checks.
s12_css_state <- .s12_state(c("SYN-QB-001", "SYN-RB-001"))
s12_css_path  <- file.path(tempdir(), "warroom-s12css", "draft.rds")
unlink(dirname(s12_css_path), recursive = TRUE)
save_state(s12_css_state, s12_css_path)
s12_css_bak <- file.path(tempdir(), "styles.css.s12bak")
if (!file.copy("www/styles.css", s12_css_bak, overwrite = TRUE)) {
  fail("s12: could not stage a backup of www/styles.css for the css-absent check")
}
s12_css_seen <- NULL
s12_css_ok <- tryCatch({
  if (!file.remove("www/styles.css")) stop("could not remove www/styles.css")
  s12_env <- new.env(parent = globalenv())
  suppressMessages(sys.source("app.R", envir = s12_env))
  srv <- s12_env$server
  formals(srv)$snapshot   <- snap
  formals(srv)$state_path <- s12_css_path
  formals(srv)$config     <- cfg
  shiny::testServer(srv, {
    hh <- .strip_html(output$roster_table)
    s12_css_seen <<- grepl('class="roster-panel"', hh, fixed = TRUE) &&
      .html_count(hh, '<div class="roster-row') == sum(league$roster)
  })
  isTRUE(s12_css_seen)
}, error = function(e) structure(FALSE, msg = conditionMessage(e)),
   finally = {
     if (!file.exists("www/styles.css")) {
       file.copy(s12_css_bak, "www/styles.css", overwrite = TRUE)
     }
   })
if (!file.exists("www/styles.css")) fail("s12: www/styles.css not restored after the css-absent check")
if (!isTRUE(s12_css_ok)) fail("s12: roster panel did not assemble with www/styles.css absent: ",
                              attr(s12_css_ok, "msg"))

## (12j) static UI + CSS + app.R analysis (Acceptance Criteria).
ui12 <- as.character(htmltools::renderTags(ui)$html)
if (!grepl('id="roster_table"', ui12, fixed = TRUE)) fail("s12: rendered ui has no id=\"roster_table\"")
p_rt12 <- regexpr('id="roster_table"', ui12, fixed = TRUE)
if (grepl("<table", substr(ui12, p_rt12, p_rt12 + 200L), fixed = TRUE)) {
  fail("s12: roster_table renders a static <table>")
}
for (id in c("status_strip", "recs_note", "recs_table", "recs_pos_filter",
             "recent_picks_table", "available_table", "player_query",
             "search_results", "draft_btn", "undo_btn", "pos_filter")) {
  if (!grepl(id, ui12, fixed = TRUE)) fail("s12: rendered ui lost the story 8-11 id '", id, "'")
}
css12 <- paste(readLines("www/styles.css", warn = FALSE), collapse = "\n")
css12_code <- gsub("(?s)/\\*.*?\\*/", "", css12, perl = TRUE)
for (tok in c(".roster-panel", ".roster-group", ".roster-row")) {
  if (!grepl(tok, css12_code, fixed = TRUE)) fail("s12: styles.css missing '", tok, "'")
}
slot_rule12 <- regmatches(
  css12_code, regexpr("\\.roster-row\\s+\\.slot\\s*\\{[^}]*\\}", css12_code, perl = TRUE))
if (length(slot_rule12) != 1L) fail("s12: no '.roster-row .slot { ... }' rule in styles.css")
if (grepl("var\\(--action\\)", slot_rule12)) {
  fail("s12: '.roster-row .slot' uses var(--action) -- green is reserved (DESIGN.md Colors)")
}
if (grepl("@import|url\\(\\s*['\"]?https?:|src:\\s*url\\(\\s*['\"]?https?:",
          css12_code, perl = TRUE)) {
  fail("s12: styles.css pulls a remote asset -- network on the live path")
}
app12 <- readLines("app.R", warn = FALSE)
if (any(grepl("bslib|sass|includeCSS|shinyjs|Shiny\\.setInputValue", app12))) {
  fail("s12: app.R introduced a forbidden JS / theming dependency")
}
if (any(grepl("pnorm\\(|rnorm\\(|runif\\(|\\bsample\\(", app12))) fail("s12: app.R names an RNG symbol")
if (any(grepl("ffanalytics|http[s]?://|\\bscrape\\b|httr::|curl::|download\\.file\\(", app12))) {
  fail("s12: app.R names a network / scrape symbol")
}
app12_code <- sub("#.*$", "", app12)
if (any(grepl("^\\s*(roster_slots|recommend_players)\\s*<-", app12_code))) {
  fail("s12: app.R redefines roster_slots / recommend_players")
}
if (sum(grepl("recommend_players\\(", app12_code)) != 1L) {
  fail("s12: recommend_players() not called exactly once in app.R code")
}

cat("story 12 offline checks OK -- grouped roster panel renderUI over rosters + roster_slots\n")

## --- story 13: microcopy + persistent pick/undo feedback region (A5) --------
## app.R replaces the three showNotification() toasts with uiOutput(
## "draft_feedback") -- a renderUI over a feedback() reactiveVal placed right
## below the status strip. Confirmations (kind "ok") get a green left border,
## errors (kind "error") a danger border and persist until the next pick/undo
## (no timer / auto-clear). Strings follow EXPERIENCE.md Voice and Tone; the
## pick number N is derived from state()$picks$overall. Static labels are
## accented. Non-ASCII needles are \u-escaped so this file stays ASCII-clean.
## Reuses `fail`, `ui`, `snap`, `cfg`, `league`, `team_order`,
## `.s8_bake_server`, `.strip_html`, `.html_count`.

s13_empty  <- "Selecione um jogador na busca antes de registrar."
s13_noundo <- "Nada a desfazer \u2014 nenhum pick efetivo."
s13_already <- function(n) sprintf("J\u00e1 escolhido no pick %d. Busque outro jogador.", n)
s13_undo    <- function(n) sprintf("Undo aplicado \u2014 pick %d voltou a aberto.", n)
.s13_fb <- function(output) .strip_html(output$draft_feedback)

## (13a) Pick aceito -> draft-feedback--ok + "Registrado: <player>".
s13a_path <- file.path(tempdir(), "warroom-s13a", "draft.rds")
unlink(dirname(s13a_path), recursive = TRUE)
shiny::testServer(.s8_bake_server(snap, s13a_path, cfg), {
  pid  <- view()$available$player_id[1]
  name <- snap$players$player[match(pid, snap$players$player_id)]
  session$setInputs(player_query = name)
  session$setInputs(draft_btn = 1)
  h <- .s13_fb(output)
  if (!grepl("draft-feedback--ok", h, fixed = TRUE)) {
    fail("s13a: accepted pick did not render a draft-feedback--ok line: ", h)
  }
  if (!grepl(sprintf("Registrado: %s", name), h, fixed = TRUE)) {
    fail("s13a: accepted pick feedback missing 'Registrado: <player>': ", h)
  }
  if (!grepl('aria-label="Feedback do registro"', h, fixed = TRUE)) {
    fail("s13a: feedback region missing the static aria-label: ", h)
  }
})

## (13a2) error -> ok transition: feedback() is last-event, not an append, so a
## successful pick after an error replaces the red line with the green one.
s13a2_path <- file.path(tempdir(), "warroom-s13a2", "draft.rds")
unlink(dirname(s13a2_path), recursive = TRUE)
shiny::testServer(.s8_bake_server(snap, s13a2_path, cfg), {
  session$setInputs(draft_btn = 1)                 # empty-selection error
  if (!grepl("draft-feedback--error", .s13_fb(output), fixed = TRUE)) {
    fail("s13a2: setup error not shown")
  }
  pid <- view()$available$player_id[1]
  session$setInputs(player_query = .s16_query_for(snap, pid))
  session$setInputs(draft_btn = 2)
  h <- .s13_fb(output)
  if (!grepl("draft-feedback--ok", h, fixed = TRUE) ||
      grepl("draft-feedback--error", h, fixed = TRUE)) {
    fail("s13a2: successful pick did not clear the prior error line: ", h)
  }
})

## (13b) Selecao vazia -> pre-check, draft-feedback--error, state intact.
s13b_path <- file.path(tempdir(), "warroom-s13b", "draft.rds")
unlink(dirname(s13b_path), recursive = TRUE)
shiny::testServer(.s8_bake_server(snap, s13b_path, cfg), {
  before <- nrow(state()$picks)
  session$setInputs(draft_btn = 1)   # player_query still NULL
  h <- .s13_fb(output)
  if (!grepl("draft-feedback--error", h, fixed = TRUE) ||
      !grepl(s13_empty, h, fixed = TRUE)) {
    fail("s13b: empty selection did not render the error microcopy: ", h)
  }
  if (nrow(state()$picks) != before) fail("s13b: empty-selection click changed state()")
})

## (13c) Jogador ja escolhido -> draft-feedback--error, "Ja escolhido no pick N"
## with N == overall of the existing pick; pick count unchanged.
s13c_path <- file.path(tempdir(), "warroom-s13c", "draft.rds")
unlink(dirname(s13c_path), recursive = TRUE)
shiny::testServer(.s8_bake_server(snap, s13c_path, cfg), {
  pid <- view()$available$player_id[1]
  session$setInputs(player_query = .s16_query_for(snap, pid))
  session$setInputs(draft_btn = 1)
  n      <- state()$picks$overall[match(pid, state()$picks$player_id)]
  after1 <- nrow(state()$picks)
  ## story 16: typing a drafted player's name yields resolve_player() "none", so
  ## the already-drafted branch of do_pick() is exercised directly -- the exact
  ## function a "Registrar" / search-result click ends in (same approach as s14d,
  ## which reads feedback() rather than the rendered region after a bare call).
  do_pick(pid, "unused")
  fb <- feedback()
  if (!identical(fb$kind, "error") || !grepl(s13_already(n), fb$text, fixed = TRUE)) {
    fail("s13c: re-draft did not produce the 'Ja escolhido no pick N' error: ", fb$text)
  }
  if (nrow(state()$picks) != after1) fail("s13c: rejected re-draft changed the pick count")
})

## (13d) Undo com pick -> draft-feedback--ok, "Undo aplicado - pick N voltou a
## aberto" with N == overall of the removed pick (captured before undo_pick()).
s13d_path <- file.path(tempdir(), "warroom-s13d", "draft.rds")
unlink(dirname(s13d_path), recursive = TRUE)
shiny::testServer(.s8_bake_server(snap, s13d_path, cfg), {
  pid <- view()$available$player_id[1]
  session$setInputs(player_query = .s16_query_for(snap, pid))
  session$setInputs(draft_btn = 1)
  n <- state()$picks$overall[nrow(state()$picks)]
  session$setInputs(undo_btn = 1)
  h <- .s13_fb(output)
  if (!grepl("draft-feedback--ok", h, fixed = TRUE) ||
      !grepl(s13_undo(n), h, fixed = TRUE)) {
    fail("s13d: undo with a pick did not render the ok microcopy: ", h)
  }
  if (nrow(state()$picks) != 0L) fail("s13d: undo did not remove the pick")
})

## (13e) Undo sem pick -> draft-feedback--error, own message (never the core
## conditionMessage), state intact.
s13e_path <- file.path(tempdir(), "warroom-s13e", "draft.rds")
unlink(dirname(s13e_path), recursive = TRUE)
shiny::testServer(.s8_bake_server(snap, s13e_path, cfg), {
  session$setInputs(undo_btn = 1)
  h <- .s13_fb(output)
  if (!grepl("draft-feedback--error", h, fixed = TRUE) ||
      !grepl(s13_noundo, h, fixed = TRUE)) {
    fail("s13e: undo with no pick did not render 'Nada a desfazer': ", h)
  }
  if (grepl("no picks to undo", h, fixed = TRUE)) {
    fail("s13e: undo error leaked the core conditionMessage")
  }
  if (nrow(state()$picks) != 0L) fail("s13e: undo on empty draft changed state()")
})

## (13e2) No-match query -> resolve_player() "none" -> do_pick(NA) -> the shared
## empty-selection branch, state intact. Story 16: an invalid player_id can no
## longer reach record_pick() (the search box only ever yields available
## players); do_pick's generic "Pick nao registrado:" else branch is still
## covered by the save_state() failure in 13e3.
s13e2_path <- file.path(tempdir(), "warroom-s13e2", "draft.rds")
unlink(dirname(s13e2_path), recursive = TRUE)
shiny::testServer(.s8_bake_server(snap, s13e2_path, cfg), {
  before <- nrow(state()$picks)
  session$setInputs(player_query = "zzzz")
  session$setInputs(draft_btn = 1)
  h <- .s13_fb(output)
  if (!grepl("draft-feedback--error", h, fixed = TRUE) ||
      !grepl(s13_empty, h, fixed = TRUE)) {
    fail("s13e2: no-match query did not render the empty-selection error: ", h)
  }
  if (grepl("draft-feedback--ok", h, fixed = TRUE)) fail("s13e2: no-match query rendered an ok line")
  if (nrow(state()$picks) != before) fail("s13e2: no-match query changed state()")
})

## (13e3) Falha de save_state(): commit_state() raises inside save_state() ->
## the generic else branch (not "already drafted"); state() intact (pick not
## confirmed) and the error line persists across an unrelated input change.
## The state dir is made unwritable after init so the atomic write of the next
## pick fails. Skipped -- not failed -- where chmod is a no-op (suite running
## as root in CI/Docker), detected by a post-chmod write probe.
s13e3_path <- file.path(tempdir(), "warroom-s13e3", "draft.rds")
unlink(dirname(s13e3_path), recursive = TRUE)
save_state(new_draft(snap, team_order, "Team 01", league = league), s13e3_path)
s13e3_dir <- dirname(s13e3_path)
Sys.chmod(s13e3_dir, "0500")
s13e3_probe <- file.path(s13e3_dir, ".probe")
if (isTRUE(suppressWarnings(file.create(s13e3_probe)))) {
  unlink(s13e3_probe)
  Sys.chmod(s13e3_dir, "0700")
  cat("s13e3: state dir still writable after chmod (root?) -- save-failure assertions skipped\n")
} else {
  s13e3_ok <- tryCatch({
    shiny::testServer(.s8_bake_server(snap, s13e3_path, cfg), {
      before <- nrow(state()$picks)
      pid <- view()$available$player_id[1]
      session$setInputs(player_query = .s16_query_for(snap, pid))
      session$setInputs(draft_btn = 1)
      h <- .s13_fb(output)
      if (!grepl("draft-feedback--error", h, fixed = TRUE) ||
          !grepl("Pick n\u00e3o registrado:", h, fixed = TRUE)) {
        fail("s13e3: save_state failure did not render 'Pick nao registrado:': ", h)
      }
      if (nrow(state()$picks) != before) fail("s13e3: pick shown as confirmed despite save failure")
      session$setInputs(pos_filter = "RB")
      if (!grepl("Pick n\u00e3o registrado:", .s13_fb(output), fixed = TRUE)) {
        fail("s13e3: save-failure error line did not persist")
      }
    })
    TRUE
  }, finally = Sys.chmod(s13e3_dir, "0700"))
  if (!isTRUE(s13e3_ok)) fail("s13e3: save_state-failure scenario did not complete")
}

## (13f) Persistencia do erro: after an error, neither an unrelated input
## change nor elapsed time clears the region -- there is no timer /
## invalidateLater that would dismiss it (DESIGN.md "erros persistem ...").
s13f_path <- file.path(tempdir(), "warroom-s13f", "draft.rds")
unlink(dirname(s13f_path), recursive = TRUE)
shiny::testServer(.s8_bake_server(snap, s13f_path, cfg), {
  session$setInputs(draft_btn = 1)   # empty-selection error
  if (!grepl(s13_empty, .s13_fb(output), fixed = TRUE)) fail("s13f: setup error not shown")
  session$setInputs(pos_filter = "RB")
  if (!grepl(s13_empty, .s13_fb(output), fixed = TRUE)) {
    fail("s13f: unrelated input change cleared the feedback region")
  }
  session$elapse(60000)
  if (!grepl(s13_empty, .s13_fb(output), fixed = TRUE)) {
    fail("s13f: feedback region auto-cleared after elapsed time (a timer crept in)")
  }
})

## (13g) Estado inicial: no event -> empty div.draft-feedback (no modifier).
s13g_path <- file.path(tempdir(), "warroom-s13g", "draft.rds")
unlink(dirname(s13g_path), recursive = TRUE)
shiny::testServer(.s8_bake_server(snap, s13g_path, cfg), {
  h <- .s13_fb(output)
  if (!grepl('class="draft-feedback"', h, fixed = TRUE)) {
    fail("s13g: initial feedback region is not a bare .draft-feedback div: ", h)
  }
  if (.html_count(h, "draft-feedback--") != 0L) {
    fail("s13g: initial feedback region already carries an --ok/--error modifier: ", h)
  }
})

## (13h) www/styles.css absent at runtime -> the region still assembles with no
## server error. Same swap-and-restore as (12i).
s13h_state <- new_draft(snap, team_order, "Team 01", league = league)
s13h_path  <- file.path(tempdir(), "warroom-s13hcss", "draft.rds")
unlink(dirname(s13h_path), recursive = TRUE)
save_state(s13h_state, s13h_path)
s13h_bak <- file.path(tempdir(), "styles.css.s13bak")
if (!file.copy("www/styles.css", s13h_bak, overwrite = TRUE)) {
  fail("s13: could not stage a backup of www/styles.css for the css-absent check")
}
s13h_seen <- NULL
s13h_ok <- tryCatch({
  if (!file.remove("www/styles.css")) stop("could not remove www/styles.css")
  s13_env <- new.env(parent = globalenv())
  suppressMessages(sys.source("app.R", envir = s13_env))
  srv <- s13_env$server
  formals(srv)$snapshot   <- snap
  formals(srv)$state_path <- s13h_path
  formals(srv)$config     <- cfg
  shiny::testServer(srv, {
    pid <- view()$available$player_id[1]
    session$setInputs(player_query = .s16_query_for(snap, pid))
    session$setInputs(draft_btn = 1)
    hh <- .strip_html(output$draft_feedback)
    s13h_seen <<- grepl("draft-feedback--ok", hh, fixed = TRUE)
  })
  isTRUE(s13h_seen)
}, error = function(e) structure(FALSE, msg = conditionMessage(e)),
   finally = {
     if (!file.exists("www/styles.css")) {
       file.copy(s13h_bak, "www/styles.css", overwrite = TRUE)
     }
   })
if (!file.exists("www/styles.css")) fail("s13: www/styles.css not restored after the css-absent check")
if (!isTRUE(s13h_ok)) fail("s13: feedback region did not assemble with www/styles.css absent: ",
                           attr(s13h_ok, "msg"))

## (13i) static UI + app.R + CSS analysis (Acceptance Criteria).
ui13 <- as.character(htmltools::renderTags(ui)$html)
if (!grepl('id="draft_feedback"', ui13, fixed = TRUE)) fail("s13: rendered ui has no id=\"draft_feedback\"")
p_ss13 <- regexpr('id="status_strip"', ui13, fixed = TRUE)
p_df13 <- regexpr('id="draft_feedback"', ui13, fixed = TRUE)
if (p_ss13 < 0L || p_df13 < 0L || p_df13 < p_ss13) {
  fail("s13: id=\"draft_feedback\" does not appear after id=\"status_strip\" in the UI")
}
for (id in c("status_strip", "recs_note", "recs_table", "recs_pos_filter",
             "roster_table", "recent_picks_table", "available_table",
             "player_query", "search_results", "draft_btn", "undo_btn",
             "pos_filter")) {
  if (!grepl(id, ui13, fixed = TRUE)) fail("s13: rendered ui lost the story 8-12 id '", id, "'")
}
app13 <- readLines("app.R", warn = FALSE, encoding = "UTF-8")
app13_all <- paste(app13, collapse = "\n")
if (any(grepl("showNotification", app13, fixed = TRUE))) fail("s13: app.R still calls showNotification()")
for (s in c('h4("Recomenda\u00e7\u00f5es")', 'h4("Dispon\u00edveis")',
            "Filtrar dispon\u00edveis por posi\u00e7\u00e3o",
            "buscar jogador dispon\u00edvel...",
            'actionButton("draft_btn", "Registrar"')) {
  if (!grepl(s, app13_all, fixed = TRUE)) fail("s13: app.R missing the accented string '", s, "'")
}
for (s in c("Recomendacoes", "Disponiveis", "disponiveis por posicao",
            "jogador disponivel...", 'actionButton("draft_btn", "Draft"')) {
  if (grepl(s, app13_all, fixed = TRUE)) fail("s13: app.R still carries the un-accented '", s, "'")
}
## story 16 (checkpoint Option A) allows exactly ONE tags$script in app.R -- the
## minimal Enter-key keydown handler. shinyjs / bslib / sass / includeCSS /
## Shiny.setInputValue stay vetoed; the single-script + clean-body assertion
## lives in the story 16 block.
if (any(grepl("bslib|sass|includeCSS|shinyjs|Shiny\\.setInputValue", app13))) {
  fail("s13: app.R introduced a forbidden JS / theming dependency")
}
if (any(grepl("pnorm\\(|rnorm\\(|runif\\(|\\bsample\\(", app13))) fail("s13: app.R names an RNG symbol")
if (any(grepl("ffanalytics|http[s]?://|\\bscrape\\b|httr::|curl::|download\\.file\\(", app13))) {
  fail("s13: app.R names a network / scrape symbol")
}
app13_code <- sub("#.*$", "", app13)
if (any(grepl("^\\s*(record_pick|undo_pick|recommend_players)\\s*<-", app13_code))) {
  fail("s13: app.R redefines record_pick / undo_pick / recommend_players")
}
if (sum(grepl("recommend_players\\(", app13_code)) != 1L) {
  fail("s13: recommend_players() not called exactly once in app.R code")
}
css13 <- paste(readLines("www/styles.css", warn = FALSE), collapse = "\n")
css13_code <- gsub("(?s)/\\*.*?\\*/", "", css13, perl = TRUE)
for (tok in c(".draft-feedback", ".draft-feedback--ok", ".draft-feedback--error")) {
  if (!grepl(tok, css13_code, fixed = TRUE)) fail("s13: styles.css missing '", tok, "'")
}
if (grepl("@import|url\\(\\s*['\"]?https?:|src:\\s*url\\(\\s*['\"]?https?:",
          css13_code, perl = TRUE)) {
  fail("s13: styles.css pulls a remote asset -- network on the live path")
}

cat("story 13 offline checks OK -- persistent pick/undo feedback region + microcopy pass\n")

## --- story 14: candidate-list readability + click-to-pick (offline) --------
## app.R promotes the .candidate content (reason/tier/score) to --ink and turns
## each smart-list row into a <button id="pick_row_k"> bound as a Shiny action
## button. A row click registers the player at rank k of the filtered frame via
## the SAME do_pick() the "Registrar" button uses -- record_pick() stays a single
## code path and is never re-called by recommend_players() on a click. Reuses
## `fail`, `snap`, `team_order`, `cfg`, `league`, `.s8_bake_server`,
## `.strip_html`, `.s11_count`.

## shared mid-draft on-turn fixture: 23 picks -> overall 24 is Team 01 (user).
.s14_mid <- function() {
  st <- new_draft(snap, team_order, "Team 01", league = league)
  for (i in 1:23) st <- record_pick(st, snap$players$player_id[i], snap)
  st
}
mid14  <- .s14_mid()
term14 <- recommend_players(mid14, snap)
if (nrow(term14) < 5L) fail("s14: fixture mid-draft recs has < 5 rows -- precondition")
if (isTRUE(attr(term14, "off_turn"))) fail("s14: mid14 should be the user's own pick -- precondition")
if (length(unique(term14$player_id[1:3])) != 3L) fail("s14: fixture top-3 recs not distinct -- precondition")
rb14 <- term14$player_id[term14$pos == "RB"]
if (!length(rb14)) fail("s14: fixture mid-draft recs has no RB row -- precondition")

## (14a) click row 1, unfiltered -> record_pick() of rank-01, ok feedback, saved.
s14a_path <- file.path(tempdir(), "warroom-s14a", "draft.rds")
unlink(dirname(s14a_path), recursive = TRUE)
save_state(mid14, s14a_path)
shiny::testServer(.s8_bake_server(snap, s14a_path, cfg), {
  h <- .strip_html(output$recs_table)
  if (!grepl("<button", h, fixed = TRUE)) fail("s14: smart-list rows are not <button>: ", h)
  if (!grepl('id="pick_row_1"', h, fixed = TRUE)) fail("s14: no id=\"pick_row_1\" on row 1")
  if (!grepl('class="candidate action-button', h, fixed = TRUE)) {
    fail("s14: row class does not lead with 'candidate action-button': ", h)
  }
  ## role="listitem" is kept on the button so the .smart-list item count / index
  ## stays available to AT until story 23's listbox/option pass.
  if (!grepl('role="listitem"', h, fixed = TRUE)) fail("s14: row lost role=listitem")
  if (!grepl(sprintf('aria-label="Registrar %s"', term14$player[1]), h, fixed = TRUE)) {
    fail("s14: row 1 missing the 'Registrar <player>' aria-label: ", h)
  }
  if (.s11_count(h, 'class="candidate') != nrow(term14)) {
    fail("s14: story-11 candidate row count broke with the new class order")
  }
  before <- nrow(state()$picks)
  session$setInputs(pick_row_1 = 1)
  if (nrow(state()$picks) != before + 1L) fail("s14: click on row 1 did not record a pick")
  if (state()$picks$player_id[nrow(state()$picks)] != term14$player_id[1]) {
    fail("s14: click on row 1 recorded the wrong player")
  }
  fb <- feedback()
  if (!identical(fb$kind, "ok") || !grepl("Registrado:", fb$text, fixed = TRUE)) {
    fail("s14: click feedback is not the ok 'Registrado:' line: ", fb$text)
  }
})
d14a <- load_state(s14a_path)
if (nrow(d14a$picks) != 24L) fail("s14: click-registered pick not persisted to disk")
if (d14a$picks$player_id[24] != term14$player_id[1]) fail("s14: persisted click pick is the wrong player")

## (14a2) a click on a row past rank 1 registers that row's player -- every
## wired observer, not just pick_row_1 (guards an off-by-one in the observer loop
## vs the render loop).
s14a2_path <- file.path(tempdir(), "warroom-s14a2", "draft.rds")
unlink(dirname(s14a2_path), recursive = TRUE)
save_state(mid14, s14a2_path)
shiny::testServer(.s8_bake_server(snap, s14a2_path, cfg), {
  invisible(.strip_html(output$recs_table))  # flush so the pick_row_* observers baseline before the click
  before <- nrow(state()$picks)
  session$setInputs(pick_row_3 = 1)
  if (nrow(state()$picks) != before + 1L) fail("s14: click on row 3 did not record a pick")
  if (state()$picks$player_id[nrow(state()$picks)] != term14$player_id[3]) {
    fail("s14: click on row 3 registered the wrong player (observer<->render index mismatch?)")
  }
})

## (14b) click under a position badge -> registers the first RB of the frame.
## Setting the badge must not disturb recs() (the one recompute is on the pick
## that follows -- a legitimate state change); "never re-called on a filter or
## click" is also pinned by the once-only recommend_players() static check (14g)
## and story 11's badge test.
s14b_path <- file.path(tempdir(), "warroom-s14b", "draft.rds")
unlink(dirname(s14b_path), recursive = TRUE)
save_state(mid14, s14b_path)
shiny::testServer(.s8_bake_server(snap, s14b_path, cfg), {
  session$setInputs(recs_pos_filter = "RB")
  if (!identical(recs(), term14)) {
    fail("s14: setting the RB badge changed the recs() frame")
  }
  before <- nrow(state()$picks)
  session$setInputs(pick_row_1 = 1)
  if (nrow(state()$picks) != before + 1L) fail("s14: filtered row-1 click did not record a pick")
  if (state()$picks$player_id[nrow(state()$picks)] != rb14[1]) {
    fail("s14: filtered row-1 click did not register the first RB of recs()")
  }
})

## (14c) click a row index past the filtered frame -> the observer passes NA to
## do_pick(); shared empty branch: error feedback, state untouched.
s14c_path <- file.path(tempdir(), "warroom-s14c", "draft.rds")
unlink(dirname(s14c_path), recursive = TRUE)
save_state(mid14, s14c_path)
shiny::testServer(.s8_bake_server(snap, s14c_path, cfg), {
  session$setInputs(recs_pos_filter = "RB")
  oob_k <- nrow(recs_view()) + 1L
  if (oob_k > 10L) fail("s14: RB recs fill all 10 rows -- cannot exercise an out-of-range click")
  before <- nrow(state()$picks)
  do.call(session$setInputs, stats::setNames(list(1), sprintf("pick_row_%d", oob_k)))
  if (nrow(state()$picks) != before) fail("s14: out-of-range row click changed state")
  fb <- feedback()
  if (!identical(fb$kind, "error") || !grepl("não está mais na lista", fb$text, fixed = TRUE)) {
    fail("s14: out-of-range row click did not set the 'não está mais na lista' error: ", fb$text)
  }
})

## (14d) matrix row: a row click landing on an already-drafted player (rare
## race) -> the shared do_pick() already-drafted branch, state untouched. Driven
## through do_pick() directly (it is in server scope) -- the exact function a
## row click calls.
s14e_path <- file.path(tempdir(), "warroom-s14e", "draft.rds")
unlink(dirname(s14e_path), recursive = TRUE)
save_state(mid14, s14e_path)
shiny::testServer(.s8_bake_server(snap, s14e_path, cfg), {
  drafted_id <- state()$picks$player_id[1]
  before <- nrow(state()$picks)
  do_pick(drafted_id, "unused")
  if (nrow(state()$picks) != before) fail("s14: do_pick() on a drafted id changed state")
  fb <- feedback()
  if (!identical(fb$kind, "error") || !grepl("escolhido no pick", fb$text, fixed = TRUE)) {
    fail("s14: do_pick() on a drafted id did not produce the 'ja escolhido' error: ", fb$text)
  }
})

## (14e) regression: the "Registrar" button with no selection keeps the old
## search-box message (do_pick's caller-specific empty_msg).
s14d_path <- file.path(tempdir(), "warroom-s14d", "draft.rds")
unlink(dirname(s14d_path), recursive = TRUE)
save_state(mid14, s14d_path)
shiny::testServer(.s8_bake_server(snap, s14d_path, cfg), {
  session$setInputs(player_query = "")
  session$setInputs(draft_btn = 1)
  fb <- feedback()
  if (!identical(fb$kind, "error") ||
      !grepl("Selecione um jogador na busca", fb$text, fixed = TRUE)) {
    fail("s14: draft_btn empty-selection message changed: ", fb$text)
  }
})

## (14f) contrast: reason / tier / score render at var(--ink); rank and the
## column head stay var(--ink-muted); button.candidate reset + hover exist.
css14 <- paste(readLines("www/styles.css", warn = FALSE), collapse = "\n")
css14_code <- gsub("(?s)/\\*.*?\\*/", "", css14, perl = TRUE)
reason14 <- regmatches(css14_code,
  regexpr("\\.candidate \\.reason\\s*\\{[^}]*\\}", css14_code, perl = TRUE))
if (length(reason14) != 1L) fail("s14: no '.candidate .reason { }' rule in styles.css")
if (!grepl("color:\\s*var\\(--ink\\)", reason14, perl = TRUE) ||
    grepl("var\\(--ink-muted\\)", reason14, perl = TRUE)) {
  fail("s14: '.candidate .reason' is not at var(--ink): ", reason14)
}
ts14 <- regmatches(css14_code, regexpr(
  "\\.candidate \\.tier,\\s*\\.candidate \\.score\\s*\\{[^}]*color:[^}]*\\}",
  css14_code, perl = TRUE))
if (length(ts14) != 1L) fail("s14: no '.candidate .tier, .candidate .score { color: ... }' rule")
if (!grepl("color:\\s*var\\(--ink\\)", ts14, perl = TRUE) ||
    grepl("var\\(--ink-muted\\)", ts14, perl = TRUE)) {
  fail("s14: '.candidate .tier/.score' is not at var(--ink): ", ts14)
}
rank14 <- regmatches(css14_code,
  regexpr("\\.candidate \\.rank\\s*\\{[^}]*\\}", css14_code, perl = TRUE))
if (!length(rank14) || !grepl("var\\(--ink-muted\\)", rank14, perl = TRUE)) {
  fail("s14: '.candidate .rank' no longer at var(--ink-muted) -- decoration must stay muted")
}
if (!grepl("button\\.candidate\\s*\\{", css14_code, perl = TRUE)) {
  fail("s14: no 'button.candidate { }' UA-reset rule in styles.css")
}
if (!grepl("button.candidate:hover", css14_code, fixed = TRUE)) {
  fail("s14: no 'button.candidate:hover' interaction affordance in styles.css")
}
if (!grepl("button.candidate:focus-visible", css14_code, fixed = TRUE)) {
  fail("s14: no 'button.candidate:focus-visible' -- keyboard focus less visible than hover")
}
if (grepl("@import|url\\(\\s*['\"]?https?:|src:\\s*url\\(\\s*['\"]?https?:",
          css14_code, perl = TRUE)) {
  fail("s14: styles.css pulls a remote asset -- network on the live path")
}

## (14g) static app.R analysis: single pick path, adapter stays thin.
app14 <- readLines("app.R", warn = FALSE)
if (any(grepl("bslib|sass|includeCSS|shinyjs|Shiny\\.setInputValue", app14))) {
  fail("s14: app.R introduced a forbidden JS / theming dependency")
}
if (any(grepl("pnorm\\(|rnorm\\(|runif\\(|\\bsample\\(", app14))) fail("s14: app.R names an RNG symbol")
if (any(grepl("ffanalytics|http[s]?://|\\bscrape\\b|httr::|curl::|download\\.file\\(", app14))) {
  fail("s14: app.R names a network / scrape symbol")
}
app14_code <- sub("#.*$", "", app14)
for (fn in c("record_pick", "undo_pick")) {
  if (sum(grepl(sprintf("%s\\(", fn), app14_code)) != 1L) {
    fail(sprintf("s14: %s() not called exactly once in app.R code -- single pick path", fn))
  }
}
if (sum(grepl("recommend_players\\(", app14_code)) != 1L) {
  fail("s14: recommend_players() not called exactly once in app.R code")
}
if (!any(grepl("do_pick\\s*<-\\s*function", app14_code))) fail("s14: app.R does not define do_pick()")
if (!any(grepl("recs_view\\s*<-\\s*reactive", app14_code))) fail("s14: app.R does not define recs_view()")
if (any(grepl("^\\s*(do_pick|recs_view)\\s*<<-", app14_code))) fail("s14: do_pick / recs_view use <<-")

## (14h) www/styles.css absent at runtime: the button list still assembles AND a
## row click still registers. Same swap-and-restore as the story 9 / 11 checks.
s14css_path <- file.path(tempdir(), "warroom-s14css", "draft.rds")
unlink(dirname(s14css_path), recursive = TRUE)
save_state(mid14, s14css_path)
s14_css_bak <- file.path(tempdir(), "styles.css.s14bak")
if (!file.copy("www/styles.css", s14_css_bak, overwrite = TRUE)) {
  fail("s14: could not stage a backup of www/styles.css for the css-absent check")
}
s14_css_seen <- NULL
s14_css_ok <- tryCatch({
  if (!file.remove("www/styles.css")) stop("could not remove www/styles.css")
  s14_env <- new.env(parent = globalenv())
  suppressMessages(sys.source("app.R", envir = s14_env))
  srv <- s14_env$server
  formals(srv)$snapshot   <- snap
  formals(srv)$state_path <- s14css_path
  formals(srv)$config     <- cfg
  shiny::testServer(srv, {
    hh <- .strip_html(output$recs_table)
    b0 <- nrow(state()$picks)
    session$setInputs(pick_row_1 = 1)
    s14_css_seen <<- grepl("<button", hh, fixed = TRUE) &&
      .s11_count(hh, 'class="candidate') > 0L &&
      nrow(state()$picks) == b0 + 1L
  })
  isTRUE(s14_css_seen)
}, error = function(e) structure(FALSE, msg = conditionMessage(e)),
   finally = {
     if (!file.exists("www/styles.css")) {
       file.copy(s14_css_bak, "www/styles.css", overwrite = TRUE)
     }
   })
if (!file.exists("www/styles.css")) fail("s14: www/styles.css not restored after the css-absent check")
if (!isTRUE(s14_css_ok)) {
  fail("s14: button list / click did not work with www/styles.css absent: ",
       attr(s14_css_ok, "msg"))
}

cat("story 14 offline checks OK -- candidate-list --ink content + click-to-pick buttons\n")

## --- story 15: all-team rosters panel (offline, renderUI over view()$rosters) --
## app.R factors the story-12 grouped roster panel into a local roster_panel_ui()
## and adds output$all_rosters_table -- a renderUI that emits ONLY the
## .all-rosters-grid (one .team-roster card per team in state()$team_order, each
## panel built by the SAME roster_panel_ui(): one slotting path, AGENTS.md). The
## native <details class="all-rosters" open> / <summary> that collapses the
## section live in the STATIC ui tree (not the renderUI), so the operator's
## collapse survives every per-pick re-render. view()$rosters is indexed by
## position (built as lapply(seq_along(team_order), ...)). The operator's own
## team card carries a textual "VOCE" tag and an --ink (not --focus) border.
## Mirrors the terminal's /teams command. Reuses `fail`, `snap`, `team_order`,
## `cfg`, `league`, `.s8_bake_server`, `.strip_html`, `.html_count`, and the
## story-12 helpers `.s12_state`, `.s12_group`, `.s12_filled`, `s12_name`,
## `s12_open`.

s15_you <- "VOCÊ"  # "VOCE" with the circumflex, as rendered in the card head

.s15_render <- function(st, snapshot = snap) {
  p <- file.path(tempdir(), "warroom-s15", "draft.rds")
  unlink(dirname(p), recursive = TRUE)
  save_state(st, p)
  out <- NULL
  shiny::testServer(.s8_bake_server(snapshot, p, cfg), {
    out <<- .strip_html(output$all_rosters_table)
  })
  out
}

## HTML of the one .team-roster card for `team`. Sliced from the card's opening
## <div class="team-roster..."> (NOT the inner name span) so the --you class on
## that div is inside the slice and the per-card negative check is real.
.s15_card <- function(h, team) {
  opens <- gregexpr('<div class="team-roster( team-roster--you)?">', h, perl = TRUE)[[1]]
  if (length(opens) == 1L && opens[1] == -1L) fail("s15: no .team-roster divs: ", h)
  name <- sprintf('<span class="team-roster-name">%s</span>', team)
  j <- regexpr(name, h, fixed = TRUE)
  if (j < 0L) fail("s15: panel has no card for '", team, "': ", h)
  s <- max(opens[opens < j])
  e <- if (any(opens > j)) min(opens[opens > j]) - 1L else nchar(h)
  substring(h, s, e)
}

## (15a) mid-draft: the grid renders 12 cards in team_order order.
s15_mid <- .s12_state(c("SYN-QB-001", "SYN-RB-001"))
h15 <- .s15_render(s15_mid)
if (!grepl('<div class="all-rosters-grid">', h15, fixed = TRUE)) {
  fail("s15: output$all_rosters_table did not render the .all-rosters-grid: ", h15)
}
if (grepl("<details", h15, fixed = TRUE)) {
  fail("s15: the <details> must live in the static ui, not output$all_rosters_table")
}
if (.html_count(h15, 'class="team-roster-name"') != 12L) {
  fail("s15: not 12 team cards: ", .html_count(h15, 'class="team-roster-name"'))
}
s15_prev <- 0L
for (tm in team_order) {
  pp <- regexpr(sprintf('<span class="team-roster-name">%s</span>', tm), h15, fixed = TRUE)
  if (pp < 0L) fail("s15: no card for ", tm)
  if (pp < s15_prev) fail("s15: cards not rendered in team_order")
  s15_prev <- pp
}

## (15b) the operator's team is marked -- textual tag + class, on that card only.
if (.html_count(h15, 'class="team-roster team-roster--you"') != 1L) {
  fail("s15: not exactly one .team-roster--you card")
}
if (.html_count(h15, sprintf('<span class="team-roster-you">%s</span>', s15_you)) != 1L) {
  fail("s15: the 'VOCE' tag is not on exactly one card")
}
s15_c_you <- .s15_card(h15, "Team 01")
if (!grepl("team-roster--you", s15_c_you, fixed = TRUE)) fail("s15: operator card lost the --you class")
if (!grepl(s15_you, s15_c_you, fixed = TRUE)) fail("s15: operator card 'Team 01' has no VOCE tag")
s15_c_opp <- .s15_card(h15, "Team 02")
if (grepl("team-roster--you", s15_c_opp, fixed = TRUE) || grepl(s15_you, s15_c_opp, fixed = TRUE)) {
  fail("s15: an opponent card is marked as the operator's")
}

## (15c) the operator card is built by roster_panel_ui() -- same filled slot the
## story-12 operator panel produces, three groups; its aria-label names the team.
if (!.s12_filled(.s12_group(s15_c_you, "Titulares"), "QB", s12_name("SYN-QB-001"))) {
  fail("s15: operator card QB slot not filled by roster_panel_ui()")
}
if (.html_count(s15_c_you, '<div class="roster-group">') != 3L) fail("s15: operator card not 3 groups")
## each card's panel aria-label names its own team (not "Roster do operador",
## which is the dedicated output$roster_table only).
if (!grepl('aria-label="Roster Team 01"', s15_c_you, fixed = TRUE)) {
  fail("s15: operator card panel aria-label is not \"Roster Team 01\"")
}

## (15d) a partially-drafted opponent shows ITS OWN drafted players (not the
## operator's), plus explicit "- aberto" for its still-open starter slots. Under
## .s12_state(c("SYN-QB-001","SYN-RB-001")) the non-Team-01 picks are filled with
## setdiff(all_ids, those) in overall order: overall 2 -> fillers[1], 3 ->
## fillers[2], ... Team 03 (slot 3) holds overalls 3 and 22 => fillers[2] and
## fillers[21]. A regression that indexed every card by st$user_team / a fixed
## name would show SYN-QB-001 here instead.
s15_fill  <- setdiff(snap$players$player_id, c("SYN-QB-001", "SYN-RB-001"))
s15_t3_p1 <- s15_fill[2]
s15_t3_p2 <- s15_fill[21]
s15_c_t3  <- .s15_card(h15, "Team 03")
if (!grepl(s12_name(s15_t3_p1), s15_c_t3, fixed = TRUE) ||
    !grepl(s12_name(s15_t3_p2), s15_c_t3, fixed = TRUE)) {
  fail("s15: opponent 'Team 03' card does not show its own drafted players")
}
if (grepl(s12_name("SYN-QB-001"), s15_c_t3, fixed = TRUE)) {
  fail("s15: opponent 'Team 03' card shows the operator's QB -- cards not indexed per team")
}
if (grepl(s12_name(s15_t3_p1), s15_c_you, fixed = TRUE)) {
  fail("s15: the operator card shows an opponent's player -- cards not indexed per team")
}
if (!grepl(s12_open, s15_c_t3, fixed = TRUE)) {
  fail("s15: opponent 'Team 03' shows no '- aberto' for its unfilled starter slots")
}
if (.html_count(s15_c_t3, '<div class="roster-group">') != 3L) fail("s15: opponent card not 3 groups")
if (!grepl('aria-label="Roster Team 03"', s15_c_t3, fixed = TRUE)) {
  fail("s15: opponent card panel aria-label is not threaded per team (\"Roster Team 03\")")
}
## total .roster-row per card == sum(league$roster) (no bench surplus here).
if (.html_count(s15_c_you, '<div class="roster-row') != sum(league$roster)) {
  fail("s15: operator card .roster-row count != sum(league$roster): ",
       .html_count(s15_c_you, '<div class="roster-row'))
}

## (15e) draft not started: 12 cards, every panel empty, one "- aberto" per open
## starter/FLEX slot per card. The open count is derived from the league roster
## (all slots but BENCH) so a config change fails with a clear count, not a
## hardcoded mismatch.
s15_open_per_card <- sum(league$roster) - league$roster[["BENCH"]]
h15e <- .s15_render(.s12_state(character(0)))
if (.html_count(h15e, 'class="team-roster-name"') != 12L) fail("s15: empty-draft panel not 12 cards")
if (grepl('class="name"', h15e, fixed = TRUE)) fail("s15: empty-draft panel rendered a filled .name row")
if (.html_count(h15e, sprintf('<span class="empty">%s</span>', s12_open)) !=
    s15_open_per_card * 12L) {
  fail("s15: empty-draft panel not ", s15_open_per_card, " '- aberto' placeholders per card x 12")
}

## (15f) nfl_team absent -> bare pos meta, never the string "NA".
snap15_nt <- snap
snap15_nt$players$nfl_team <- NULL
h15nt <- .s15_render(.s12_state(c("SYN-QB-001"), snap15_nt), snap15_nt)
if (grepl(">NA<", h15nt, fixed = TRUE) || grepl("NA</span>", h15nt, fixed = TRUE)) {
  fail("s15: all-team panel emitted the string 'NA' for a missing nfl_team")
}

## (15g) www/styles.css absent at runtime -> the grid still assembles (same
## swap-and-restore as the story 11 / 12 / 14 css-absent checks).
s15_css_path <- file.path(tempdir(), "warroom-s15css", "draft.rds")
unlink(dirname(s15_css_path), recursive = TRUE)
save_state(.s12_state(c("SYN-QB-001", "SYN-RB-001")), s15_css_path)
s15_css_bak <- file.path(tempdir(), "styles.css.s15bak")
if (!file.copy("www/styles.css", s15_css_bak, overwrite = TRUE)) {
  fail("s15: could not stage a backup of www/styles.css for the css-absent check")
}
s15_css_seen <- NULL
s15_css_ok <- tryCatch({
  if (!file.remove("www/styles.css")) stop("could not remove www/styles.css")
  s15_env <- new.env(parent = globalenv())
  suppressMessages(sys.source("app.R", envir = s15_env))
  srv <- s15_env$server
  formals(srv)$snapshot   <- snap
  formals(srv)$state_path <- s15_css_path
  formals(srv)$config     <- cfg
  shiny::testServer(srv, {
    hh <- .strip_html(output$all_rosters_table)
    s15_css_seen <<- grepl('<div class="all-rosters-grid">', hh, fixed = TRUE) &&
      .html_count(hh, 'class="team-roster-name"') == 12L
  })
  isTRUE(s15_css_seen)
}, error = function(e) structure(FALSE, msg = conditionMessage(e)),
   finally = {
     if (!file.exists("www/styles.css")) {
       file.copy(s15_css_bak, "www/styles.css", overwrite = TRUE)
     }
   })
if (!file.exists("www/styles.css")) fail("s15: www/styles.css not restored after the css-absent check")
if (!isTRUE(s15_css_ok)) fail("s15: all-team grid did not assemble with www/styles.css absent: ",
                              attr(s15_css_ok, "msg"))

## (15h) operator collapses the panel: the <details> is static ui, so a re-render
## of output$all_rosters_table (a pick) never re-emits it -- the grid content is
## all that changes. Verified structurally: the renderUI output has no <details>
## (asserted in 15a); the static ui has <details ... open> (asserted in 15j).

## (15i) user_team other than "Team 01" -- the "VOCE" tag lands on that card.
s15_u      <- "Team 07"
s15_sched  <- make_snake_schedule(league$teams, league$rounds)
s15_u_slot <- which(team_order == s15_u)
s15_u_ov   <- s15_sched$overall[s15_sched$slot == s15_u_slot]
s15_m      <- s15_u_ov[2]
s15_is_u   <- s15_sched$slot[seq_len(s15_m)] == s15_u_slot
s15_upids  <- c("SYN-QB-001", "SYN-K-001")   # a K, to check opponent K-slot placement
s15u_fill  <- setdiff(snap$players$player_id, s15_upids)
s15_ids            <- character(s15_m)
s15_ids[s15_is_u]  <- s15_upids
s15_ids[!s15_is_u] <- s15u_fill[seq_len(sum(!s15_is_u))]
st07 <- new_draft(snap, team_order, s15_u, league = league)
st07$picks <- data.frame(
  overall    = seq_len(s15_m),
  player_id  = s15_ids,
  entered_at = as.POSIXct("2026-09-01 12:00:00", tz = "UTC") + seq_len(s15_m),
  stringsAsFactors = FALSE)
h15u <- .s15_render(st07)
if (.html_count(h15u, 'class="team-roster-name"') != 12L) fail("s15: Team 07 fixture not 12 cards")
if (.html_count(h15u, sprintf('<span class="team-roster-you">%s</span>', s15_you)) != 1L) {
  fail("s15: Team 07 fixture: 'VOCE' tag not on exactly one card")
}
if (!grepl(s15_you, .s15_card(h15u, "Team 07"), fixed = TRUE)) {
  fail("s15: 'VOCE' tag not on the 'Team 07' card when user_team = Team 07")
}
if (grepl(s15_you, .s15_card(h15u, "Team 01"), fixed = TRUE)) {
  fail("s15: 'VOCE' tag wrongly on 'Team 01' when user_team = Team 07")
}
## the K/DST-into-dedicated-Titulares-slot rule (story 12) also runs for an
## opponent card, not just the operator's.
if (!.s12_filled(.s12_group(.s15_card(h15u, "Team 07"), "Titulares"), "K",
                 s12_name("SYN-K-001"))) {
  fail("s15: opponent 'Team 07' K not placed in its Titulares K slot")
}
s15u_prev <- 0L
for (tm in team_order) {
  pp <- regexpr(sprintf('<span class="team-roster-name">%s</span>', tm), h15u, fixed = TRUE)
  if (pp < s15u_prev) fail("s15: Team 07 fixture cards not in team_order")
  s15u_prev <- pp
}

## (15j) static UI + CSS + app.R analysis (Acceptance Criteria).
ui15 <- as.character(htmltools::renderTags(ui)$html)
if (!grepl('id="all_rosters_table"', ui15, fixed = TRUE)) fail("s15: rendered ui has no id=\"all_rosters_table\"")
if (!grepl('<details class="all-rosters" open>', ui15, fixed = TRUE)) {
  fail("s15: static ui lacks '<details class=\"all-rosters\" open>' (must be open by default, in the ui)")
}
p_det <- regexpr('<details class="all-rosters" open>', ui15, fixed = TRUE)
p_uio <- regexpr('id="all_rosters_table"', ui15, fixed = TRUE)
if (p_uio < p_det) fail("s15: uiOutput(\"all_rosters_table\") is not inside the <details>")
if (!grepl("<h4>Rosters dos times</h4>", ui15, fixed = TRUE)) {
  fail("s15: section heading h4(\"Rosters dos times\") missing")
}
for (id in c("status_strip", "draft_feedback", "recs_table", "recs_pos_filter", "recs_note",
             "roster_table", "recent_picks_table", "available_table", "player_query",
             "search_results", "draft_btn", "undo_btn", "pos_filter")) {
  if (!grepl(id, ui15, fixed = TRUE)) fail("s15: rendered ui lost the story 8-14 id '", id, "'")
}
css15 <- paste(readLines("www/styles.css", warn = FALSE), collapse = "\n")
css15_code <- gsub("(?s)/\\*.*?\\*/", "", css15, perl = TRUE)
for (tok in c(".all-rosters", ".all-rosters-grid", ".team-roster", ".team-roster--you")) {
  if (!grepl(tok, css15_code, fixed = TRUE)) fail("s15: styles.css missing '", tok, "'")
}
if (!grepl("@media (max-width: 900px)", css15_code, fixed = TRUE)) {
  fail("s15: styles.css has no '@media (max-width: 900px)' rule for the narrow layout")
}
if (!grepl("grid-template-columns: 1fr", css15_code, fixed = TRUE)) {
  fail("s15: styles.css narrow layout does not collapse the grid to one column")
}
## the open-grid height cap + internal scroll must apply at ANY width -- it must
## exist BEFORE the @media block, not only inside it (round-1 amendment).
s15_media_at <- regexpr("@media (max-width: 900px)", css15_code, fixed = TRUE)
s15_cap_at   <- regexpr("\\.all-rosters\\[open\\][^{]*\\{[^}]*max-height[^}]*overflow-y:\\s*auto",
                        css15_code, perl = TRUE)
if (s15_cap_at < 0L) {
  fail("s15: no '.all-rosters[open] .all-rosters-grid' rule with max-height + overflow-y: auto")
}
if (s15_cap_at > s15_media_at) {
  fail("s15: the open-grid height cap is only inside @media -- a wide short viewport loses the scroll")
}
s15_you_rule <- regmatches(
  css15_code, regexpr("\\.team-roster--you\\s*\\{[^}]*\\}", css15_code, perl = TRUE))
if (length(s15_you_rule) != 1L) fail("s15: no '.team-roster--you { ... }' rule in styles.css")
if (grepl("var\\(--focus\\)", s15_you_rule)) {
  fail("s15: '.team-roster--you' uses var(--focus) -- blue is reserved for keyboard focus (DESIGN.md)")
}
if (grepl("@import|url\\(\\s*['\"]?https?:|src:\\s*url\\(\\s*['\"]?https?:",
          css15_code, perl = TRUE)) {
  fail("s15: styles.css pulls a remote asset -- network on the live path")
}
app15 <- readLines("app.R", warn = FALSE)
if (any(grepl("bslib|sass|includeCSS|shinyjs|Shiny\\.setInputValue", app15))) {
  fail("s15: app.R introduced a forbidden JS / theming dependency")
}
if (any(grepl("pnorm\\(|rnorm\\(|runif\\(|\\bsample\\(", app15))) fail("s15: app.R names an RNG symbol")
if (any(grepl("ffanalytics|http[s]?://|\\bscrape\\b|httr::|curl::|download\\.file\\(", app15))) {
  fail("s15: app.R names a network / scrape symbol")
}
app15_code <- sub("#.*$", "", app15)
if (any(grepl("^\\s*(roster_slots|recommend_players|derive_draft_view)\\s*<-", app15_code))) {
  fail("s15: app.R redefines a core function")
}
if (sum(grepl("recommend_players\\(", app15_code)) != 1L) {
  fail("s15: recommend_players() not called exactly once in app.R code")
}
if (sum(grepl("derive_draft_view\\(", app15_code)) != 1L) {
  fail("s15: derive_draft_view() not called exactly once in app.R code")
}
if (sum(grepl("roster_slots\\(", app15_code)) > 1L) {
  fail("s15: roster_slots() called more than once in app.R code (should be one call in roster_panel_ui)")
}

## (15k) the factored operator panel keeps the story-12 markup.
s15_op_path <- file.path(tempdir(), "warroom-s15op", "draft.rds")
unlink(dirname(s15_op_path), recursive = TRUE)
save_state(.s12_state(c("SYN-QB-001")), s15_op_path)
shiny::testServer(.s8_bake_server(snap, s15_op_path, cfg), {
  s15_op <- .strip_html(output$roster_table)
  if (!grepl('aria-label="Roster do operador"', s15_op, fixed = TRUE)) {
    fail("s15: factored operator panel lost aria-label=\"Roster do operador\"")
  }
  if (!grepl('class="roster-panel"', s15_op, fixed = TRUE)) fail("s15: operator panel lost .roster-panel")
})

## (15l) legacy state with one blank team_order entry (passes .warroom_validate_state
## -- only duplicates are caught): positional indexing keeps all 12 cards
## assembling, and the blank name falls back to "Time <i>" rather than "NA".
s15_blank <- .s12_state(c("SYN-QB-001"))
s15_blank$team_order[5] <- ""
h15b <- tryCatch(.s15_render(s15_blank),
                 error = function(e) fail("s15: blank team_order crashed the panel: ",
                                          conditionMessage(e)))
if (.html_count(h15b, 'class="team-roster-name"') != 12L) {
  fail("s15: blank team_order did not still render 12 cards")
}
if (!grepl('<span class="team-roster-name">Time 5</span>', h15b, fixed = TRUE)) {
  fail("s15: blank team name did not fall back to 'Time 5': ", h15b)
}
if (grepl('<span class="team-roster-name">NA</span>', h15b, fixed = TRUE) ||
    grepl('aria-label="Roster NA"', h15b, fixed = TRUE)) {
  fail("s15: blank team name rendered the literal string 'NA'")
}

cat("story 15 offline checks OK -- all-team rosters panel renderUI over view()$rosters\n")

## --- story 16: search as a server-rendered combobox (offline) --------------
## app.R swaps selectizeInput("player_choice") for textInput("player_query") +
## uiOutput("search_results"). A keystroke recomputes only search_hits()
## (resolve_player() over view()$available + the full snapshot table) -- never
## recs() / recommend_players(). Each result row is a <button id="search_row_k">
## bound as a Shiny action button; row 1 carries .search-result--active and is
## what "Registrar" (and the tags$head Enter keydown script) register, through
## the SAME do_pick() path. Reuses `fail`, `snap`, `team_order`, `cfg`,
## `league`, `.s8_bake_server`, `.strip_html`, `.html_count`, `.s16_query_for`.

.s16_res <- function(output) .strip_html(output$search_results)

## on-turn mid-draft fixture: 23 picks -> overall 24 belongs to Team 01 (user).
s16_mid <- new_draft(snap, team_order, "Team 01", league = league)
for (i in 1:23) s16_mid <- record_pick(s16_mid, snap$players$player_id[i], snap)

## (16a) unique query, on the clock: row 1 is that player; a search_row_1 click
## records it via record_pick(); state grows by 1; ok feedback; state saved.
s16a_path <- file.path(tempdir(), "warroom-s16a", "draft.rds")
unlink(dirname(s16a_path), recursive = TRUE)
save_state(s16_mid, s16a_path)
shiny::testServer(.s8_bake_server(snap, s16a_path, cfg), {
  pid  <- view()$available$player_id[1]
  name <- .s16_query_for(snap, pid)
  session$setInputs(player_query = name)
  if (!identical(search_hits()$status, "unique")) fail("s16a: full name did not resolve uniquely")
  if (search_hits()$players$player_id[1] != pid) fail("s16a: hit 1 is not the queried player")
  h <- .s16_res(output)
  if (!grepl("<button", h, fixed = TRUE)) fail("s16a: search results are not <button>: ", h)
  if (!grepl('id="search_row_1"', h, fixed = TRUE)) fail("s16a: no id=\"search_row_1\": ", h)
  if (!grepl('class="search-result action-button', h, fixed = TRUE)) {
    fail("s16a: row class does not lead with 'search-result action-button': ", h)
  }
  if (!grepl("search-result--active", h, fixed = TRUE)) fail("s16a: row 1 not --active: ", h)
  if (!grepl(sprintf('aria-label="Registrar %s"', name), h, fixed = TRUE)) {
    fail("s16a: row 1 missing the 'Registrar <player>' aria-label: ", h)
  }
  before <- nrow(state()$picks)
  session$setInputs(search_row_1 = 1)
  if (nrow(state()$picks) != before + 1L) fail("s16a: search_row_1 click did not record a pick")
  if (state()$picks$player_id[nrow(state()$picks)] != pid) fail("s16a: click recorded the wrong player")
  fb <- feedback()
  if (!identical(fb$kind, "ok") ||
      !grepl(sprintf("Registrado: %s", name), fb$text, fixed = TRUE)) {
    fail("s16a: click feedback is not the ok 'Registrado:' line: ", fb$text)
  }
})
d16a <- load_state(s16a_path)
if (nrow(d16a$picks) != 24L) fail("s16a: click-registered pick not persisted to disk")

## (16b) "Registrar" with a 1-hit query -> same do_pick(); registers hit 1.
s16b_path <- file.path(tempdir(), "warroom-s16b", "draft.rds")
unlink(dirname(s16b_path), recursive = TRUE)
save_state(s16_mid, s16b_path)
shiny::testServer(.s8_bake_server(snap, s16b_path, cfg), {
  pid <- view()$available$player_id[2]
  session$setInputs(player_query = .s16_query_for(snap, pid))
  before <- nrow(state()$picks)
  session$setInputs(draft_btn = 1)
  if (nrow(state()$picks) != before + 1L) fail("s16b: Registrar did not record the single hit")
  if (state()$picks$player_id[nrow(state()$picks)] != pid) fail("s16b: Registrar recorded the wrong player")
})

## (16c) ambiguous query -> multiple rows, first --active, no pick until an
## action, and a keystroke does NOT recompute recs(); results are capped at
## search_result_cap (8 -- one constant, checked against the observer count in 16h).
s16c_path <- file.path(tempdir(), "warroom-s16c", "draft.rds")
unlink(dirname(s16c_path), recursive = TRUE)
save_state(s16_mid, s16c_path)
shiny::testServer(.s8_bake_server(snap, s16c_path, cfg), {
  recs_before <- recs()
  before      <- nrow(state()$picks)
  session$setInputs(player_query = "wr synthetic")
  if (!identical(search_hits()$status, "ambiguous")) fail("s16c: 'wr synthetic' did not resolve ambiguous")
  h <- .s16_res(output)
  if (.html_count(h, "search-result--active") != 1L) fail("s16c: not exactly one --active row: ", h)
  if (.html_count(h, 'id="search_row_') != 8L) fail("s16c: results not capped at 8 rows: ", h)
  if (nrow(state()$picks) != before) fail("s16c: an ambiguous query recorded a pick")
  if (!identical(recs(), recs_before)) fail("s16c: a keystroke recomputed recs()")
})

## (16d) no-result query -> the .search-empty line, state intact.
s16d_path <- file.path(tempdir(), "warroom-s16d", "draft.rds")
unlink(dirname(s16d_path), recursive = TRUE)
save_state(s16_mid, s16d_path)
shiny::testServer(.s8_bake_server(snap, s16d_path, cfg), {
  before <- nrow(state()$picks)
  session$setInputs(player_query = "zzzz")
  h <- .s16_res(output)
  if (!grepl('class="search-empty"', h, fixed = TRUE)) fail("s16d: no .search-empty line: ", h)
  if (!grepl("Nenhum jogador dispon\u00edvel corresponde", h, fixed = TRUE)) {
    fail("s16d: .search-empty text is not the EXPERIENCE.md string: ", h)
  }
  if (grepl("<button", h, fixed = TRUE)) fail("s16d: no-result query still rendered a row")
  if (nrow(state()$picks) != before) fail("s16d: no-result query changed state")
})

## (16e) empty query -- and a whitespace-only query -- both give an empty
## .search-results container (no rows, no .search-empty line): the trimws() in
## the search_hits reactive and the renderUI agree.
s16e_path <- file.path(tempdir(), "warroom-s16e", "draft.rds")
unlink(dirname(s16e_path), recursive = TRUE)
save_state(s16_mid, s16e_path)
shiny::testServer(.s8_bake_server(snap, s16e_path, cfg), {
  for (blank in c("", "   ", "\t ")) {
    session$setInputs(player_query = blank)
    h <- .s16_res(output)
    if (!grepl('class="search-results"', h, fixed = TRUE)) {
      fail("s16e: blank query [", blank, "] lost the container: ", h)
    }
    if (grepl("<button", h, fixed = TRUE)) fail("s16e: blank query [", blank, "] rendered rows: ", h)
    if (grepl("search-empty", h, fixed = TRUE)) {
      fail("s16e: blank query [", blank, "] rendered the no-result line: ", h)
    }
  }
})

## (16f) "Registrar" with an empty query -> empty-selection error, state intact.
s16f_path <- file.path(tempdir(), "warroom-s16f", "draft.rds")
unlink(dirname(s16f_path), recursive = TRUE)
save_state(s16_mid, s16f_path)
shiny::testServer(.s8_bake_server(snap, s16f_path, cfg), {
  before <- nrow(state()$picks)
  session$setInputs(player_query = "")
  session$setInputs(draft_btn = 1)
  fb <- feedback()
  if (!identical(fb$kind, "error") ||
      !grepl("Selecione um jogador na busca antes de registrar.", fb$text, fixed = TRUE)) {
    fail("s16f: Registrar with an empty query did not raise the empty-selection error: ", fb$text)
  }
  if (nrow(state()$picks) != before) fail("s16f: empty-query Registrar changed state")
})

## (16g) a search_row_k click past the hit count -> do_pick(NA): the
## caller-specific "Resultado de busca indisponivel" error, state intact.
s16g_path <- file.path(tempdir(), "warroom-s16g", "draft.rds")
unlink(dirname(s16g_path), recursive = TRUE)
save_state(s16_mid, s16g_path)
shiny::testServer(.s8_bake_server(snap, s16g_path, cfg), {
  pid <- view()$available$player_id[1]
  session$setInputs(player_query = .s16_query_for(snap, pid))
  if (nrow(search_hits()$players) != 1L) fail("s16g: precondition -- query is not a single hit")
  before <- nrow(state()$picks)
  session$setInputs(search_row_5 = 1)
  if (nrow(state()$picks) != before) fail("s16g: out-of-range search row click changed state")
  fb <- feedback()
  if (!identical(fb$kind, "error") ||
      !grepl("Resultado de busca indispon\u00edvel", fb$text, fixed = TRUE)) {
    fail("s16g: out-of-range click did not set the 'Resultado de busca indisponivel' error: ", fb$text)
  }
})

## (16g2) in-range boundary: an ambiguous query (>4 hits) + a search_row_4 click
## registers the 4th hit -- exercises the k <= nrow(h) guard from the in-range
## side, not only the out-of-range search_row_5 case above.
s16g2_path <- file.path(tempdir(), "warroom-s16g2", "draft.rds")
unlink(dirname(s16g2_path), recursive = TRUE)
save_state(s16_mid, s16g2_path)
shiny::testServer(.s8_bake_server(snap, s16g2_path, cfg), {
  session$setInputs(player_query = "wr synthetic")
  hits4 <- search_hits()$players$player_id
  if (length(hits4) < 4L) fail("s16g2: precondition -- 'wr synthetic' has < 4 hits")
  before <- nrow(state()$picks)
  session$setInputs(search_row_4 = 1)
  if (nrow(state()$picks) != before + 1L) fail("s16g2: search_row_4 click did not record a pick")
  if (state()$picks$player_id[nrow(state()$picks)] != hits4[4]) {
    fail("s16g2: search_row_4 registered the wrong hit (observer<->hit index mismatch?)")
  }
})

## (16h) static UI + app.R + the Enter script (Acceptance Criteria).
ui16 <- as.character(htmltools::renderTags(ui)$html)
for (id in c("status_strip", "draft_feedback", "recs_note", "recs_table", "recs_pos_filter",
             "roster_table", "recent_picks_table", "available_table",
             "player_query", "search_results", "draft_btn", "undo_btn", "pos_filter")) {
  if (!grepl(id, ui16, fixed = TRUE)) fail("s16: rendered ui lost the id '", id, "'")
}
if (grepl("player_choice", ui16, fixed = TRUE)) fail("s16: rendered ui still carries player_choice")
if (grepl("buscar jogador dispon\u00edvel...", ui16, fixed = TRUE) == FALSE) {
  fail("s16: the textInput placeholder lost the accented 'buscar jogador disponivel...'")
}
app16 <- readLines("app.R", warn = FALSE, encoding = "UTF-8")
if (any(grepl("selectizeInput|updateSelectizeInput|player_choice", app16))) {
  fail("s16: app.R still names selectizeInput / updateSelectizeInput / player_choice")
}
if (any(grepl("bslib|sass|includeCSS|shinyjs|Shiny\\.setInputValue", app16))) {
  fail("s16: app.R introduced a forbidden JS / theming dependency")
}
## Enter wiring (checkpoint Option A): exactly one tags$script, and nothing in
## app.R touches Shiny.* or the network -- the handler is plain DOM keydown.
i16_script <- grep("tags\\$script", app16)
if (length(i16_script) != 1L) {
  fail("s16: app.R must contain exactly one tags$script (the Enter keydown handler)")
}
if (any(grepl("Shiny\\.", app16))) fail("s16: app.R references Shiny.* -- the Enter script must be plain DOM")
if (any(grepl("fetch\\(|XMLHttpRequest|WebSocket|http[s]?://", app16))) {
  fail("s16: app.R script names a network symbol")
}
## Pin the Enter-script bridge: the handler must literally name each thing it
## couples -- the field id, both selectors it clicks, the DOM calls, and the two
## IME/auto-repeat guards. A rename on either side (or story 22 rewriting the
## Enter branch away) trips this.
s16_script_body <- paste(app16[i16_script:min(length(app16), i16_script + 12L)],
                         collapse = "\n")
for (tok in c("player_query", ".search-result--active", ".search-result",
              ".click(", "preventDefault", "isComposing", "e.repeat")) {
  if (!grepl(tok, s16_script_body, fixed = TRUE)) {
    fail("s16: the Enter keydown script lost the bridge token '", tok, "'")
  }
}
## Field-value reset: shiny::testServer does not reflect updateTextInput back
## into input$player_query, so this is pinned by source position instead -- the
## clear must sit in do_pick's success branch, right after commit_state(st) and
## right before the ok feedback(). (Story ## Verification carries the matching
## manual check.)
i16_clear <- grep('updateTextInput(session, "player_query", value = "")', app16, fixed = TRUE)
if (length(i16_clear) != 1L) {
  fail("s16: expected exactly one updateTextInput(session, \"player_query\", ...) call")
}
if (!any(grepl("commit_state(st)", app16[max(1L, i16_clear - 3L):(i16_clear - 1L)], fixed = TRUE))) {
  fail("s16: the player_query clear is not immediately after commit_state(st) in do_pick()")
}
if (!any(grepl('feedback(list(kind = "ok"',
               app16[(i16_clear + 1L):min(length(app16), i16_clear + 3L)], fixed = TRUE))) {
  fail("s16: the player_query clear is not immediately before the ok feedback() in do_pick()")
}
if (any(grepl("pnorm\\(|rnorm\\(|runif\\(|\\bsample\\(", app16))) fail("s16: app.R names an RNG symbol")
app16_code <- sub("#.*$", "", app16)
for (fn in c("resolve_player", "record_pick", "undo_pick", "recommend_players")) {
  if (sum(grepl(sprintf("%s\\(", fn), app16_code)) != 1L) {
    fail(sprintf("s16: %s() not called exactly once in app.R code", fn))
  }
}
## One result-cap constant: defined once, read by both the observer loop
## (seq_len) and the render cap (min) so they cannot drift from 8.
if (!any(grepl("search_result_cap <- 8L", app16_code, fixed = TRUE))) {
  fail("s16: app.R does not define the single result cap 'search_result_cap <- 8L'")
}
s16_cap_in_seq <- any(grepl("seq_len(search_result_cap)", app16_code, fixed = TRUE))
s16_cap_in_min <- any(grepl("min(search_result_cap", app16_code, fixed = TRUE))
if (!s16_cap_in_seq || !s16_cap_in_min) {
  fail("s16: search_result_cap is not reused by both the observer loop and the render cap")
}
css16 <- paste(readLines("www/styles.css", warn = FALSE), collapse = "\n")
css16_code <- gsub("(?s)/\\*.*?\\*/", "", css16, perl = TRUE)
for (tok in c(".search-results", ".search-result", ".search-result--active", ".search-empty")) {
  if (!grepl(tok, css16_code, fixed = TRUE)) fail("s16: styles.css missing '", tok, "'")
}
s16_active_rule <- regmatches(css16_code, regexpr(
  "\\.search-result--active[^{]*\\{[^}]*\\}", css16_code, perl = TRUE))
if (!length(s16_active_rule) || !grepl("var\\(--surface-raised\\)", paste(s16_active_rule, collapse = ""))) {
  fail("s16: '.search-result--active' background is not var(--surface-raised)")
}
## the results list is height-capped with an internal scroll so a full list does
## not push the Registrar / Undo buttons down (same containment as story 15).
s16_list_rule <- regmatches(css16_code, regexpr(
  "\\.search-results\\s*\\{[^}]*\\}", css16_code, perl = TRUE))
if (!length(s16_list_rule) ||
    !grepl("max-height", s16_list_rule, fixed = TRUE) ||
    !grepl("overflow-y", s16_list_rule, fixed = TRUE)) {
  fail("s16: '.search-results' has no max-height + overflow-y cap: ", s16_list_rule)
}
if (grepl("@import|url\\(\\s*['\"]?https?:|src:\\s*url\\(\\s*['\"]?https?:",
          css16_code, perl = TRUE)) {
  fail("s16: styles.css pulls a remote asset -- network on the live path")
}

## (16i) www/styles.css absent at runtime: the results list still assembles AND
## a search_row_1 click still registers. Same swap-and-restore as story 9 / 14.
s16css_path <- file.path(tempdir(), "warroom-s16css", "draft.rds")
unlink(dirname(s16css_path), recursive = TRUE)
save_state(s16_mid, s16css_path)
s16_css_bak <- file.path(tempdir(), "styles.css.s16bak")
if (!file.copy("www/styles.css", s16_css_bak, overwrite = TRUE)) {
  fail("s16: could not stage a backup of www/styles.css for the css-absent check")
}
s16_css_seen <- NULL
s16_css_ok <- tryCatch({
  if (!file.remove("www/styles.css")) stop("could not remove www/styles.css")
  s16_env <- new.env(parent = globalenv())
  suppressMessages(sys.source("app.R", envir = s16_env))
  srv <- s16_env$server
  formals(srv)$snapshot   <- snap
  formals(srv)$state_path <- s16css_path
  formals(srv)$config     <- cfg
  shiny::testServer(srv, {
    pid <- view()$available$player_id[1]
    session$setInputs(player_query = .s16_query_for(snap, pid))
    hh <- .strip_html(output$search_results)
    b0 <- nrow(state()$picks)
    session$setInputs(search_row_1 = 1)
    s16_css_seen <<- grepl("<button", hh, fixed = TRUE) &&
      nrow(state()$picks) == b0 + 1L &&
      state()$picks$player_id[nrow(state()$picks)] == pid
  })
  isTRUE(s16_css_seen)
}, error = function(e) structure(FALSE, msg = conditionMessage(e)),
   finally = {
     if (!file.exists("www/styles.css")) {
       file.copy(s16_css_bak, "www/styles.css", overwrite = TRUE)
     }
   })
if (!file.exists("www/styles.css")) fail("s16: www/styles.css not restored after the css-absent check")
if (!isTRUE(s16_css_ok)) {
  fail("s16: results list / click did not work with www/styles.css absent: ",
       attr(s16_css_ok, "msg"))
}

cat("story 16 offline checks OK -- textInput + resolve_player() search results + click/Enter to pick\n")

## --- story 17: panel-grid layout (offline, presentation only) --------------
## app.R restructures the ui tree into regions: .region--search (dominant query
## field) inside the one surviving fluidRow, then a div.warroom-main with
## .workspace (Recomendacoes | Disponiveis), .wide (Picks recentes | Seu roster)
## and .region--audit (the story-15 all-rosters <details>, moved unchanged).
## Presentation only -- server() unchanged, no new core call, no new tags$script.
## Reuses `fail`, `ui`.

ui17 <- as.character(htmltools::renderTags(ui)$html)
for (tok in c('class="workspace"', 'class="wide"', "region--search", "region--audit",
              "warroom-main")) {
  if (!grepl(tok, ui17, fixed = TRUE)) fail("s17: rendered ui missing '", tok, "'")
}
## every input/output id from stories 8-16 still in the ui, at the same ids.
for (id in c("status_strip", "draft_feedback", "recs_note", "recs_table",
             "recs_pos_filter", "pos_filter", "roster_table", "recent_picks_table",
             "available_table", "player_query", "search_results", "draft_btn",
             "undo_btn", "all_rosters_table")) {
  if (!grepl(id, ui17, fixed = TRUE)) fail("s17: rendered ui lost the story 8-16 id '", id, "'")
}
## status_strip then draft_feedback, both before the first `class="row"` (the
## search fluidRow) -- stories 10 / 13 pinned this order.
p_ss17  <- regexpr('id="status_strip"', ui17, fixed = TRUE)
p_df17  <- regexpr('id="draft_feedback"', ui17, fixed = TRUE)
p_row17 <- regexpr('class="row"', ui17, fixed = TRUE)
if (p_ss17 < 0L || p_df17 < 0L || p_row17 < 0L ||
    p_ss17 > p_df17 || p_df17 > p_row17) {
  fail("s17: status_strip / draft_feedback are not both ahead of the first class=\"row\"")
}
## the <details class="all-rosters" open> (story 15) still static and open.
if (!grepl('<details class="all-rosters" open>', ui17, fixed = TRUE)) {
  fail("s17: static ui lost '<details class=\"all-rosters\" open>'")
}

## CSS: .workspace / .wide are two-column grids, collapsing to one column in an
## @media (max-width: 900px); story 15's open-grid cap still precedes the first
## @media occurrence.
css17      <- paste(readLines("www/styles.css", warn = FALSE), collapse = "\n")
css17_code <- gsub("(?s)/\\*.*?\\*/", "", css17, perl = TRUE)
for (tok in c(".warroom-main", ".region--search", ".region-actions",
              ".workspace", ".wide")) {
  if (!grepl(tok, css17_code, fixed = TRUE)) fail("s17: styles.css missing '", tok, "'")
}
s17_ws_rule <- regmatches(css17_code, regexpr("\\.workspace\\s*\\{[^}]*\\}", css17_code, perl = TRUE))
s17_wd_rule <- regmatches(css17_code, regexpr("\\.wide\\s*\\{[^}]*\\}", css17_code, perl = TRUE))
if (!length(s17_ws_rule) || !grepl("display:\\s*grid", s17_ws_rule)) {
  fail("s17: '.workspace' is not display: grid: ", s17_ws_rule)
}
if (!length(s17_wd_rule) || !grepl("display:\\s*grid", s17_wd_rule)) {
  fail("s17: '.wide' is not display: grid: ", s17_wd_rule)
}
if (!grepl("grid-template-columns:[^;]+minmax", paste(s17_ws_rule, s17_wd_rule), perl = TRUE)) {
  fail("s17: '.workspace' / '.wide' are not two-column (minmax) grids")
}
## the narrow @media: at least ONE '@media (max-width: 900px)' block must
## collapse .workspace/.wide to a single column. Scan every match rather than
## demand a second literal block -- a future harmless merge of story 15's and
## story 17's identical media queries into one block must stay legal.
s17_media_at <- gregexpr("@media (max-width: 900px)", css17_code, fixed = TRUE)[[1]]
if (s17_media_at[1] < 0L) {
  fail("s17: no '@media (max-width: 900px)' rule for the narrow layout")
}
s17_narrow_ok <- FALSE
for (s17_at in s17_media_at) {
  blk <- regmatches(substring(css17_code, s17_at), regexpr(
    "@media[^{]*\\{(?:[^{}]*\\{[^{}]*\\})*[^{}]*\\}",
    substring(css17_code, s17_at), perl = TRUE))
  if (length(blk) && grepl("\\.workspace", blk) && grepl("\\.wide", blk) &&
      grepl("grid-template-columns:\\s*1fr", blk)) {
    s17_narrow_ok <- TRUE
    break
  }
}
if (!s17_narrow_ok) {
  fail("s17: no '@media (max-width: 900px)' block collapses .workspace/.wide to grid-template-columns: 1fr")
}
## story 15's open-grid height cap must still precede the FIRST @media (its own
## assertion); re-checked here so the new block did not reorder it.
s17_cap_at <- regexpr("\\.all-rosters\\[open\\][^{]*\\{[^}]*max-height[^}]*overflow-y:\\s*auto",
                      css17_code, perl = TRUE)
if (s17_cap_at < 0L || s17_cap_at > s17_media_at[1]) {
  fail("s17: story 15's open-grid cap no longer precedes the first @media")
}
if (grepl("@import|url\\(\\s*['\"]?https?:", css17_code, perl = TRUE)) {
  fail("s17: styles.css pulls a remote asset -- network on the live path")
}

## app.R static: presentation-only. Each core function called exactly once; one
## tags$script; no forbidden theming/JS dep; no network / RNG symbol.
app17 <- readLines("app.R", warn = FALSE, encoding = "UTF-8")
if (any(grepl("bslib|sass|includeCSS|shinyjs|Shiny\\.setInputValue", app17))) {
  fail("s17: app.R introduced a forbidden JS / theming dependency")
}
if (sum(grepl("tags\\$script", app17)) != 1L) {
  fail("s17: app.R must still contain exactly one tags$script (the Enter keydown handler)")
}
if (any(grepl("pnorm\\(|rnorm\\(|runif\\(|\\bsample\\(", app17))) fail("s17: app.R names an RNG symbol")
if (any(grepl("ffanalytics|http[s]?://|\\bscrape\\b|httr::|curl::|download\\.file\\(", app17))) {
  fail("s17: app.R names a network / scrape symbol")
}
app17_code <- sub("#.*$", "", app17)
for (fn in c("recommend_players", "derive_draft_view", "resolve_player",
             "record_pick", "undo_pick")) {
  if (sum(grepl(sprintf("%s\\(", fn), app17_code)) != 1L) {
    fail(sprintf("s17: %s() not called exactly once in app.R code", fn))
  }
}

## www/styles.css absent at runtime: the ui still mounts and shinyApp() returns a
## shiny.appobj. Same swap-and-restore as stories 9 / 11 / 12 / 15 / 16.
s17_css_bak <- file.path(tempdir(), "styles.css.s17bak")
if (!file.copy("www/styles.css", s17_css_bak, overwrite = TRUE)) {
  fail("s17: could not stage a backup of www/styles.css for the css-absent check")
}
s17_ok <- tryCatch({
  if (!file.remove("www/styles.css")) stop("could not remove www/styles.css")
  s17_env <- new.env(parent = globalenv())
  suppressMessages(sys.source("app.R", envir = s17_env))
  htmltools::renderTags(s17_env$ui)
  inherits(shiny::shinyApp(s17_env$ui, s17_env$server), "shiny.appobj")
}, error = function(e) structure(FALSE, msg = conditionMessage(e)),
   finally = {
     if (!file.exists("www/styles.css")) {
       file.copy(s17_css_bak, "www/styles.css", overwrite = TRUE)
     }
   })
if (!file.exists("www/styles.css")) fail("s17: www/styles.css not restored after the css-absent check")
if (!isTRUE(s17_ok)) fail("s17: app assembly errored with www/styles.css absent: ", attr(s17_ok, "msg"))

cat("story 17 offline checks OK -- panel-grid regions (.warroom-main / .workspace / .wide / .region--*)\n")

## --- prepare.R immutability guard (one offline subprocess) -------------------
## data/projections.rds exists (this test just wrote it), so `Rscript
## scripts/prepare.R` with no --force must refuse. The guard is placed above the
## first ffanalytics reference in prepare.R; the fast clean exit here (well under
## the ~30s an ffanalytics load costs) is the evidence it did not reach a scrape.
if (file.exists(snapshot_path)) {
  t_pg <- Sys.time()
  pg <- suppressWarnings(system2("Rscript", "scripts/prepare.R",
                                 stdout = TRUE, stderr = TRUE))
  pg_secs <- as.numeric(difftime(Sys.time(), t_pg, units = "secs"))
  pg_status <- attr(pg, "status")
  if (is.null(pg_status) || pg_status == 0L) {
    fail("prepare guard: `Rscript scripts/prepare.R` did not fail with a snapshot present")
  }
  if (!any(grepl("immutable", pg, fixed = TRUE))) {
    fail("prepare guard: refusal message did not mention immutability: ",
         paste(utils::tail(pg, 3), collapse = " | "))
  }
  if (pg_secs > 25) {
    fail("prepare guard: refusal took ", round(pg_secs), "s -- it may be ",
         "reaching a scrape before the guard fires")
  }
  cat("prepare.R immutability guard OK\n")
}

## --- Summary (I/O matrix: "smoke offline") -------------------------------
cat(sprintf("smoke OK -- %d players in %s\n", n, snapshot_path))
for (p in names(pos_tab)) cat(sprintf("  %-3s %3d\n", p, pos_tab[[p]]))
cat(sprintf("snapshot size: %.1f KB\n", file.size(snapshot_path) / 1024))
quit(status = 0L, save = "no")
