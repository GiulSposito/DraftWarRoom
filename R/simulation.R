## R/simulation.R -- mock draft simulator + weight calibration (story 7, CAP-10).
##
## Pure and offline, no `shiny`, no network. The ONLY file in R/ that runs any
## RNG, and it is confined to one seeded, saved/restored block
## (.warroom_with_seed(), called from .warroom_market_value()) -- everything
## else in a simulated draft is 100% deterministic given that one market draw.
## Reuses (read-only) the story 3/5/6 core: make_snake_schedule(), new_draft(),
## record_pick(), derive_draft_view() (R/core.R); recommend_players(),
## default_decision_weights(), lineup_value(), and the .warroom_ internals of
## R/recommendation.R (best_lineup, slot_counts, pos_count, unfilled_mandatory,
## value_of, bench_value, col, pick_sd) plus .warroom_pos_levels from R/core.R.
## No *value formula* is duplicated here. The one exception is the strand-guard
## *rule* in .warroom_eligible_sim_candidates() below, which intentionally
## mirrors (does not share via a common function) recommend_players()'s
## strand-guard/K-DST-grace eligibility loop, because R/recommendation.R is
## frozen this story and cannot be refactored to expose it.
##
## Contracts: functional-core.md (opponent_pick / simulate_draft catalog),
## operations.md (simulator + calibration), recommendation-algorithm.md (the
## components simulate_draft's "warroom" strategy reuses verbatim).
##
## Calibration is a small transparent grid search (expand.grid) over
## default_weight_grid() -- never a machine-learned or population-based
## optimizer (AGENTS.md, SPEC "Non-goals").

## --- constants ---------------------------------------------------------------

## Simple positional ceiling for a simulated team, ignored only when the
## strand-guard (.warroom_fills_mandatory()) requires that position to keep the
## roster feasible. Applies to both opponent_pick() and the adp/vor strategies.
.warroom_sim_pos_cap <- c(QB = 2L, RB = 8L, WR = 8L, TE = 2L, K = 1L, DST = 1L)

## adp_surplus / reach_count margin: a pick is a "reach" when the player's adp
## exceeds the pick's overall by more than this many slots.
.warroom_sim_reach_margin <- 10

## calibrate_weights() fitness formula constants (operations.md "Calibration").
.warroom_calib_bench_frac      <- 0.5
.warroom_calib_adp_frac        <- 0.1
.warroom_calib_invalid_penalty <- 1000
.warroom_calib_variance_penalty <- 1.0

## --- RNG isolation -------------------------------------------------------

#' Evaluate `expr` under `set.seed(seed)`, saving and restoring the caller's
#' global `.Random.seed` -- the only RNG in the whole R/ core, and it never
#' leaks state to whoever called simulate_draft()/`.warroom_market_value()`.
##
## `expr` is an unevaluated argument (lazy promise): it is only forced AFTER
## set.seed() runs below, so the caller's outer RNG stream is untouched except
## for the save/restore performed here.
.warroom_with_seed <- function(seed, expr) {
  has_seed <- exists(".Random.seed", envir = .GlobalEnv, inherits = FALSE)
  old_seed <- if (has_seed) get(".Random.seed", envir = .GlobalEnv) else NULL
  on.exit({
    if (has_seed) {
      assign(".Random.seed", old_seed, envir = .GlobalEnv)
    } else if (exists(".Random.seed", envir = .GlobalEnv, inherits = FALSE)) {
      rm(".Random.seed", envir = .GlobalEnv)
    }
  }, add = TRUE)
  set.seed(seed)
  expr
}

## The latent per-player "market value" for one simulated draft: adp plus
## normal noise at .warroom_pick_sd(adp, adp_sd) scale (the same dispersion
## p_next already uses -- one definition of "how the market errs on ADP" in
## the whole project). Drawn once per simulate_draft() call, under one seeded
## block. A player with no usable adp gets the worst (largest finite value + 1)
## market_value, so they are always drafted last among the market-driven
## strategies; ties among such players break on player_id ascending downstream
## (opponent_pick() / the adp-strategy sort), since they all share that value.
##
## @return a numeric vector named by player_id.
.warroom_market_value <- function(players, seed) {
  if (!is.data.frame(players) || is.null(players[["player_id"]]) ||
      is.null(players[["adp"]])) {
    stop(".warroom_market_value(): players must be a data frame with ",
         "player_id and adp columns")
  }
  if (length(seed) != 1L || !is.numeric(seed) || is.na(seed) ||
      seed %% 1 != 0) {
    stop(".warroom_market_value(): seed must be a single whole number")
  }
  pid    <- as.character(players$player_id)
  adp    <- as.numeric(players$adp)
  adp_sd <- as.numeric(.warroom_col(players, "adp_sd"))
  sd     <- .warroom_pick_sd(adp, adp_sd)
  ok     <- is.finite(adp) & is.finite(sd) & sd > 0

  mv <- rep(NA_real_, length(pid))
  if (any(ok)) {
    noise  <- .warroom_with_seed(seed, stats::rnorm(sum(ok), mean = 0, sd = sd[ok]))
    mv[ok] <- adp[ok] + noise
  }
  if (any(!ok)) {
    worst      <- if (any(ok)) max(mv[ok]) + 1 else 1
    mv[!ok]    <- worst
  }
  stats::setNames(mv, pid)
}

## --- shared eligibility filter (opponent_pick + adp/vor strategies) ----------

## The same strand-guard as recommend_players() -- never strand a mandatory
## slot, K/DST only in the final rounds unless mandatory -- plus a simple
## positional ceiling (.warroom_sim_pos_cap), ignored for a position only when
## the strand-guard already requires it. `round_on_clock` is the round the
## roster's own team is currently drafting (simulate_draft()/opponent_pick()
## pass `nrow(roster) + 1`, since each team picks exactly once per round).
.warroom_eligible_sim_candidates <- function(available, roster, league,
                                             round_on_clock) {
  flex_pos <- as.character(league$flex_positions)
  need     <- .warroom_unfilled_mandatory(roster, league)
  picks_remaining <- as.integer(league$rounds) -
    (if (is.null(roster) || !is.data.frame(roster)) 0L else nrow(roster))
  tight <- picks_remaining <= need$total
  round_on_clock <- suppressWarnings(as.integer(round_on_clock))
  kdst_ok_round  <- is.finite(round_on_clock) &&
    round_on_clock >= as.integer(league$rounds) - .warroom_kdst_grace_rounds

  pos_fill <- stats::setNames(
    vapply(names(.warroom_sim_pos_cap), function(p) .warroom_pos_count(roster, p),
           integer(1)),
    names(.warroom_sim_pos_cap)
  )

  keep <- logical(nrow(available))
  for (i in seq_len(nrow(available))) {
    pos   <- available$pos[i]
    fills <- .warroom_fills_mandatory(pos, need, flex_pos)
    if (!fills && tight) next                                    # strand guard
    if (!is.na(pos) && pos %in% c("K", "DST") && !kdst_ok_round && !tight) next
    if (!fills && !is.na(pos) && pos %in% names(.warroom_sim_pos_cap) &&
        pos_fill[[pos]] >= .warroom_sim_pos_cap[[pos]]) next      # pos cap
    keep[i] <- TRUE
  }
  available[keep, , drop = FALSE]
}

## --- opponent behaviour -------------------------------------------------

#' Simulated-team pick behaviour: the eligible candidate with the smallest
#' already-drawn `market_value` (CAP-10).
#'
#' Pure/deterministic given `market_value`. Eligibility is the shared
#' strand-guard + positional-cap filter (`.warroom_eligible_sim_candidates()`).
#'
#' @param available data frame of undrafted players (`derive_draft_view()$available`).
#' @param roster the picking team's current roster rows (may be `NULL`/0-row).
#' @param league the `state$league` list.
#' @param market_value named numeric vector (by `player_id`), already drawn by
#'   `.warroom_market_value()`.
#' @return a single `player_id`, always a row of `available`.
opponent_pick <- function(available, roster, league, market_value) {
  if (!is.data.frame(available) || is.null(available[["player_id"]])) {
    stop("opponent_pick(): available must be a data frame with a player_id column")
  }
  if (!is.numeric(market_value) || is.null(names(market_value))) {
    stop("opponent_pick(): market_value must be a named numeric vector (by player_id)")
  }

  round_on_clock <- (if (is.null(roster) || !is.data.frame(roster)) 0L else
    nrow(roster)) + 1L
  cand <- .warroom_eligible_sim_candidates(available, roster, league, round_on_clock)
  if (nrow(cand) == 0L) {
    stop("opponent_pick(): no eligible candidate remains")
  }

  mv <- as.numeric(market_value[cand$player_id])
  mv[is.na(mv)] <- Inf     ## defensive: a candidate absent from market_value picks last
  ord <- order(mv, cand$player_id, method = "radix")
  as.character(cand$player_id[ord[1L]])
}

## --- starters vs. bench (mirrors .warroom_best_lineup's selection) ----------

## The player_ids that make up the best current lineup for `roster` -- same
## slots, same value metric, same flex pool as .warroom_best_lineup(), but with
## an explicit player_id tie-break (value desc, player_id asc) so individual
## starters can be told apart from bench. Never modifies recommendation.R; this
## is purely a read of the same rules with identity attached.
.warroom_sim_starter_ids <- function(roster, league) {
  if (is.null(roster) || !is.data.frame(roster) || nrow(roster) == 0L) {
    return(character(0))
  }
  slots    <- .warroom_slot_counts(league)
  flex_pos <- as.character(league$flex_positions)
  val <- .warroom_value_of(roster)
  pos <- as.character(roster$pos)
  pid <- as.character(roster$player_id)

  pick_top <- function(p, k) {
    idx <- which(pos == p & !is.na(val))
    if (!length(idx) || k <= 0L) return(integer(0))
    ord <- idx[order(-val[idx], pid[idx], method = "radix")]
    utils::head(ord, k)
  }

  qb_idx <- pick_top("QB", slots$QB)
  rb_idx <- pick_top("RB", slots$RB)
  wr_idx <- pick_top("WR", slots$WR)
  te_idx <- pick_top("TE", slots$TE)
  used   <- c(qb_idx, rb_idx, wr_idx, te_idx)

  pool_idx <- which(pos %in% flex_pos & !is.na(val) & !(seq_along(pos) %in% used))
  flex_idx <- if (length(pool_idx) && slots$FLEX > 0L) {
    ord <- pool_idx[order(-val[pool_idx], pid[pool_idx], method = "radix")]
    utils::head(ord, slots$FLEX)
  } else {
    integer(0)
  }

  pid[c(qb_idx, rb_idx, wr_idx, te_idx, flex_idx)]
}

## A roster is valid when every mandatory slot (including FLEX) is filled and
## the team drafted exactly league$rounds players.
.warroom_roster_is_valid <- function(roster, league) {
  n <- if (is.null(roster) || !is.data.frame(roster)) 0L else nrow(roster)
  isTRUE(.warroom_unfilled_mandatory(roster, league)$total == 0L) &&
    identical(as.integer(n), as.integer(league$rounds))
}

## --- per-draft metrics (user's team only) ------------------------------------

## The operations.md metric set for one team's finished roster: projected
## starter points, starter VOR (lineup_value), discounted bench VOR, position
## counts, ADP surplus, reach count, roster validity, QB round, TE round.
.warroom_sim_metrics <- function(roster, state, snapshot, league, team) {
  starter_ids <- .warroom_sim_starter_ids(roster, league)
  has_roster  <- !is.null(roster) && is.data.frame(roster) && nrow(roster) > 0L
  is_starter  <- if (has_roster) roster$player_id %in% starter_ids else logical(0)

  starter_points <- if (has_roster) sum(roster$points[is_starter], na.rm = TRUE) else 0
  starter_vor    <- lineup_value(roster, league)

  bench_vor <- 0
  if (has_roster && any(!is_starter)) {
    bench <- roster[!is_starter, , drop = FALSE]
    bvor  <- as.numeric(.warroom_col(bench, "vor"))
    bench_vor <- sum(vapply(seq_len(nrow(bench)), function(i)
      .warroom_bench_value(bench$pos[i], bvor[i]), numeric(1)))
  }

  pos_counts <- stats::setNames(
    vapply(.warroom_pos_levels, function(p) .warroom_pos_count(roster, p), integer(1)),
    .warroom_pos_levels
  )

  ## This team's own picks, via the snake schedule slot mapping (same pattern
  ## as derive_draft_view()).
  schedule  <- make_snake_schedule(league$teams, league$rounds)
  team_slot <- match(team, state$team_order)
  pick_slot <- if (nrow(state$picks) > 0L) schedule$slot[state$picks$overall] else integer(0)
  own       <- state$picks[pick_slot == team_slot, , drop = FALSE]

  adp_surplus <- 0
  reach_count <- 0L
  qb_round    <- NA_integer_
  te_round    <- NA_integer_
  if (nrow(own) > 0L) {
    pl  <- snapshot$players[match(own$player_id, snapshot$players$player_id), , drop = FALSE]
    adp <- as.numeric(.warroom_col(pl, "adp"))
    ok  <- is.finite(adp)
    if (any(ok)) {
      adp_surplus <- sum(own$overall[ok] - adp[ok])
      reach_count <- sum((adp[ok] - own$overall[ok]) > .warroom_sim_reach_margin)
    }
    rounds_of <- schedule$round[own$overall]
    qb_rows <- which(pl$pos == "QB")
    te_rows <- which(pl$pos == "TE")
    if (length(qb_rows)) qb_round <- as.integer(min(rounds_of[qb_rows]))
    if (length(te_rows)) te_round <- as.integer(min(rounds_of[te_rows]))
  }

  list(
    starter_points = as.numeric(starter_points),
    starter_vor    = as.numeric(starter_vor),
    bench_vor      = as.numeric(bench_vor),
    pos_counts     = pos_counts,
    adp_surplus    = as.numeric(adp_surplus),
    reach_count    = as.integer(reach_count),
    roster_valid   = .warroom_roster_is_valid(roster, league),
    qb_round       = qb_round,
    te_round       = te_round
  )
}

## --- the full mock draft ------------------------------------------------

#' Run one complete seeded mock draft (CAP-10).
#'
#' The market draw (`.warroom_market_value()`) happens once, under one seeded
#' block; every one of the teams x rounds picks after that is deterministic. On the
#' `user_team`'s turn: `strategy = "warroom"` calls `recommend_players()` (the
#' real algorithm, no parallel heuristic) and takes its top pick;
#' `"adp"`/`"vor"` use the same eligibility filter as `opponent_pick()`,
#' ordered by `adp` ascending or `vor` descending. Every other team always uses
#' `opponent_pick()`. Picks are recorded via `record_pick()` -- no validation
#' is duplicated.
#'
#' @param snapshot the projection snapshot.
#' @param team_order character vector of team names in draft-slot order.
#' @param user_team one entry of `team_order`.
#' @param seed integer, drives the one market draw.
#' @param strategy one of "adp", "vor", "warroom" -- the user's own strategy.
#' @param weights decision weights, used only when `strategy == "warroom"`.
#' @param league optional league list (its `rounds`, if any, is re-derived from
#'   `roster`); `NULL` loads `config/league.yml` via `load_league()`.
#' @return `list(state, metrics, rosters_valid)`. `metrics` covers only
#'   `user_team`: `starter_points`, `starter_vor`, `bench_vor`, `pos_counts`
#'   (named QB..DST), `adp_surplus`, `reach_count`, `roster_valid`, `qb_round`,
#'   `te_round`. `rosters_valid` is a logical vector named by `team_order`.
simulate_draft <- function(snapshot, team_order, user_team, seed,
                           strategy = c("adp", "vor", "warroom"),
                           weights = default_decision_weights(),
                           league = NULL) {
  strategy <- match.arg(strategy)

  state  <- new_draft(snapshot, team_order, user_team, seed = seed, league = league)
  league <- state$league   ## resolved + shape-checked by new_draft()

  market_value <- .warroom_market_value(snapshot$players, seed)
  total <- as.integer(league$teams) * as.integer(league$rounds)

  for (i in seq_len(total)) {
    view <- derive_draft_view(state, snapshot)
    if (isTRUE(view$is_complete)) break

    team    <- view$team_on_clock
    roster  <- view$rosters[[team]]
    is_user <- identical(team, user_team)

    if (is_user && strategy == "warroom") {
      recs <- recommend_players(state, snapshot, weights, n = 1L)
      if (nrow(recs) == 0L) {
        stop("simulate_draft(): recommend_players() returned no candidate ",
             "for the user's pick at overall ", view$current_overall)
      }
      pid <- as.character(recs$player_id[1L])
    } else if (is_user && strategy %in% c("adp", "vor")) {
      cand <- .warroom_eligible_sim_candidates(view$available, roster, league,
                                               view$round_on_clock)
      if (nrow(cand) == 0L) {
        stop("simulate_draft(): no eligible candidate for the user's '",
             strategy, "' pick at overall ", view$current_overall)
      }
      if (strategy == "adp") {
        key <- as.numeric(.warroom_col(cand, "adp"))
        key[is.na(key)] <- Inf
        ord <- order(key, cand$player_id, method = "radix")
      } else {
        key <- as.numeric(.warroom_col(cand, "vor"))
        key[is.na(key)] <- -Inf
        ord <- order(-key, cand$player_id, method = "radix")
      }
      pid <- as.character(cand$player_id[ord[1L]])
    } else {
      pid <- opponent_pick(view$available, roster, league, market_value)
    }

    entered_at <- snapshot$created_at + view$current_overall
    state <- record_pick(state, pid, snapshot, entered_at = entered_at)
  }

  final_view <- derive_draft_view(state, snapshot)
  rosters_valid <- stats::setNames(
    vapply(team_order, function(tm)
      .warroom_roster_is_valid(final_view$rosters[[tm]], league), logical(1)),
    team_order
  )
  metrics <- .warroom_sim_metrics(final_view$rosters[[user_team]], state, snapshot,
                                  league, user_team)

  list(state = state, metrics = metrics, rosters_valid = rosters_valid)
}

## --- strategy comparison --------------------------------------------------

#' Compare strategies for `user_team` on one shared market draw (CAP-10).
#'
#' Runs `simulate_draft()` once per strategy, all with the same `seed` (so all
#' three see the same market_value draw -- a fair comparison), and flattens
#' each run's metrics into one row.
#'
#' @return a data frame, one row per strategy: `strategy` plus the flattened
#'   metrics (`n_QB`..`n_DST` instead of the `pos_counts` vector) and
#'   `all_rosters_valid` (all 12 teams).
compare_strategies <- function(snapshot, team_order, user_team, seed,
                               strategies = c("adp", "vor", "warroom"),
                               weights = default_decision_weights()) {
  rows <- lapply(as.character(strategies), function(strat) {
    res <- simulate_draft(snapshot, team_order, user_team, seed,
                          strategy = strat, weights = weights)
    m <- res$metrics
    data.frame(
      strategy          = strat,
      starter_points    = m$starter_points,
      starter_vor       = m$starter_vor,
      bench_vor         = m$bench_vor,
      n_QB              = as.integer(m$pos_counts[["QB"]]),
      n_RB              = as.integer(m$pos_counts[["RB"]]),
      n_WR              = as.integer(m$pos_counts[["WR"]]),
      n_TE              = as.integer(m$pos_counts[["TE"]]),
      n_K               = as.integer(m$pos_counts[["K"]]),
      n_DST             = as.integer(m$pos_counts[["DST"]]),
      adp_surplus       = m$adp_surplus,
      reach_count       = m$reach_count,
      roster_valid      = m$roster_valid,
      qb_round          = m$qb_round,
      te_round          = m$te_round,
      all_rosters_valid = all(res$rosters_valid),
      stringsAsFactors  = FALSE
    )
  })
  out <- do.call(rbind, rows)
  rownames(out) <- NULL
  out
}

## --- calibration grid ---------------------------------------------------

#' The default calibration grid over the four decision weights (operations.md
#' "Calibration") -- `expand.grid` over three hypotheses each for
#' `roster_value`, `wait_cost`, `tier_cliff`; `adp_value` completes the sum to
#' 1; rows where that would go negative are dropped. No optimizer, no search
#' heuristic -- a plain transparent grid.
#'
#' @return a data frame with columns `roster_value`, `wait_cost`, `tier_cliff`,
#'   `adp_value`, each row summing to 1.
default_weight_grid <- function() {
  grid <- expand.grid(
    roster_value = c(0.40, 0.50, 0.60),
    wait_cost    = c(0.20, 0.30, 0.40),
    tier_cliff   = c(0.10, 0.15, 0.20),
    KEEP.OUT.ATTRS = FALSE,
    stringsAsFactors = FALSE
  )
  grid$adp_value <- round(1 - (grid$roster_value + grid$wait_cost + grid$tier_cliff), 10)
  grid <- grid[grid$adp_value >= 0, , drop = FALSE]
  rownames(grid) <- NULL
  grid
}

#' Calibrate decision weights over a small transparent grid (CAP-10).
#'
#' For each grid row, runs `simulate_draft(strategy = "warroom")` once per
#' `slot` x `seed` combination (`user_team = team_order[slot]`), and computes
#' a fitness per run:
#'   `starter_vor + .warroom_calib_bench_frac * bench_vor +
#'    .warroom_calib_adp_frac * adp_surplus -
#'    .warroom_calib_invalid_penalty * !roster_valid`
#' Aggregated per row: `mean_fitness`, `sd_fitness` (0 for a single run),
#' `risk_score = mean_fitness - .warroom_calib_variance_penalty * sd_fitness`,
#' `all_valid`. Never a machine-learned or population-based optimizer -- a
#' plain double loop (grid x seeds x slots) over `expand.grid()`.
#'
#' @return `grid` with the aggregate columns attached, ordered by
#'   `risk_score` descending.
calibrate_weights <- function(snapshot, team_order, seeds = c(1L, 2L, 3L),
                              slots = c(1L, 6L, 12L), grid = default_weight_grid()) {
  if (length(slots) < 1L || !is.numeric(slots) || anyNA(slots) ||
      any(slots %% 1 != 0) || any(slots < 1) || any(slots > length(team_order))) {
    stop("calibrate_weights(): slots must be whole numbers between 1 and ",
         length(team_order), " (length(team_order)); got ",
         paste(deparse(slots), collapse = ""))
  }
  n <- nrow(grid)
  mean_fitness <- numeric(n)
  sd_fitness   <- numeric(n)
  risk_score   <- numeric(n)
  all_valid    <- logical(n)

  for (g in seq_len(n)) {
    weights <- c(
      roster_value = grid$roster_value[g],
      wait_cost    = grid$wait_cost[g],
      tier_cliff   = grid$tier_cliff[g],
      adp_value    = grid$adp_value[g]
    )
    fits  <- numeric(0)
    valid <- TRUE
    for (slot in slots) {
      user_team <- team_order[[slot]]
      for (sd in seeds) {
        res <- simulate_draft(snapshot, team_order, user_team, seed = sd,
                              strategy = "warroom", weights = weights)
        m <- res$metrics
        fit <- m$starter_vor +
          .warroom_calib_bench_frac * m$bench_vor +
          .warroom_calib_adp_frac   * m$adp_surplus -
          .warroom_calib_invalid_penalty * (!isTRUE(m$roster_valid))
        fits  <- c(fits, fit)
        valid <- valid && isTRUE(m$roster_valid)
      }
    }
    mean_fitness[g] <- mean(fits)
    sd_fitness[g]   <- if (length(fits) > 1L) stats::sd(fits) else 0
    risk_score[g]   <- mean_fitness[g] - .warroom_calib_variance_penalty * sd_fitness[g]
    all_valid[g]    <- valid
  }

  out <- cbind(grid, data.frame(
    mean_fitness = mean_fitness, sd_fitness = sd_fitness,
    risk_score = risk_score, all_valid = all_valid,
    stringsAsFactors = FALSE
  ))
  out <- out[order(-out$risk_score, method = "radix"), , drop = FALSE]
  rownames(out) <- NULL
  out
}
