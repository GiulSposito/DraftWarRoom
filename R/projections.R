## R/projections.R -- the data/projections.rds runtime contract.
##
## Two responsibilities, both pure and offline (no network, no scrapers):
##   * build_synthetic_projections() -- the deterministic synthetic fixture (CAP-2)
##   * validate_projections() / load_projections() -- the shared schema gate that a
##     real scraped snapshot (story 2) must also pass.
##
## Contract: rds-contracts.md. Fixture parameters: preparation-pipeline.md.

.warroom_valid_pos <- c("QB", "RB", "WR", "TE", "K", "DST")

.warroom_projection_keys <- c(
  "schema_version", "created_at", "season", "method",
  "scoring", "vor_baseline", "players"
)

## Fixed snapshot timestamp for the synthetic fixture: kept constant (not
## Sys.time()) so repeated builds are byte-identical. Year matches config season.
.warroom_fixture_created_at <- as.POSIXct("2026-09-01 12:00:00", tz = "UTC")

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

  for (key in c("scoring", "vor_baseline", "season", "method")) {
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
  scoring      <- cfg$scoring
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
