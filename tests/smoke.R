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

## --- Summary (I/O matrix: "smoke offline") -------------------------------
cat(sprintf("smoke OK -- %d players in %s\n", n, snapshot_path))
for (p in names(pos_tab)) cat(sprintf("  %-3s %3d\n", p, pos_tab[[p]]))
cat(sprintf("snapshot size: %.1f KB\n", file.size(snapshot_path) / 1024))
quit(status = 0L, save = "no")
