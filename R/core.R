## R/core.R -- the pure functional core of draft state (story 3).
##
## Responsibilities, all pure and offline (no network, no UI layer, no saving):
##   * make_snake_schedule() -- the serpentine pick order for a snake draft (CAP-3)
##   * new_draft()           -- build the initial state/draft.rds list (CAP-4)
##   * record_pick() / undo_pick() -- validate and return a new state (CAP-6);
##     they never save -- that is the story 4 adapter's job.
##   * derive_draft_view()   -- current pick, team on the clock, rosters, available
##     players, all derived from the ordered picks alone (CAP-5)
##   * next_user_pick()      -- the user's next overall selection (CAP-5)
##
## Contracts: rds-contracts.md (state/draft.rds, picks), functional-core.md
## (catalog + invariants). Persist facts, derive views: nothing here writes a
## derived field back into the state.

## Empty `picks` with the exact contract column types. The typed zero-row frame
## keeps the incremental rbind in record_pick() from promoting column classes and
## survives a saveRDS/readRDS round trip unchanged (rds-contracts.md:56-63).
.warroom_empty_picks <- function() {
  data.frame(
    overall    = integer(0),
    player_id  = character(0),
    entered_at = as.POSIXct(character(0)),
    stringsAsFactors = FALSE
  )
}

## Require `x` to be a single, finite, whole number >= 1; return it as integer.
## Rejects NA, non-numeric, non-scalar, non-integral (e.g. 12.9), and < 1 with a
## message that names the offending argument.
.warroom_whole_scalar <- function(x, what) {
  if (length(x) != 1L || !is.numeric(x) || is.na(x) || !is.finite(x) ||
      x %% 1 != 0 || x < 1) {
    stop(what, " must be a single whole number >= 1; got ",
         paste(deparse(x), collapse = ""))
  }
  as.integer(x)
}

#' Generate the complete snake (serpentine) pick order (CAP-3).
#'
#' Rounds alternate direction: odd rounds run slot 1 -> teams, even rounds run
#' teams -> 1. For `teams` slots and `rounds` rounds the schedule has
#' `teams * rounds` turns.
#'
#' @param teams integer, number of draft slots (12 for the initial league).
#' @param rounds integer, number of rounds (15 for the initial league, i.e. the
#'   sum of every roster slot).
#' @return a data frame with columns `overall` (1..teams*rounds), `round`,
#'   `pick_in_round`, `slot`, all integer, ordered by `overall`.
make_snake_schedule <- function(teams, rounds) {
  teams  <- .warroom_whole_scalar(teams,  "make_snake_schedule(): teams")
  rounds <- .warroom_whole_scalar(rounds, "make_snake_schedule(): rounds")

  round         <- rep(seq_len(rounds), each = teams)
  pick_in_round <- rep(seq_len(teams), times = rounds)
  slot          <- ifelse(round %% 2L == 1L,
                          pick_in_round,
                          teams - pick_in_round + 1L)

  data.frame(
    overall       = seq_len(teams * rounds),
    round         = as.integer(round),
    pick_in_round = as.integer(pick_in_round),
    slot          = as.integer(slot),
    stringsAsFactors = FALSE
  )
}

#' Resolve the league format from `config/league.yml` (CAP-3, the live-path source).
#'
#' Reads the YAML league file, validates its shape, and derives `rounds` as the
#' sum of every roster slot (starters + bench). `rounds` is not an input -- it is
#' derived here (and re-derived when `new_draft()` gets an explicit league), then
#' frozen into `state$league` at draft creation -- so bench depth and round count
#' can never disagree. This and `scripts/prepare.R` are the only YAML reads in
#' the repository.
#'
#' @param path optional path to the league YAML; `NULL` walks up from the
#'   working directory looking for `config/league.yml`.
#' @return a list: `teams` (integer), `roster` (named integer vector, includes
#'   `BENCH`), `flex_positions` (character), `rounds` (integer, `sum(roster)`).
load_league <- function(path = NULL) {
  if (is.null(path)) {
    path <- .warroom_find_file(file.path("config", "league.yml"))
    if (is.null(path)) {
      stop("load_league(): config/league.yml not found from '", getwd(),
           "' or any parent; the live path needs it for the league format")
    }
  }
  if (!file.exists(path)) {
    stop("load_league(): no league file at '", path, "'")
  }
  raw <- tryCatch(
    yaml::read_yaml(path),
    error = function(e) {
      stop("load_league(): '", path, "' is not readable YAML (",
           conditionMessage(e), ")")
    }
  )
  ## The YAML file is the human-authored, fully-validated format: require every
  ## slot spelled out (use 0 for none) so a forgotten line is caught, not
  ## silently defaulted.
  .warroom_shape_league(raw, source = path, require_all_slots = TRUE)
}

## The complete roster-slot vocabulary. The resolved roster always carries
## exactly these keys (absent ones filled with 0 for an explicit `league` arg),
## so `sum(roster)` (the derived round count) can never silently omit a slot and
## `.warroom_slot_counts()`'s per-position defaults never quietly stand in.
.warroom_roster_slots  <- c("QB", "RB", "WR", "TE", "FLEX", "K", "DST", "BENCH")
.warroom_flex_eligible <- c("RB", "WR", "TE")

## Validate a raw league mapping (from YAML or passed explicitly to new_draft())
## and derive `rounds` = sum(roster). Any `rounds` key in the input is ignored --
## it is always derived, which is what makes the bench-vs-rounds discrepancy
## impossible to reintroduce. Unknown slots are always rejected; absent known
## slots are rejected only when `require_all_slots` (the YAML path), otherwise
## filled with 0. `source` names the origin for error messages.
.warroom_shape_league <- function(league, source = "league",
                                  require_all_slots = FALSE) {
  if (!is.list(league)) {
    stop("league (", source, ") must be a mapping with teams, roster, ",
         "flex_positions; got ", class(league)[1L])
  }
  required <- c("teams", "roster", "flex_positions")
  missing_keys <- setdiff(required, names(league))
  if (length(missing_keys)) {
    stop("league (", source, ") is missing key(s): ",
         paste(missing_keys, collapse = ", "))
  }

  teams <- .warroom_whole_scalar(league$teams, paste0("league (", source, ") teams"))

  ## roster: a named map of scalar numbers, covering exactly the known slots.
  rmap <- league$roster
  if (!is.list(rmap) && !is.numeric(rmap)) {
    stop("league (", source, ") roster must be a mapping of slot -> count; got ",
         class(rmap)[1L])
  }
  rmap <- as.list(rmap)
  if (is.null(names(rmap)) || any(!nzchar(names(rmap)))) {
    stop("league (", source, ") roster must be a fully named slot -> count map")
  }
  bad_shape <- names(rmap)[!vapply(rmap, function(v)
    is.numeric(v) && length(v) == 1L && !is.na(v), logical(1))]
  if (length(bad_shape)) {
    stop("league (", source, ") roster slot(s) not a single number: ",
         paste(bad_shape, collapse = ", "))
  }
  unknown <- setdiff(names(rmap), .warroom_roster_slots)
  if (length(unknown)) {
    stop("league (", source, ") roster has unknown slot(s): ",
         paste(unknown, collapse = ", "), " (allowed: ",
         paste(.warroom_roster_slots, collapse = ", "), ")")
  }
  absent <- setdiff(.warroom_roster_slots, names(rmap))
  if (require_all_slots && length(absent)) {
    stop("league (", source, ") roster is missing slot(s): ",
         paste(absent, collapse = ", "),
         " -- every slot must be listed, use 0 for none")
  }
  roster <- vapply(.warroom_roster_slots, function(s)
    if (s %in% names(rmap)) as.numeric(rmap[[s]]) else 0, numeric(1))
  bad_roster <- roster %% 1 != 0 | roster < 0
  if (any(bad_roster)) {
    stop("league (", source, ") roster has non-integral / negative value(s): ",
         paste(names(roster)[bad_roster], collapse = ", "))
  }
  storage.mode(roster) <- "integer"

  rounds <- sum(roster)
  if (rounds < 1L) {
    stop("league (", source, ") roster slots sum to ", rounds,
         "; need at least 1 round")
  }

  ## flex_positions: non-empty, drawn from the flex-eligible set, and each must
  ## be a roster slot the team actually carries.
  flex_pos <- as.character(league$flex_positions)
  if (roster[["FLEX"]] > 0L) {
    if (!length(flex_pos)) {
      stop("league (", source, ") has FLEX slots but flex_positions is empty")
    }
    bad_flex <- setdiff(flex_pos, .warroom_flex_eligible)
    if (length(bad_flex)) {
      stop("league (", source, ") flex_positions has ineligible entr(ies): ",
           paste(bad_flex, collapse = ", "), " (allowed: ",
           paste(.warroom_flex_eligible, collapse = ", "), ")")
    }
    no_slot <- flex_pos[roster[flex_pos] <= 0L]
    if (length(no_slot)) {
      stop("league (", source, ") flex_positions names position(s) with no ",
           "roster slot: ", paste(no_slot, collapse = ", "))
    }
  }

  list(
    teams          = teams,
    roster         = roster,
    flex_positions = flex_pos,
    rounds         = as.integer(rounds)
  )
}

#' Assert a draft is being resumed against the projection snapshot it was
#' started on (rds-contracts.md invariant 10).
#'
#' A draft state carries `projection_created_at`, the `created_at` of the
#' snapshot it is bound to. Resuming against a rebuilt snapshot would silently
#' corrupt every derived view, so both adapters call this before entering their
#' loop / rendering. `stop()`s with an explaining message on any mismatch,
#' including a missing or `NA` timestamp on either side.
#'
#' @param state a draft-state list (`load_state()` output).
#' @param snapshot the projection snapshot loaded for this session.
#' @return invisible(TRUE) when the binding holds.
.warroom_assert_snapshot_binding <- function(state, snapshot) {
  a <- suppressWarnings(as.numeric(state$projection_created_at))
  b <- suppressWarnings(as.numeric(snapshot$created_at))
  if (length(a) != 1L || length(b) != 1L || is.na(a) || is.na(b)) {
    stop("cannot verify the draft<->snapshot binding: ",
         "projection_created_at is ", format(state$projection_created_at),
         " and the snapshot created_at is ", format(snapshot$created_at))
  }
  if (!isTRUE(all.equal(a, b))) {
    stop("this draft is bound to a projection snapshot from ",
         format(state$projection_created_at, usetz = TRUE),
         " but the loaded snapshot is from ",
         format(snapshot$created_at, usetz = TRUE),
         " -- refusing to resume against the wrong snapshot")
  }
  invisible(TRUE)
}

## Resolve the league for new_draft(): an explicit list is shape-checked and its
## `rounds` re-derived from `roster`; `NULL` loads `config/league.yml`.
.warroom_resolve_league <- function(league) {
  if (is.null(league)) return(load_league())
  .warroom_shape_league(league, source = "explicit league arg")
}

#' Create the initial draft-state list (CAP-4).
#'
#' Persists facts only: the state carries the league, the slot order, the user's
#' team, a seed, and an empty ordered `picks` frame. Everything else (current
#' pick, rosters, availability) is derived later by `derive_draft_view()`.
#'
#' @param snapshot a projection snapshot (rds-contracts.md); only `created_at`
#'   and `players$player_id` are read.
#' @param team_order character vector of team names in draft-slot order; length
#'   must equal `league$teams` and names must be unique.
#' @param user_team one entry of `team_order`.
#' @param seed integer, for reproducible simulation / tie-breaks (story 7).
#' @param league optional league list (its `rounds`, if any, is re-derived from
#'   `roster`); `NULL` loads `config/league.yml` via `load_league()`.
#' @return the state list matching `state/draft.rds` in rds-contracts.md.
new_draft <- function(snapshot, team_order, user_team, seed = 1L, league = NULL) {
  if (!is.list(snapshot) || !inherits(snapshot$created_at, "POSIXct")) {
    stop("new_draft(): snapshot must be a list with a POSIXct `created_at`")
  }
  if (!is.data.frame(snapshot$players) ||
      is.null(snapshot$players[["player_id"]])) {
    stop("new_draft(): snapshot$players must be a data frame with a ",
         "player_id column")
  }

  league     <- .warroom_resolve_league(league)
  team_order <- as.character(team_order)

  if (length(team_order) != league$teams) {
    stop("new_draft(): team_order has ", length(team_order),
         " entries but league$teams is ", league$teams)
  }
  if (anyNA(team_order)) {
    stop("new_draft(): team_order contains NA entr(ies) in slot(s): ",
         paste(which(is.na(team_order)), collapse = ", "))
  }
  if (anyDuplicated(team_order)) {
    stop("new_draft(): team_order has duplicate name(s): ",
         paste(unique(team_order[duplicated(team_order)]), collapse = ", "))
  }
  if (length(user_team) != 1L || is.na(user_team) ||
      !user_team %in% team_order) {
    stop("new_draft(): user_team '",
         paste(deparse(user_team), collapse = ""),
         "' is not one of team_order")
  }
  if (length(seed) != 1L || !is.numeric(seed) || is.na(seed) ||
      seed %% 1 != 0) {
    stop("new_draft(): seed must be a single whole number")
  }

  list(
    schema_version        = 1L,
    projection_created_at  = snapshot$created_at,
    league                 = league,
    team_order             = team_order,
    user_team              = as.character(user_team),
    seed                   = as.integer(seed),
    picks                  = .warroom_empty_picks()
  )
}

#' Validate and append a player to `picks`, returning a new state (CAP-6).
#'
#' Does not save -- persistence is the story 4 adapter's job. Rejects an unknown
#' `player_id`, one already drafted, or a pick beyond `teams * rounds`.
#'
#' @param state a draft-state list.
#' @param player_id character, must exist in `snapshot$players$player_id`.
#' @param snapshot the projection snapshot bound to this draft.
#' @param entered_at POSIXct (or coercible); the persisted pick timestamp.
#' @return the state with one more row in `picks`.
record_pick <- function(state, player_id, snapshot, entered_at = Sys.time()) {
  player_id <- as.character(player_id)
  if (length(player_id) != 1L || is.na(player_id)) {
    stop("record_pick(): player_id must be a single non-NA string")
  }
  if (!is.data.frame(snapshot$players) ||
      is.null(snapshot$players[["player_id"]])) {
    stop("record_pick(): snapshot$players must be a data frame with a ",
         "player_id column")
  }
  if (length(entered_at) != 1L) {
    stop("record_pick(): entered_at must be length 1; got length ",
         length(entered_at))
  }
  entered_at <- tryCatch(
    as.POSIXct(entered_at),
    error = function(e) {
      stop("record_pick(): entered_at is not a valid timestamp (",
           conditionMessage(e), ")")
    }
  )
  if (is.na(entered_at)) {
    stop("record_pick(): entered_at coerced to NA -- pass a POSIXct or a ",
         "parseable date-time string")
  }

  if (!player_id %in% snapshot$players$player_id) {
    stop("record_pick(): player_id '", player_id,
         "' is not in the projection snapshot")
  }
  if (player_id %in% state$picks$player_id) {
    stop("record_pick(): player_id '", player_id,
         "' has already been drafted")
  }
  max_picks <- state$league$teams * state$league$rounds
  if (nrow(state$picks) >= max_picks) {
    stop("record_pick(): draft is full -- ", max_picks,
         " picks (teams * rounds) already recorded")
  }

  new_row <- data.frame(
    overall    = as.integer(nrow(state$picks) + 1L),
    player_id  = player_id,
    entered_at = entered_at,
    stringsAsFactors = FALSE
  )
  state$picks <- rbind(state$picks, new_row)
  rownames(state$picks) <- NULL
  state
}

#' Remove the most recent pick, returning a new state (CAP-6).
#'
#' @param state a draft-state list with at least one pick.
#' @return the state with the last `picks` row removed.
undo_pick <- function(state) {
  n <- nrow(state$picks)
  if (n == 0L) {
    stop("undo_pick(): there are no picks to undo")
  }
  state$picks <- state$picks[seq_len(n - 1L), , drop = FALSE]
  rownames(state$picks) <- NULL
  state
}

#' Derive every view over a draft from the ordered picks alone (CAP-5).
#'
#' Nothing here is written back into `state`. The snapshot is required because
#' `available` and `rosters` are projections over `snapshot$players`; the state
#' by itself only holds `player_id`.
#'
#' @param state a draft-state list.
#' @param snapshot the projection snapshot bound to this draft.
#' @return a list: `current_overall` (`nrow(picks)+1`, or `NA` when complete),
#'   `is_complete`, `round_on_clock`, `slot_on_clock`, `team_on_clock` (`NA` when
#'   complete), `drafted_ids`, `available` (snapshot players minus drafted),
#'   `rosters` (named by `team_order`, each the drafted players' snapshot rows).
derive_draft_view <- function(state, snapshot) {
  if (!is.data.frame(snapshot$players)) {
    stop("derive_draft_view(): snapshot$players must be a data frame; got ",
         class(snapshot$players)[1L])
  }
  schedule <- make_snake_schedule(state$league$teams, state$league$rounds)
  total    <- state$league$teams * state$league$rounds
  k        <- nrow(state$picks)
  is_complete     <- k >= total
  current_overall <- if (is_complete) NA_integer_ else as.integer(k + 1L)

  players     <- snapshot$players
  drafted_ids <- state$picks$player_id
  available   <- players[!(players$player_id %in% drafted_ids), , drop = FALSE]
  rownames(available) <- NULL

  ## pick i belongs to team_order[schedule$slot[i]] (schedule$overall == row).
  pick_slot <- if (k > 0L) schedule$slot[state$picks$overall] else integer(0)
  rosters <- stats::setNames(
    lapply(seq_along(state$team_order), function(slot_i) {
      ids <- state$picks$player_id[pick_slot == slot_i]
      roster_df <- players[match(ids, players$player_id), , drop = FALSE]
      rownames(roster_df) <- NULL
      roster_df
    }),
    state$team_order
  )

  if (is_complete) {
    round_on_clock <- NA_integer_
    slot_on_clock  <- NA_integer_
    team_on_clock  <- NA_character_
  } else {
    row <- schedule[schedule$overall == current_overall, ]
    round_on_clock <- row$round
    slot_on_clock  <- row$slot
    team_on_clock  <- state$team_order[row$slot]
  }

  list(
    current_overall = current_overall,
    is_complete     = is_complete,
    round_on_clock  = round_on_clock,
    slot_on_clock   = slot_on_clock,
    team_on_clock   = team_on_clock,
    drafted_ids     = drafted_ids,
    available       = available,
    rosters         = rosters
  )
}

#' The user's next overall selection (CAP-5).
#'
#' The smallest schedule `overall` whose slot is the user's and which is at or
#' after the current pick; `NA_integer_` once the user has no picks left.
#'
#' @param state a draft-state list.
#' @return integer scalar, or `NA_integer_`.
next_user_pick <- function(state) {
  schedule  <- make_snake_schedule(state$league$teams, state$league$rounds)
  user_slot <- match(state$user_team, state$team_order)
  if (is.na(user_slot)) {
    stop("next_user_pick(): user_team '", state$user_team,
         "' is not in team_order")
  }
  current_overall <- nrow(state$picks) + 1L
  candidates <- schedule$overall[schedule$slot == user_slot &
                                   schedule$overall >= current_overall]
  if (!length(candidates)) NA_integer_ else as.integer(min(candidates))
}

## --- Player-name resolution and board (story 4) ------------------------------
## Pure, offline helpers the terminal adapter (scripts/draft.R) and the story 8
## Shiny UI both call so no matching or board-ordering logic is duplicated in an
## adapter (functional-core.md, SPEC "Constraints").

.warroom_pos_levels <- c("QB", "RB", "WR", "TE", "K", "DST")

## Normalize a player name for matching: lowercase, transliterate accents to
## ASCII, collapse every run of non-alphanumeric characters to a single space,
## trim. Vectorized. `iconv(., "ASCII//TRANSLIT")` returns NA per element it
## cannot transliterate (and, on a few locales, for every element) -- fall back
## to the lowercased pre-iconv string there rather than losing the name entirely.
.warroom_normalize_name <- function(x) {
  lo   <- tolower(as.character(x))
  ascii <- iconv(lo, to = "ASCII//TRANSLIT")
  ascii[is.na(ascii)] <- lo[is.na(ascii)]
  ascii[is.na(ascii)] <- ""
  ascii <- gsub("[^a-z0-9]+", " ", ascii)
  trimws(gsub("[[:space:]]+", " ", ascii))
}

#' Resolve a typed query to available players (CAP-7).
#'
#' Matching is tried in order and the first non-empty tier wins: exact normalized
#' name, prefix, substring, then an `adist()` fuzzy fallback (all names at the
#' minimum edit distance, when that distance is within
#' `max(1, floor(nchar(query) / 3))`). Only rows of `available` can be returned.
#' If exact, prefix and substring all come up empty and the query is nonetheless
#' the exact normalized name of some player in `all_players` who is not available,
#' the result is `"none"` (they are drafted) instead of fuzzy near-neighbours.
#' Players whose normalized name is empty never match. The returned rows are
#' ordered by `points` descending, `player_id` ascending, for a stable numbered
#' disambiguation list.
#'
#' @param query character scalar, the raw user input.
#' @param available a data frame of available players (`derive_draft_view()$available`);
#'   must carry `player_id`, `player`, `points`.
#' @param all_players the full snapshot player table (`snapshot$players`); used
#'   only to recognise an exact name that is already drafted. Defaults to
#'   `available` (no drafted-name detection).
#' @return a list: `status` (`"unique"`, `"ambiguous"`, or `"none"`), `players`
#'   (the matched rows of `available`, possibly zero), `query` (the raw input).
resolve_player <- function(query, available, all_players = available) {
  if (length(query) != 1L || is.na(query)) {
    stop("resolve_player(): query must be a single non-NA string")
  }
  if (!is.data.frame(available) ||
      !all(c("player_id", "player", "points") %in% names(available))) {
    stop("resolve_player(): available must be a data frame with player_id, ",
         "player, points")
  }

  none <- list(status = "none",
               players = available[0L, , drop = FALSE],
               query = query)

  q <- .warroom_normalize_name(query)
  if (!nzchar(q) || nrow(available) == 0L) {
    return(none)
  }

  names_norm <- .warroom_normalize_name(available$player)
  ok <- which(nzchar(names_norm))          # never match a blank normalized name

  idx <- ok[names_norm[ok] == q]
  if (!length(idx)) idx <- ok[startsWith(names_norm[ok], q)]
  if (!length(idx)) idx <- ok[grepl(q, names_norm[ok], fixed = TRUE)]
  if (!length(idx)) {
    ## Exact/prefix/substring all empty. If the query is the exact name of a
    ## player who exists in the snapshot but is not available, they are drafted
    ## -- return "none" rather than fuzzy-guessing look-alikes.
    if (is.data.frame(all_players) && "player" %in% names(all_players) &&
        any(.warroom_normalize_name(all_players$player) == q)) {
      return(none)
    }
    d <- as.integer(utils::adist(q, names_norm[ok]))
    threshold <- max(1L, as.integer(floor(nchar(q) / 3)))
    if (length(d) && min(d) <= threshold) {
      idx <- ok[d == min(d)]
    }
  }
  if (!length(idx)) {
    return(none)
  }

  rows  <- available[idx, , drop = FALSE]
  rows  <- rows[order(-rows$points, rows$player_id, method = "radix"), ,
                drop = FALSE]
  rownames(rows) <- NULL

  list(
    status  = if (nrow(rows) == 1L) "unique" else "ambiguous",
    players = rows,
    query   = query
  )
}

#' The best available players, optionally filtered by position (CAP-7).
#'
#' Ordering is by `overall_rank` when present, else by `points` descending. Pure
#' presentation projection over `derive_draft_view()$available` — the same one the
#' Shiny available-player table uses.
#'
#' @param view a `derive_draft_view()` result.
#' @param pos optional position filter, one of QB/RB/WR/TE/K/DST (any case).
#' @param n optional row cap.
#' @return the matching rows of `view$available`, ordered, row names reset.
available_board <- function(view, pos = NULL, n = NULL) {
  av <- view$available
  if (!is.data.frame(av)) {
    stop("available_board(): view$available must be a data frame; got ",
         class(av)[1L])
  }
  if (is.null(av[["player_id"]]) ||
      !any(c("overall_rank", "points") %in% names(av))) {
    stop("available_board(): view$available needs player_id and one of ",
         "overall_rank / points")
  }

  if (!is.null(pos)) {
    if (length(pos) != 1L || is.na(pos)) {
      stop("available_board(): pos must be a single non-NA string")
    }
    if (is.null(av[["pos"]])) {
      stop("available_board(): view$available has no pos column to filter on")
    }
    pos <- toupper(as.character(pos))
    if (!pos %in% .warroom_pos_levels) {
      stop("available_board(): unknown position '", pos, "' -- expected one of ",
           paste(.warroom_pos_levels, collapse = ", "))
    }
    av <- av[!is.na(av$pos) & av$pos == pos, , drop = FALSE]
  }

  ## Deterministic order, player_id as the tie-break (rds-contracts.md inv. 9).
  ord <- if ("overall_rank" %in% names(av)) {
    order(av$overall_rank, av$player_id, method = "radix")
  } else {
    order(-av$points, av$player_id, method = "radix")
  }
  av <- av[ord, , drop = FALSE]

  if (!is.null(n)) {
    n <- .warroom_whole_scalar(n, "available_board(): n")
    av <- utils::head(av, n)
  }
  rownames(av) <- NULL
  av
}
