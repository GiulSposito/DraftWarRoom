## R/projections.R -- the data/projections.rds runtime contract.
##
## Responsibilities, all pure and offline (no network, no scrapers, no scrape
## package -- that lives only in scripts/prepare.R):
##   * build_synthetic_projections() -- the deterministic synthetic fixture (CAP-2)
##   * validate_projections() / load_projections() -- the shared schema gate that a
##     real scraped snapshot (story 2) must also pass.
##   * warroom_scoring() -- copy-and-override merge of league scoring onto a base
##     rule set (story 2). Pure list surgery; the base comes from the caller.
##   * normalize_projections() -- map a flattened multi-source projection table to
##     the `players` schema and assemble the snapshot list (story 2). The caller
##     (scripts/prepare.R) owns every scrape call; this function never sees one.
##
## Contract: rds-contracts.md. Fixture parameters + field mapping:
## preparation-pipeline.md.

.warroom_valid_pos <- c("QB", "RB", "WR", "TE", "K", "DST")

.warroom_projection_keys <- c(
  "schema_version", "created_at", "season", "method",
  "scoring", "vor_baseline", "players"
)

## Fixed snapshot timestamp for the synthetic fixture: kept constant (not
## Sys.time()) so repeated builds are byte-identical. Year matches config season.
.warroom_fixture_created_at <- as.POSIXct("2026-09-01 12:00:00", tz = "UTC")

## Scoring object stamped into the synthetic fixture. Story 2 moved the league
## scoring out of config.R (its keys did not match the real scrape API) into
## config/score_settings.yml, which only scripts/prepare.R may read. The
## synthetic snapshot does NOT model scoring: its `points` are closed-form
## synthetic values, so this object exists only to satisfy the `scoring` snapshot
## key. It is deliberately minimal -- do not grow it into a second copy of the
## real league rules (config/score_settings.yml is the only source for those).
.warroom_fixture_scoring <- list(
  note = "synthetic fixture: closed-form points, real scoring rules not modeled",
  rec  = list(rec = 1)
)

## Walk up from `start` looking for `name`; returns the path or NULL.
.warroom_find_file <- function(name, start = getwd()) {
  dir <- normalizePath(start, mustWork = FALSE)
  repeat {
    candidate <- file.path(dir, name)
    if (file.exists(candidate)) return(candidate)
    parent <- dirname(dir)
    if (identical(parent, dir)) return(NULL)
    dir <- parent
  }
}

## Load config.R into an isolated environment and check it carries the values the
## fixture stamps into the snapshot. config.R is the single source for the
## scoring rules and VOR baselines.
.warroom_load_config <- function() {
  path <- .warroom_find_file("config.R")
  if (is.null(path)) {
    stop("config.R not found from working directory '", getwd(),
         "'; run from the repository root.")
  }
  env <- new.env(parent = baseenv())
  sys.source(path, envir = env)

  ## `scoring` is no longer required in config.R (story 2): the real scoring is
  ## resolved in scripts/prepare.R from config/score_settings.yml. vor_baseline /
  ## season / method are still stamped into every snapshot, so still required.
  for (key in c("vor_baseline", "season", "method")) {
    if (is.null(env[[key]])) {
      stop("config.R is missing required value '", key, "'")
    }
  }
  vb <- env$vor_baseline
  if (!is.numeric(vb) || is.null(names(vb))) {
    stop("config.R vor_baseline must be a named numeric vector")
  }
  missing_pos <- setdiff(.warroom_valid_pos, names(vb))
  if (length(missing_pos)) {
    stop("config.R vor_baseline is missing position(s): ",
         paste(missing_pos, collapse = ", "))
  }
  env
}

#' Build the synthetic projection snapshot (CAP-2).
#'
#' Fully deterministic: `points`, `vor`, `adp`, and ranks are closed-form
#' functions of the within-position index, so repeated builds are identical and
#' no seeded or unseeded RNG runs. `seed` is accepted for signature stability
#' with the real preparation path but is unused.
#'
#' @return a list matching data/projections.rds in rds-contracts.md.
build_synthetic_projections <- function(seed = 1L) {
  stopifnot(length(seed) == 1L, is.numeric(seed))

  cfg          <- .warroom_load_config()
  scoring      <- if (is.null(cfg$scoring)) .warroom_fixture_scoring else cfg$scoring
  vor_baseline <- cfg$vor_baseline
  season       <- as.integer(cfg$season)
  method       <- cfg$method

  ## ~228 players: covers 168 picks and the board with room to spare.
  pos_counts <- c(QB = 24L, RB = 60L, WR = 72L, TE = 24L, K = 24L, DST = 24L)
  base_pts   <- c(QB = 380, RB = 340, WR = 330, TE = 240, K = 150, DST = 170)
  decay      <- c(QB = 7.0, RB = 4.2, WR = 3.0, TE = 4.6, K = 1.6, DST = 2.4)
  amp        <- c(QB = 6,   RB = 5,   WR = 5,   TE = 4,   K = 3,   DST = 4)

  pos_points <- function(pos, r) {
    p <- base_pts[[pos]] - decay[[pos]] * (r - 1) + amp[[pos]] * sin(r * 0.7)
    pmax(p, 15)
  }

  nfl_teams <- c("ARI","ATL","BAL","BUF","CAR","CHI","CIN","CLE","DAL","DEN",
                 "DET","GB","HOU","IND","JAX","KC","LV","LAC","LAR","MIA",
                 "MIN","NE","NO","NYG","NYJ","PHI","PIT","SEA","SF","TB","TEN","WAS")

  frames <- lapply(names(pos_counts), function(pos) {
    n <- pos_counts[[pos]]
    r <- seq_len(n)
    points <- round(pos_points(pos, r), 1)
    baseline_points <- as.numeric(round(pos_points(pos, vor_baseline[[pos]]), 1))
    sd   <- round(points * 0.10 + 3, 1)
    low  <- round(points - 1.5 * sd, 1)
    high <- round(points + 1.5 * sd, 1)
    data.frame(
      player_id   = sprintf("SYN-%s-%03d", pos, r),
      player      = sprintf("%s Synthetic %02d", pos, r),
      nfl_team    = nfl_teams[((r - 1L) %% length(nfl_teams)) + 1L],
      pos         = pos,
      points      = points,
      source_sd   = sd,
      source_low  = low,
      source_high = high,
      vor         = round(points - baseline_points, 1),
      low_vor     = round(low - baseline_points, 1),
      high_vor    = round(high - baseline_points, 1),
      ## pos_rank / tier are within-position ranks, assigned here BEFORE the
      ## global sort by points below -- downstream (story 5 tier-cliff) reads
      ## them as per-position.
      pos_rank    = as.integer(r),
      tier        = as.integer(pmin(ceiling(r / 6), 12)),
      stringsAsFactors = FALSE
    )
  })

  players <- do.call(rbind, frames)

  ## Overall rank by projected points, deterministic tie-break on player_id.
  ## method = "radix" is locale-independent, so ties keep a stable order.
  players <- players[order(-players$points, players$player_id, method = "radix"),
                     , drop = FALSE]
  players$overall_rank <- seq_len(nrow(players))

  ## ADP tracks overall rank with a smooth wobble, so the fixture exercises
  ## ADP-vs-value gaps without RNG.
  wobble        <- 6 * sin(players$overall_rank * 0.9) +
                   3 * cos(players$overall_rank * 0.35)
  players$adp    <- round(pmax(players$overall_rank + wobble, 1), 1)
  players$adp_sd <- round(4 + 0.05 * players$adp, 1)

  players <- players[, c(
    "player_id", "player", "nfl_team", "pos", "points",
    "source_sd", "source_low", "source_high",
    "vor", "low_vor", "high_vor",
    "overall_rank", "pos_rank", "tier", "adp", "adp_sd"
  )]
  rownames(players) <- NULL

  list(
    schema_version = 1L,
    created_at     = .warroom_fixture_created_at,
    season         = season,
    method         = method,
    scoring        = scoring,
    vor_baseline   = vor_baseline,
    players        = players
  )
}

#' Validate a projection snapshot against the rds-contracts.md schema.
#'
#' The synthetic fixture and a real scraped snapshot must both pass this.
#' Rejects with an explanatory stop() on any failure.
#'
#' @return invisible(TRUE) on success.
validate_projections <- function(x) {
  if (!is.list(x) || is.data.frame(x)) {
    stop("projection snapshot must be a list; got ", class(x)[1L])
  }
  missing_keys <- setdiff(.warroom_projection_keys, names(x))
  if (length(missing_keys)) {
    stop("projection snapshot missing list key(s): ",
         paste(missing_keys, collapse = ", "))
  }
  if (!identical(x$schema_version, 1L)) {
    stop("projection schema_version must be 1L; got ",
         paste(deparse(x$schema_version), collapse = ""))
  }
  if (!inherits(x$created_at, "POSIXct")) {
    stop("projection created_at must be POSIXct; got ", class(x$created_at)[1L])
  }

  players <- x$players
  if (!is.data.frame(players)) {
    stop("projection players must be a data frame; got ", class(players)[1L])
  }
  if (nrow(players) == 0L) {
    stop("projection players has no rows")
  }

  required_fields <- c("player_id", "player", "pos", "points")
  missing_fields <- setdiff(required_fields, names(players))
  if (length(missing_fields)) {
    stop("projection players missing required field(s): ",
         paste(missing_fields, collapse = ", "))
  }
  for (f in required_fields) {
    na_rows <- which(is.na(players[[f]]))
    if (length(na_rows)) {
      stop("projection players field '", f, "' has NA in row(s): ",
           paste(utils::head(na_rows, 10L), collapse = ", "))
    }
  }
  if (!is.numeric(players$points)) {
    stop("projection players field 'points' must be numeric; got ",
         class(players$points)[1L])
  }
  nonfinite <- which(!is.finite(players$points))
  if (length(nonfinite)) {
    stop("projection players field 'points' has non-finite value(s) ",
         "(Inf/-Inf/NaN) in row(s): ",
         paste(utils::head(nonfinite, 10L), collapse = ", "))
  }

  bad_pos <- setdiff(unique(as.character(players$pos)), .warroom_valid_pos)
  if (length(bad_pos)) {
    stop("projection players field 'pos' has invalid value(s): ",
         paste(bad_pos, collapse = ", "),
         " (allowed: ", paste(.warroom_valid_pos, collapse = ", "), ")")
  }

  dup <- duplicated(players$player_id)
  if (any(dup)) {
    stop("projection players has duplicate player_id: ",
         paste(unique(players$player_id[dup]), collapse = ", "))
  }

  invisible(TRUE)
}

#' Read and validate a projection snapshot from disk.
#'
#' @return the validated snapshot list.
load_projections <- function(path = file.path("data", "projections.rds")) {
  if (!file.exists(path)) {
    stop("projection snapshot not found at '", path,
         "'; build it first (make test rebuilds the synthetic fixture).")
  }
  x <- readRDS(path)
  validate_projections(x)
  x
}

## Is `x` a list carrying names on every element? (pts_bracket is an unnamed list.)
.warroom_is_named_list <- function(x) {
  is.list(x) && !is.null(names(x)) && all(nzchar(names(x)))
}

#' Copy-and-override merge of league scoring onto a base rule set (story 2).
#'
#' Starts from `base` (the complete rule set -- in scripts/prepare.R that is the
#' scrape package's default scoring object) and lays `overrides` on top:
#'   * named leaf in `overrides` replaces the matching leaf in `base`;
#'   * a leaf present only in `base` survives untouched (so field-goal-by-distance,
#'     extra points, sacks, defensive TDs, points-allowed brackets carry over
#'     automatically);
#'   * where `base[[key]]` is a named list, `overrides[[key]]` must also be a
#'     named list and the two merge recursively; a shape mismatch (scalar or
#'     partially-named override against a named-list base) is a `stop()`;
#'   * where `base[[key]]` is not a named list (`pts_bracket`, an unnamed list),
#'     `overrides[[key]]` replaces it wholesale, no recursion;
#'   * a named key in `overrides` with no counterpart in `base`, at any depth,
#'     is a `stop()` naming the full key path -- this catches silent typos;
#'   * a `NULL` override value is a `stop()` -- assigning `NULL` would delete a
#'     base scoring rule, a silent scoring loss (e.g. an empty `pass_int:` in YAML).
#'
#' No scrape package, no YAML parser, no I/O, no clock. `yes`/`no` parsed from
#' YAML arrive as logicals (e.g. `all_pos`) and are left as-is.
#'
#' @param base named list of scoring rules (the complete base).
#' @param overrides named list of league differences, same shape as `base`.
#' @param .path internal, for error messages.
#' @return `base` with `overrides` applied.
warroom_scoring <- function(base, overrides, .path = character()) {
  loc <- if (length(.path)) paste(.path, collapse = "$") else "<root>"
  if (!is.list(base)) {
    stop("warroom_scoring(): base at '", loc, "' is not a list")
  }
  if (is.null(overrides)) {
    return(base)
  }
  if (!.warroom_is_named_list(overrides)) {
    stop("warroom_scoring(): overrides at '", loc,
         "' must be a fully named list")
  }
  out <- base
  for (key in names(overrides)) {
    here <- c(.path, key)
    here_str <- paste(here, collapse = "$")
    if (!key %in% names(base)) {
      stop("warroom_scoring(): unknown scoring key '", here_str,
           "' -- not present in the base scoring rules")
    }
    ov <- overrides[[key]]
    if (is.null(ov)) {
      stop("warroom_scoring(): override key '", here_str,
           "' is NULL -- refusing to delete a base scoring rule")
    }
    if (.warroom_is_named_list(base[[key]])) {
      if (!.warroom_is_named_list(ov)) {
        stop("warroom_scoring(): override at '", here_str,
             "' must be a fully named list to match the base sub-section; got ",
             class(ov)[1L])
      }
      out[[key]] <- warroom_scoring(base[[key]], ov, here)
    } else {
      ## base leaf, or an unnamed list (pts_bracket): replace wholesale.
      out[[key]] <- ov
    }
  }
  out
}

## Snapshot field <- flattened projection-table column. player_id / player /
## pos / points are handled explicitly (required); rest are copied when present.
## Each mapped column is coerced to a fixed type so a real scraped table
## (integer / double / factor columns) yields the same `players` column types as
## the synthetic fixture.
.warroom_projection_field_map <- c(
  nfl_team     = "team",
  source_sd    = "sd_pts",
  source_low   = "floor",
  source_high  = "ceiling",
  vor          = "points_vor",
  low_vor      = "floor_vor",
  high_vor     = "ceiling_vor",
  overall_rank = "rank",
  pos_rank     = "pos_rank",
  tier         = "tier",
  adp          = "adp",
  adp_sd       = "adp_sd"
)

.warroom_projection_field_type <- c(
  nfl_team     = "character",
  source_sd    = "numeric",
  source_low   = "numeric",
  source_high  = "numeric",
  vor          = "numeric",
  low_vor      = "numeric",
  high_vor     = "numeric",
  overall_rank = "integer",
  pos_rank     = "integer",
  tier         = "integer",
  adp          = "numeric",
  adp_sd       = "numeric"
)

.warroom_players_column_order <- c(
  "player_id", "player", "nfl_team", "pos", "points",
  "source_sd", "source_low", "source_high",
  "vor", "low_vor", "high_vor",
  "overall_rank", "pos_rank", "tier", "adp", "adp_sd"
)

#' Normalize a flattened multi-source projection table into a snapshot list (story 2).
#'
#' Input is the data frame produced by the scrape adapter's projection-table +
#' player-info + ADP steps (see preparation-pipeline.md for the field mapping).
#' It never calls the scrape package, a YAML parser, or the network -- all of
#' that is scripts/prepare.R's job, and prepare.R hands the finished table in.
#' The only impurity is the `created_at` default, which reads the clock; callers
#' that need a fixed timestamp pass one explicitly (as the fixture builder does).
#'
#' Behaviour:
#'   * if an `avg_type` column is present, keep only `avg_type == cfg$method`,
#'     and `stop()` if that leaves no rows;
#'   * require source columns `id`, `pos`, `points` -- `stop()` naming any absent;
#'   * derive the player name from `first_name` + `last_name`, or a `player`
#'     column; `stop()` if neither is available;
#'   * map to the `players` schema (coercing each mapped column to a fixed type),
#'     `pos` upper-cased, `player <- trimws(paste(first_name, last_name))`;
#'   * order rows by `overall_rank` when that column is present;
#'   * reject duplicate `player_id`, naming the offending id(s);
#'   * `adp` / `adp_sd` are optional and travel as a pair -- if either is missing
#'     both are dropped with a `warning()` and the snapshot is still valid;
#'   * assemble the rds-contracts.md list and run it through
#'     `validate_projections()` before returning.
#'
#' @param proj_table data frame, the flattened projection table.
#' @param cfg list with `season`, `method`, `vor_baseline` (and optionally
#'   `scoring`). In scripts/prepare.R this is assembled from config.R values.
#' @param scoring the scoring-rules object to stamp into the snapshot; defaults
#'   to `cfg$scoring`.
#' @param created_at POSIXct snapshot timestamp; defaults to `Sys.time()`.
#' @return the validated snapshot list (rds-contracts.md).
normalize_projections <- function(proj_table, cfg, scoring = cfg$scoring,
                                  created_at = Sys.time()) {
  if (!is.data.frame(proj_table)) {
    stop("normalize_projections(): proj_table must be a data frame; got ",
         class(proj_table)[1L])
  }
  for (key in c("season", "method", "vor_baseline")) {
    if (is.null(cfg[[key]])) {
      stop("normalize_projections(): cfg is missing required value '", key, "'")
    }
  }
  if (!inherits(created_at, "POSIXct")) {
    stop("normalize_projections(): created_at must be POSIXct; got ",
         class(created_at)[1L])
  }
  if (is.null(scoring)) {
    stop("normalize_projections(): no scoring object -- pass `scoring` or set ",
         "`cfg$scoring`")
  }

  df <- proj_table

  ## projections_table() can stack several aggregation methods -- keep ours.
  if ("avg_type" %in% names(df)) {
    keep <- !is.na(df$avg_type) & df$avg_type == cfg$method
    df <- df[keep, , drop = FALSE]
    if (nrow(df) == 0L) {
      stop("normalize_projections(): no rows with avg_type == '", cfg$method,
           "'")
    }
  }

  required_src <- c("id", "pos", "points")
  missing_src <- setdiff(required_src, names(df))
  if (length(missing_src)) {
    stop("normalize_projections(): projection table missing required source ",
         "column(s): ", paste(missing_src, collapse = ", "))
  }
  if (nrow(df) == 0L) {
    stop("normalize_projections(): projection table has no rows")
  }

  if (all(c("first_name", "last_name") %in% names(df))) {
    player <- trimws(paste(df$first_name, df$last_name))
  } else if ("player" %in% names(df)) {
    player <- trimws(as.character(df$player))
  } else {
    stop("normalize_projections(): cannot derive 'player' -- need ",
         "first_name + last_name, or a 'player' column")
  }

  players <- data.frame(
    player_id = as.character(df$id),
    player    = player,
    pos       = toupper(as.character(df$pos)),
    points    = as.numeric(df$points),
    stringsAsFactors = FALSE
  )

  for (target in names(.warroom_projection_field_map)) {
    src <- .warroom_projection_field_map[[target]]
    if (src %in% names(df)) {
      val <- df[[src]]
      players[[target]] <- switch(
        .warroom_projection_field_type[[target]],
        character = as.character(val),
        numeric   = as.numeric(val),
        integer   = as.integer(val)
      )
    }
  }

  has_adp    <- "adp" %in% names(players)
  has_adp_sd <- "adp_sd" %in% names(players)
  if (!(has_adp && has_adp_sd)) {
    if (has_adp || has_adp_sd) {
      present <- if (has_adp) "adp" else "adp_sd"
      warning("normalize_projections(): only '", present, "' of the adp/adp_sd ",
              "pair is present; dropping both -- snapshot written without them")
    } else {
      warning("normalize_projections(): adp/adp_sd absent from the projection ",
              "table; snapshot written without them")
    }
    players$adp <- NULL
    players$adp_sd <- NULL
  }

  dup <- unique(players$player_id[duplicated(players$player_id)])
  if (length(dup)) {
    stop("normalize_projections(): duplicate player_id in the projection ",
         "table: ", paste(dup, collapse = ", "))
  }

  if ("overall_rank" %in% names(players)) {
    players <- players[order(players$overall_rank, players$player_id,
                             method = "radix"), , drop = FALSE]
  }

  players <- players[, intersect(.warroom_players_column_order, names(players)),
                     drop = FALSE]
  rownames(players) <- NULL

  snap <- list(
    schema_version = 1L,
    created_at     = created_at,
    season         = as.integer(cfg$season),
    method         = cfg$method,
    scoring        = scoring,
    vor_baseline   = cfg$vor_baseline,
    players        = players
  )
  validate_projections(snap)
  snap
}
