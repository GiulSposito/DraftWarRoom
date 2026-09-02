## R/recommendation.R -- roster-aware recommendation foundation (story 5, CAP-8).
##
## Pure, offline: no shiny, no network, no file I/O, no RNG. Implements
## components 1 and 4 of recommendation-algorithm.md:
##   * lineup_value()             -- value of the best possible lineup for a roster
##   * default_decision_weights() -- the four calibration-hypothesis weights
##   * recommend_players()        -- rank available players, label + explain
##
## p_next, expected_best_next, wait_cost and the full four-term configurable score
## are story 6: the result data frame carries `p_next` and `wait_cost` columns but
## both are NA_real_ here, and decision_score combines only the three components
## available now (roster_value, tier_cliff, adp_value).
##
## Contracts: functional-core.md (catalog + invariants 7-9), rds-contracts.md
## (players table), recommendation-algorithm.md (components, guardrails, labels,
## output columns). Determinism: same state + snapshot + weights -> same order,
## tie-break on player_id ascending (method = "radix").

## Positions that fill the starting lineup; K and DST are handled only through the
## guardrails / VOR / roster-need path, never in lineup_value (recommendation-
## algorithm.md, component 1).
.warroom_lineup_pos <- c("QB", "RB", "WR", "TE")

## Bench option value: max(0, vor) * factor. RB/WR retain more bench value than
## QB2/TE2 because they cover more starting and FLEX situations; K/DST cover none.
.warroom_bench_factor <- c(QB = 0.5, RB = 1.0, WR = 1.0, TE = 0.6, K = 0.2, DST = 0.2)

## Guardrail penalty magnitudes, on the 0-100 decision_score scale.
.warroom_qb2_penalty <- 40
.warroom_te2_penalty <- 25

## K/DST are ineligible while round_on_clock < rounds - this, unless already
## mandatory under a viability squeeze.
.warroom_kdst_grace_rounds <- 2L

## Label thresholds (constants, not tuned this story).
.warroom_best_value_adp   <- 8      # adp_value >= this  -> BEST VALUE
.warroom_take_now_score   <- 60     # decision_score >= this -> TAKE NOW eligible
.warroom_roster_need_slack <- 2L    # picks slack <= this -> critical mandatory need
.warroom_roster_need_depth <- 3L    # <= this available same-pos in tier-or-better

## Result column order, exactly recommendation-algorithm.md "Recommendation output
## columns".
.warroom_rec_columns <- c(
  "player_id", "player", "pos", "points", "vor", "tier", "adp",
  "p_next", "marginal_value", "wait_cost", "tier_cliff", "adp_value",
  "decision_score", "label", "reason"
)

#' The four decision weights (calibration hypotheses, not fixed truth).
#'
#' recommendation-algorithm.md "Combined score". `wait_cost` is carried for the
#' story-6 contract but ignored by `recommend_players()` this story.
#'
#' @return a named numeric vector summing to 1.
default_decision_weights <- function() {
  c(roster_value = 0.50, wait_cost = 0.30, tier_cliff = 0.15, adp_value = 0.05)
}

## Slot counts from league$roster, with the initial-league defaults as a fallback.
.warroom_slot_counts <- function(league) {
  r <- league$roster
  if (!is.numeric(r) || is.null(names(r))) {
    stop("recommend_players(): league$roster must be a named numeric vector")
  }
  g <- function(k, d) if (k %in% names(r)) as.integer(r[[k]]) else d
  list(QB = g("QB", 1L), RB = g("RB", 2L), WR = g("WR", 2L), TE = g("TE", 1L),
       FLEX = g("FLEX", 1L), K = g("K", 1L), DST = g("DST", 1L))
}

## Count rostered players at a position (0 for an empty / NULL roster).
.warroom_pos_count <- function(roster, pos) {
  if (is.null(roster) || !is.data.frame(roster) || nrow(roster) == 0L) return(0L)
  sum(!is.na(roster$pos) & roster$pos == pos)
}

## Sum of the best lineup's value from parallel pos / value vectors: best QB,
## best `RB` RBs, best `WR` WRs, best TE, then the best leftover flex_positions
## entry as FLEX. K/DST never contribute; an empty slot contributes 0. Uses only
## the value magnitudes, so the sum does not depend on any player_id tie-break.
.warroom_best_lineup <- function(pos, value, league) {
  slots    <- .warroom_slot_counts(league)
  flex_pos <- as.character(league$flex_positions)
  ok  <- !is.na(pos) & !is.na(value)
  pos <- pos[ok]; value <- value[ok]

  desc <- function(p) sort(value[pos == p], decreasing = TRUE)
  take <- function(v, k) if (k <= 0L || length(v) == 0L) numeric(0) else utils::head(v, k)

  qb <- take(desc("QB"), slots$QB)
  rb_all <- desc("RB"); wr_all <- desc("WR")
  rb <- take(rb_all, slots$RB)
  wr <- take(wr_all, slots$WR)
  te <- take(desc("TE"), slots$TE)

  pool <- numeric(0)
  for (p in flex_pos) {
    ap <- desc(p)
    start_k <- if (p == "RB") slots$RB else if (p == "WR") slots$WR else 0L
    if (length(ap) > start_k) pool <- c(pool, ap[(start_k + 1L):length(ap)])
  }
  flex <- take(sort(pool, decreasing = TRUE), slots$FLEX)

  sum(qb, rb, wr, te, flex)
}

## The value magnitude of a player table: `vor` when present, else `points`. VOR
## is the "value" currency (docs/fantasy-warroom-bmad-intent.md); raw points make
## QBs outrank scarcer RB/WR on an empty roster.
.warroom_value_of <- function(df) {
  if ("vor" %in% names(df))    return(as.numeric(df$vor))
  if ("points" %in% names(df)) return(as.numeric(df$points))
  stop("recommend_players(): player table needs a `vor` or `points` column")
}

#' Value of the best possible lineup for a roster (recommendation-algorithm.md,
#' component 1).
#'
#' Best QB, best `RB` RBs, best `WR` WRs, best TE, then the best leftover
#' `flex_positions` player as FLEX. Slots are valued by `vor` (`points` as a
#' fallback when the snapshot carries no `vor`). A negative-VOR forced starter
#' still counts; K and DST never contribute; an empty slot contributes 0.
#'
#' @param roster a data frame of player rows with `pos` and `vor`/`points` (may
#'   be 0 rows or `NULL`).
#' @param league the `state$league` list (`roster` counts, `flex_positions`).
#' @return a single numeric.
lineup_value <- function(roster, league) {
  if (is.null(roster) || !is.data.frame(roster) || nrow(roster) == 0L) return(0)
  if (is.null(roster$pos)) stop("lineup_value(): roster needs a `pos` column")
  .warroom_best_lineup(as.character(roster$pos), .warroom_value_of(roster), league)
}

## Unfilled mandatory slots for a roster: per-position need plus a FLEX need not
## already covered by RB/WR surplus. `total` drives the viability squeeze.
.warroom_unfilled_mandatory <- function(roster, league) {
  slots <- .warroom_slot_counts(league)
  fill  <- list(
    QB  = .warroom_pos_count(roster, "QB"), RB = .warroom_pos_count(roster, "RB"),
    WR  = .warroom_pos_count(roster, "WR"), TE = .warroom_pos_count(roster, "TE"),
    K   = .warroom_pos_count(roster, "K"),  DST = .warroom_pos_count(roster, "DST")
  )
  by_pos <- c(
    QB  = max(0L, slots$QB  - fill$QB),  RB  = max(0L, slots$RB  - fill$RB),
    WR  = max(0L, slots$WR  - fill$WR),  TE  = max(0L, slots$TE  - fill$TE),
    K   = max(0L, slots$K   - fill$K),   DST = max(0L, slots$DST - fill$DST)
  )
  rb_surplus <- max(0L, fill$RB - slots$RB)
  wr_surplus <- max(0L, fill$WR - slots$WR)
  flex <- max(0L, slots$FLEX - (rb_surplus + wr_surplus))
  list(by_pos = by_pos, flex = flex, total = sum(by_pos) + flex)
}

## Does a candidate at `pos` fill a currently-unfilled mandatory slot?
.warroom_fills_mandatory <- function(pos, need, flex_pos) {
  if (is.na(pos)) return(FALSE)
  if (pos %in% names(need$by_pos) && need$by_pos[[pos]] > 0L) return(TRUE)
  if (pos %in% flex_pos && need$flex > 0L) return(TRUE)
  FALSE
}

## Column `nm` of `df`, or an all-NA numeric of the right length when absent.
.warroom_col <- function(df, nm) {
  if (nm %in% names(df)) df[[nm]] else rep(NA_real_, nrow(df))
}

## Normalize to [0, 1] within the shortlist: (x - min) / (max - min); 0 when the
## range is degenerate or the value is not finite.
.warroom_norm01 <- function(x) {
  x  <- ifelse(is.finite(x), x, NA_real_)
  lo <- suppressWarnings(min(x, na.rm = TRUE))
  hi <- suppressWarnings(max(x, na.rm = TRUE))
  if (!is.finite(lo) || !is.finite(hi) || hi == lo) return(rep(0, length(x)))
  out <- (x - lo) / (hi - lo)
  out[is.na(out)] <- 0
  out
}

## points(candidate) - points(best available at the same position in the next
## tier); fall back to the worst available same-position player, then 0.
.warroom_tier_cliff <- function(cand, available) {
  pos <- cand$pos; tier <- suppressWarnings(as.numeric(cand$tier))
  same <- available[!is.na(available$pos) & available$pos == pos &
                      available$player_id != cand$player_id, , drop = FALSE]
  if (nrow(same) == 0L) return(0)
  if (is.finite(tier) && "tier" %in% names(same)) {
    nxt <- same$points[is.finite(same$tier) & same$tier > tier]
    nxt <- nxt[is.finite(nxt)]
    if (length(nxt)) return(as.numeric(cand$points) - max(nxt))
  }
  worst <- same$points[is.finite(same$points)]
  if (length(worst)) return(as.numeric(cand$points) - min(worst))
  0
}

## Human-readable slot label for the reason string.
.warroom_slot_label <- function(pos, need, flex_pos) {
  if (pos %in% names(need$by_pos) && need$by_pos[[pos]] > 0L) return(paste0(pos, " titular"))
  if (pos %in% flex_pos && need$flex > 0L) return("FLEX")
  paste0(pos, " titular")
}

## Assemble the deterministic explanation from the triggered fragments (max 4).
.warroom_rec_reason <- function(marg, bench_val, vor, cliff_cond, tier, pos,
                                tier_left, fills_need, slot_label,
                                adp_value, qb2, te2) {
  frag <- character(0)
  if (is.finite(marg) && marg > 0) {
    frag <- c(frag, sprintf("ganho de %+.1f de VOR no lineup", marg))
    if (is.finite(vor)) frag <- c(frag, sprintf("VOR %+.1f", vor))
  } else if (is.finite(bench_val) && bench_val > 0 && is.finite(vor)) {
    frag <- c(frag, sprintf("valor de banco (VOR %+.1f)", vor))
  }
  if (isTRUE(cliff_cond)) {
    frag <- c(frag, if (is.finite(tier_left) && tier_left <= 1L)
      sprintf("ultima opcao relevante do tier %s em %s", tier, pos)
    else sprintf("restam %d no tier %s em %s", tier_left, tier, pos))
  }
  if (isTRUE(fills_need)) frag <- c(frag, paste0("preenche ", slot_label))
  if (is.finite(adp_value) && adp_value >= .warroom_best_value_adp) {
    frag <- c(frag, sprintf("caiu %.0f picks abaixo do ADP", adp_value))
  }
  if (isTRUE(qb2)) frag <- c(frag, "penalizado como QB2 com titulares em aberto")
  if (isTRUE(te2)) frag <- c(frag, "penalizado como TE2 com titulares em aberto")
  if (!length(frag)) return("melhor disponivel pelo valor combinado")
  paste(utils::head(frag, 4L), collapse = "; ")
}

## Empty result with the contract columns and types.
.warroom_empty_recs <- function() {
  data.frame(
    player_id = character(0), player = character(0), pos = character(0),
    points = numeric(0), vor = numeric(0), tier = numeric(0), adp = numeric(0),
    p_next = numeric(0), marginal_value = numeric(0), wait_cost = numeric(0),
    tier_cliff = numeric(0), adp_value = numeric(0), decision_score = numeric(0),
    label = character(0), reason = character(0), stringsAsFactors = FALSE
  )
}

#' Rank available players for the user's next pick (CAP-8).
#'
#' Deterministic: the same `state`, `projection_snapshot` and `weights` produce
#' the same ordered data frame (ties broken by `player_id` ascending). Never
#' returns a drafted player or one whose pick would strand a mandatory roster
#' slot (functional-core.md invariants 7-9).
#'
#' @param state a draft-state list (`R/core.R`).
#' @param projection_snapshot the bound projection snapshot (`R/projections.R`).
#' @param weights named numeric; needs `roster_value`, `tier_cliff`, `adp_value`
#'   (`default_decision_weights()`). `wait_cost` is accepted and ignored.
#' @param n integer, max rows to return.
#' @return a data frame with columns
#'   `player_id player pos points vor tier adp p_next marginal_value wait_cost
#'   tier_cliff adp_value decision_score label reason`. `p_next` and `wait_cost`
#'   are `NA_real_` this story.
recommend_players <- function(state, projection_snapshot,
                              weights = default_decision_weights(), n = 10L) {
  if (!all(c("roster_value", "tier_cliff", "adp_value") %in% names(weights))) {
    stop("recommend_players(): weights needs roster_value, tier_cliff, adp_value")
  }
  n <- .warroom_whole_scalar(n, "recommend_players(): n")

  view <- derive_draft_view(state, projection_snapshot)
  if (isTRUE(view$is_complete) || nrow(view$available) == 0L) {
    return(.warroom_empty_recs())
  }

  league    <- state$league
  flex_pos  <- as.character(league$flex_positions)
  roster    <- view$rosters[[state$user_team]]
  available <- view$available
  need      <- .warroom_unfilled_mandatory(roster, league)
  picks_remaining <- as.integer(league$rounds) -
    (if (is.null(roster)) 0L else nrow(roster))
  tight  <- picks_remaining <= need$total
  round_on_clock <- suppressWarnings(as.integer(view$round_on_clock))
  kdst_ok_round  <- is.finite(round_on_clock) &&
    round_on_clock >= as.integer(league$rounds) - .warroom_kdst_grace_rounds

  ## --- eligibility filter (invariants 7-9) ------------------------------
  keep <- logical(nrow(available))
  for (i in seq_len(nrow(available))) {
    pos <- available$pos[i]
    fills <- .warroom_fills_mandatory(pos, need, flex_pos)
    if (!fills && picks_remaining <= need$total) next          # would strand a slot
    if (!is.na(pos) && pos %in% c("K", "DST") && !kdst_ok_round && !tight) next
    keep[i] <- TRUE
  }
  cand <- available[keep, , drop = FALSE]
  if (nrow(cand) == 0L) return(.warroom_empty_recs())

  ## --- components -------------------------------------------------------
  r_pos <- if (is.null(roster) || nrow(roster) == 0L) character(0) else
    as.character(roster$pos)
  r_val <- if (is.null(roster) || nrow(roster) == 0L) numeric(0) else
    .warroom_value_of(roster)
  base_lineup <- .warroom_best_lineup(r_pos, r_val, league)

  vor  <- as.numeric(.warroom_col(cand, "vor"))
  tier <- suppressWarnings(as.numeric(.warroom_col(cand, "tier")))
  adp  <- as.numeric(.warroom_col(cand, "adp"))
  cand_val <- .warroom_value_of(cand)
  current_overall <- suppressWarnings(as.numeric(view$current_overall))

  marginal   <- numeric(nrow(cand))
  roster_val <- numeric(nrow(cand))
  bench_val  <- numeric(nrow(cand))
  cliff      <- numeric(nrow(cand))
  for (i in seq_len(nrow(cand))) {
    m <- .warroom_best_lineup(c(r_pos, cand$pos[i]), c(r_val, cand_val[i]),
                              league) - base_lineup
    marginal[i] <- m
    bv <- max(0, if (is.finite(vor[i])) vor[i] else 0) *
      (if (!is.na(cand$pos[i]) && cand$pos[i] %in% names(.warroom_bench_factor))
        .warroom_bench_factor[[cand$pos[i]]] else 0)
    bench_val[i]  <- bv
    roster_val[i] <- if (m > 0) m else bv
    cliff[i]      <- .warroom_tier_cliff(cand[i, ], available)
  }
  adp_value <- ifelse(is.finite(adp) & is.finite(current_overall),
                      current_overall - adp, 0)

  ## --- score + guardrail penalties -------------------------------------
  score <- 100 * (weights[["roster_value"]] * .warroom_norm01(roster_val) +
                    weights[["tier_cliff"]]  * .warroom_norm01(cliff) +
                    weights[["adp_value"]]   * .warroom_norm01(adp_value))

  fill_qb <- .warroom_pos_count(roster, "QB")
  fill_te <- .warroom_pos_count(roster, "TE")
  slots   <- .warroom_slot_counts(league)
  starters_open_excl <- function(excl) {
    sum(need$by_pos[setdiff(c("QB", "RB", "WR", "TE"), excl)]) + need$flex > 0L
  }
  qb2 <- !is.na(cand$pos) & cand$pos == "QB" & fill_qb >= slots$QB &
    starters_open_excl("QB")
  te2 <- !is.na(cand$pos) & cand$pos == "TE" & fill_te >= slots$TE &
    starters_open_excl("TE")
  score <- pmax(0, score - qb2 * .warroom_qb2_penalty - te2 * .warroom_te2_penalty)

  ## --- rank ------------------------------------------------------------
  ord  <- order(-score, cand$player_id, method = "radix")
  cand <- cand[ord, , drop = FALSE]
  score <- score[ord]; marginal <- marginal[ord]; bench_val <- bench_val[ord]
  roster_val <- roster_val[ord]; cliff <- cliff[ord]; adp_value <- adp_value[ord]
  vor <- vor[ord]; tier <- tier[ord]; adp <- adp[ord]
  qb2 <- qb2[ord]; te2 <- te2[ord]

  ## --- labels + reasons ----------------------------------------------
  label  <- character(nrow(cand))
  reason <- character(nrow(cand))
  for (i in seq_len(nrow(cand))) {
    pos <- cand$pos[i]; t <- tier[i]
    fills_need <- .warroom_fills_mandatory(pos, need, flex_pos)
    same_pos <- available[!is.na(available$pos) & available$pos == pos, , drop = FALSE]
    tier_left <- if (is.finite(t) && "tier" %in% names(same_pos))
      sum(is.finite(same_pos$tier) & same_pos$tier == t) else NA_integer_
    in_tier_or_better <- if (is.finite(t) && "tier" %in% names(same_pos))
      sum(!is.finite(same_pos$tier) | same_pos$tier <= t) else nrow(same_pos)
    cliff_cond <- !is.na(pos) && pos %in% .warroom_lineup_pos &&
      is.finite(tier_left) && tier_left <= 1L
    slack <- picks_remaining - need$total
    need_critical <- isTRUE(fills_need) &&
      (slack <= .warroom_roster_need_slack ||
         in_tier_or_better <= .warroom_roster_need_depth)

    label[i] <- if (i == 1L && (need_critical || cliff_cond) &&
                    score[i] >= .warroom_take_now_score) {
      "TAKE NOW"
    } else if (need_critical) {
      "ROSTER NEED"
    } else if (cliff_cond) {
      "TIER CLIFF"
    } else if (is.finite(adp_value[i]) && adp_value[i] >= .warroom_best_value_adp) {
      "BEST VALUE"
    } else {
      "CAN WAIT"
    }
    reason[i] <- .warroom_rec_reason(
      marginal[i], bench_val[i], vor[i], cliff_cond, t, pos, tier_left,
      fills_need, .warroom_slot_label(pos, need, flex_pos),
      adp_value[i], qb2[i], te2[i]
    )
  }

  out <- data.frame(
    player_id = as.character(cand$player_id),
    player    = as.character(cand$player),
    pos       = as.character(cand$pos),
    points    = as.numeric(cand$points),
    vor       = as.numeric(vor),
    tier      = as.numeric(tier),
    adp       = as.numeric(adp),
    p_next    = NA_real_,
    marginal_value = as.numeric(marginal),
    wait_cost = NA_real_,
    tier_cliff = as.numeric(cliff),
    adp_value = as.numeric(adp_value),
    decision_score = as.numeric(score),
    label     = label,
    reason    = reason,
    stringsAsFactors = FALSE
  )
  out <- out[, .warroom_rec_columns, drop = FALSE]
  out <- utils::head(out, n)
  rownames(out) <- NULL
  out
}
