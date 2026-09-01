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

## --- Summary (I/O matrix: "smoke offline") -------------------------------
cat(sprintf("smoke OK -- %d players in %s\n", n, snapshot_path))
for (p in names(pos_tab)) cat(sprintf("  %-3s %3d\n", p, pos_tab[[p]]))
cat(sprintf("snapshot size: %.1f KB\n", file.size(snapshot_path) / 1024))
quit(status = 0L, save = "no")
