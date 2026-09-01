## R/persistence.R -- atomic read/write of state/draft.rds (story 3).
##
## Responsibilities, all offline (no network, no UI layer):
##   * load_state()  -- read and schema-check state/draft.rds
##   * save_state()  -- atomic write with a .bak of the previous state
##   * .warroom_validate_state() -- the shared schema gate
##
## Contract: rds-contracts.md:37-64. Atomic write pattern (.tmp + .bak + rename):
## rds-contracts.md:39, AGENTS.md "Conventions". "Sufficient for local use"
## (intent): no fsync -- the guarantee is that a mid-write failure never leaves
## the main draft.rds corrupt; worst case a stray .tmp is left behind.

.warroom_state_keys <- c(
  "schema_version", "projection_created_at", "league",
  "team_order", "user_team", "seed", "picks"
)

.warroom_picks_columns <- c("overall", "player_id", "entered_at")

## Is `x` a single, finite, whole number >= 1?
.warroom_is_pos_whole_scalar <- function(x) {
  length(x) == 1L && is.numeric(x) && !is.na(x) && is.finite(x) &&
    x %% 1 == 0 && x >= 1
}

#' Validate a draft-state list against the rds-contracts.md schema.
#'
#' Rejects with an explanatory `stop()` naming the defect. Used by both
#' `save_state()` (before writing) and `load_state()` (after reading).
#'
#' @return invisible(TRUE) on success.
.warroom_validate_state <- function(x) {
  if (!is.list(x) || is.data.frame(x)) {
    stop("draft state must be a list; got ", class(x)[1L])
  }
  missing_keys <- setdiff(.warroom_state_keys, names(x))
  if (length(missing_keys)) {
    stop("draft state missing list key(s): ",
         paste(missing_keys, collapse = ", "))
  }
  if (!identical(x$schema_version, 1L)) {
    stop("draft state schema_version must be 1L; got ",
         paste(deparse(x$schema_version), collapse = ""))
  }
  if (!inherits(x$projection_created_at, "POSIXct")) {
    stop("draft state projection_created_at must be POSIXct; got ",
         class(x$projection_created_at)[1L])
  }

  league <- x$league
  league_keys <- c("teams", "rounds", "roster", "flex_positions")
  if (!is.list(league) || !all(league_keys %in% names(league))) {
    stop("draft state league must be a list with ",
         paste(league_keys, collapse = ", "))
  }
  if (!.warroom_is_pos_whole_scalar(league$teams)) {
    stop("draft state league$teams must be a single positive whole number; got ",
         paste(deparse(league$teams), collapse = ""))
  }
  if (!.warroom_is_pos_whole_scalar(league$rounds)) {
    stop("draft state league$rounds must be a single positive whole number; got ",
         paste(deparse(league$rounds), collapse = ""))
  }
  if (!is.numeric(league$roster) || is.null(names(league$roster)) ||
      any(!nzchar(names(league$roster)))) {
    stop("draft state league$roster must be a fully named numeric vector")
  }
  if (length(x$team_order) < 1L || !is.character(x$team_order)) {
    stop("draft state team_order must be a non-empty character vector")
  }
  if (anyDuplicated(x$team_order)) {
    stop("draft state team_order has duplicate name(s): ",
         paste(unique(x$team_order[duplicated(x$team_order)]), collapse = ", "))
  }
  if (!identical(length(x$team_order), as.integer(league$teams))) {
    stop("draft state team_order length (", length(x$team_order),
         ") does not match league$teams (", league$teams, ")")
  }
  if (length(x$user_team) != 1L || !x$user_team %in% x$team_order) {
    stop("draft state user_team must be one entry of team_order")
  }
  if (length(x$seed) != 1L || !is.numeric(x$seed) || is.na(x$seed)) {
    stop("draft state seed must be a single integer")
  }

  picks <- x$picks
  if (!is.data.frame(picks)) {
    stop("draft state picks must be a data frame; got ", class(picks)[1L])
  }
  if (!identical(names(picks), .warroom_picks_columns)) {
    stop("draft state picks must have exactly columns ",
         paste(.warroom_picks_columns, collapse = ", "), "; got ",
         paste(names(picks), collapse = ", "))
  }
  if (!is.integer(picks$overall)) {
    stop("draft state picks$overall must be integer; got ",
         class(picks$overall)[1L])
  }
  if (!is.character(picks$player_id)) {
    stop("draft state picks$player_id must be character; got ",
         class(picks$player_id)[1L])
  }
  if (!inherits(picks$entered_at, "POSIXct")) {
    stop("draft state picks$entered_at must be POSIXct; got ",
         class(picks$entered_at)[1L])
  }
  if (nrow(picks) > 0L) {
    if (!identical(picks$overall, seq_len(nrow(picks)))) {
      stop("draft state picks$overall must equal the row number (1..",
           nrow(picks), ")")
    }
    dup <- unique(picks$player_id[duplicated(picks$player_id)])
    if (length(dup)) {
      stop("draft state picks has duplicate player_id: ",
           paste(dup, collapse = ", "))
    }
    if (nrow(picks) > as.integer(league$teams) * as.integer(league$rounds)) {
      stop("draft state picks has ", nrow(picks),
           " rows, more than teams * rounds (",
           as.integer(league$teams) * as.integer(league$rounds), ")")
    }
  }

  invisible(TRUE)
}

#' Atomically write a draft-state list to `path`, keeping a `.bak` of the prior
#' state (CAP-4).
#'
#' Writes `<path>.tmp`, copies any existing `<path>` to `<path>.bak`, then
#' renames the temp file over `<path>`. The destination directory is created if
#' absent. A mid-write failure never corrupts the live `<path>`.
#'
#' @param state a draft-state list (validated before anything is written).
#' @param path destination path (config.R's `paths$draft_state`).
#' @return invisible(path).
save_state <- function(state, path) {
  .warroom_validate_state(state)

  dest_dir <- dirname(path)
  if (nzchar(dest_dir) && !dir.exists(dest_dir)) {
    dir.create(dest_dir, recursive = TRUE, showWarnings = FALSE)
    if (!dir.exists(dest_dir)) {
      stop("save_state(): could not create destination directory '",
           dest_dir, "'")
    }
  }

  tmp <- paste0(path, ".tmp")
  tryCatch(
    saveRDS(state, tmp),
    error = function(e) {
      unlink(tmp)
      stop("save_state(): failed to write temp file '", tmp, "' (",
           conditionMessage(e), ")")
    }
  )

  if (file.exists(path)) {
    if (!file.copy(path, paste0(path, ".bak"), overwrite = TRUE)) {
      unlink(tmp)
      stop("save_state(): could not back up existing state to '",
           paste0(path, ".bak"), "'")
    }
  }

  if (!file.rename(tmp, path)) {
    unlink(tmp)
    stop("save_state(): could not move the temp file into place at '", path, "'")
  }

  invisible(path)
}

#' Read and schema-check a draft-state list from disk (CAP-4).
#'
#' @param path path to `state/draft.rds`.
#' @return the validated state list.
load_state <- function(path) {
  if (!file.exists(path)) {
    stop("load_state(): no draft state file at '", path, "'")
  }
  x <- tryCatch(
    readRDS(path),
    error = function(e) {
      stop("load_state(): '", path, "' is not a readable RDS file (",
           conditionMessage(e), ")")
    }
  )
  .warroom_validate_state(x)
  x
}
