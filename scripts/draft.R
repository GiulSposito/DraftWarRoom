#!/usr/bin/env Rscript
## scripts/draft.R -- operational terminal draft loop (CAP-7).
##
## Adapter only. This file owns I/O, prompt strings, command dispatch, and the
## numbered disambiguation list. Every rule lives in R/:
##   * pick validation      -- record_pick() / undo_pick()   (R/core.R)
##   * schedule and views   -- derive_draft_view() / next_user_pick()
##   * player-name matching  -- resolve_player()             (R/core.R)
##   * board ordering        -- available_board()            (R/core.R)
##   * persistence           -- load_state() / save_state()  (R/persistence.R)
## No network here or anywhere on the live path (AGENTS.md).
##
## Run: make draft   (Rscript scripts/draft.R)

source("R/load_core.R")
load_core()

`%||%` <- function(a, b) if (is.null(a)) b else a

## config.R -- values only, isolated environment (same pattern as prepare.R).
.warroom_draft_config <- function() {
  path <- .warroom_find_file("config.R")
  if (is.null(path)) {
    stop("config.R not found from '", getwd(), "'; run from the repo root")
  }
  env <- new.env(parent = baseenv())
  sys.source(path, envir = env)
  env
}

## Read one line from `con`; NA on EOF.
.warroom_read_line <- function(con) {
  line <- readLines(con, n = 1L, warn = FALSE)
  if (length(line) == 0L) NA_character_ else line
}

## --- renderers (pure formatting over derived views) -------------------------

.warroom_fmt_player <- function(row) {
  has <- function(f) !is.null(row[[f]]) && length(row[[f]]) == 1L && !is.na(row[[f]])
  bits <- paste0(if (has("player")) row$player else "?",
                 " (", if (has("pos")) row$pos else "?")
  if (has("points")) bits <- paste0(bits, ", ", round(row$points, 1), " pts")
  if (has("vor"))    bits <- paste0(bits, ", VOR ", round(row$vor, 1))
  if (has("tier"))   bits <- paste0(bits, ", tier ", row$tier)
  if (has("adp"))    bits <- paste0(bits, ", ADP ", round(row$adp, 1))
  paste0(bits, ")")
}

.warroom_print_banner <- function(state, view, say) {
  nup <- next_user_pick(state)
  say(sprintf(
    "R%02d  overall %d  |  na vez: %s  |  seu proximo pick: %s",
    view$round_on_clock, view$current_overall, view$team_on_clock,
    if (is.na(nup)) "-" else as.character(nup)
  ))
}

.warroom_print_board <- function(view, pos, say) {
  board <- tryCatch(
    available_board(view, pos = pos, n = 15L),
    error = function(e) { say("  ", conditionMessage(e)); NULL }
  )
  if (is.null(board)) return(invisible(NULL))
  if (nrow(board) == 0L) { say("  (nenhum jogador disponivel)"); return(invisible(NULL)) }
  header <- if (is.null(pos)) "melhores disponiveis:" else
    paste0("melhores disponiveis (", toupper(pos), "):")
  say(header)
  for (i in seq_len(nrow(board))) {
    say(sprintf("  %2d. %s", i, .warroom_fmt_player(board[i, ])))
  }
}

.warroom_print_roster <- function(roster_df, label, say) {
  say(label, ":")
  if (is.null(roster_df) || nrow(roster_df) == 0L) { say("  (vazio)"); return(invisible(NULL)) }
  ord <- if ("overall_rank" %in% names(roster_df))
    order(roster_df$overall_rank, roster_df$player_id, method = "radix") else
    seq_len(nrow(roster_df))
  roster_df <- roster_df[ord, , drop = FALSE]
  for (i in seq_len(nrow(roster_df))) {
    say("  - ", .warroom_fmt_player(roster_df[i, ]))
  }
}

.warroom_show_recommendations <- function(state, snapshot, view, say) {
  recs <- tryCatch(
    recommend_players(state, snapshot),
    error = function(e) { say("  recommend_players(): ", conditionMessage(e)); NULL }
  )
  if (is.null(recs)) return(invisible(NULL))
  if (nrow(recs) == 0L) {
    say("(sem recomendacoes -- draft completo ou nenhum jogador elegivel)")
    return(invisible(NULL))
  }
  fmt_num <- function(x, digits = 1L, plus = FALSE) {
    if (length(x) != 1L || is.na(x)) return("-")
    sprintf(if (plus) paste0("%+.", digits, "f") else paste0("%.", digits, "f"), x)
  }
  say("recomendacoes (top ", nrow(recs), "):")
  for (i in seq_len(nrow(recs))) {
    r <- recs[i, ]
    say(sprintf("  %2d. %-22s %-3s  score %5.1f  [%s]",
                i, substr(r$player, 1L, 22L), r$pos, r$decision_score, r$label))
    say(sprintf("      pts %s  VOR %s  tier %s  ADP %s  |  %s",
                fmt_num(r$points), fmt_num(r$vor, plus = TRUE),
                if (is.na(r$tier)) "-" else as.character(r$tier),
                fmt_num(r$adp), r$reason))
  }
  invisible(NULL)
}

.warroom_print_help <- function(say) {
  say("comandos: /rec  /board  /board <pos>  /team  /teams  /undo  /status  /save  /quit")
  say("ou digite um nome de jogador para draftar para o time na vez")
}

## --- the loop --------------------------------------------------------------

#' Run the interactive terminal draft (CAP-7).
#'
#' @param con input connection; `NULL` opens `file("stdin")` (works for both a
#'   pipe and a terminal under `Rscript`, unlike `stdin()`).
#' @param out output connection (default the process stdout).
#' @param snapshot projection snapshot; `NULL` loads `config$paths$projections`.
#' @param state_path path to `state/draft.rds`; `NULL` uses `config$paths$draft_state`.
#' @param config config.R environment; `NULL` loads the real one.
#' @return invisible(state_path).
run_draft <- function(con = NULL, out = stdout(),
                      snapshot = NULL, state_path = NULL, config = NULL) {
  if (is.null(con)) {
    con <- file("stdin", open = "r")
    on.exit(close(con), add = TRUE)
  }
  cfg <- config %||% .warroom_draft_config()
  if (is.null(state_path)) state_path <- cfg$paths$draft_state
  if (length(state_path) != 1L || is.na(state_path) || !nzchar(state_path)) {
    stop("run_draft(): no draft-state path (config.R paths$draft_state is unset)")
  }
  if (is.null(snapshot)) {
    proj_path <- cfg$paths$projections
    if (length(proj_path) != 1L || is.na(proj_path) || !nzchar(proj_path)) {
      stop("run_draft(): no projections path (config.R paths$projections is unset)")
    }
    snapshot <- load_projections(proj_path)
  }

  say  <- function(...) cat(..., "\n", sep = "", file = out)
  ## Save, reporting a failure instead of aborting the live draft.
  safe_save <- function(st) tryCatch({ save_state(st, state_path); TRUE },
    error = function(e) { say("FALHA AO SALVAR: ", conditionMessage(e)); FALSE })

  ## --- startup: resume or create ------------------------------------------
  if (file.exists(state_path)) {
    state <- load_state(state_path)
    say("== retomando ", state_path, " (", nrow(state$picks), " picks) ==")
  } else {
    teams <- cfg$league$teams
    slot  <- cfg$user_slot
    say("== novo draft ==")
    say("digite os ", teams, " times em ordem de slot, separados por virgula:")
    state <- NULL
    repeat {
      raw <- .warroom_read_line(con)
      if (is.na(raw)) { say("entrada encerrada antes de criar o draft"); return(invisible(state_path)) }
      nm <- trimws(strsplit(raw, ",", fixed = TRUE)[[1]])
      nm <- nm[nzchar(nm)]
      if (length(nm) < slot) {
        say("ordem invalida: informe ao menos ", slot, " nomes (seu slot e ", slot, ")")
        next
      }
      state <- tryCatch(
        new_draft(snapshot, nm, nm[slot], seed = cfg$seed, league = cfg$league),
        error = function(e) { say("ordem invalida: ", conditionMessage(e)); NULL }
      )
      if (!is.null(state)) break
    }
    safe_save(state)
    say("draft criado: ", state_path, "  (voce = ", state$user_team, ")")
  }

  ## --- command loop ------------------------------------------------------
  ## Each iteration's derive/render/dispatch is wrapped: an unexpected error
  ## degrades to a message and the loop continues -- a live draft must not die
  ## on a rendering bug (SPEC "Why"). Only /quit and a complete draft break.
  quitting <- FALSE
  repeat {
    tryCatch({
      view <- derive_draft_view(state, snapshot)
      if (isTRUE(view$is_complete)) {
        say("=== DRAFT COMPLETO -- ", nrow(state$picks), " picks ===")
        quitting <- TRUE
      } else {
        .warroom_print_banner(state, view, say)
        if (identical(view$team_on_clock, state$user_team)) {
          .warroom_show_recommendations(state, snapshot, view, say)
        }
        cat("pick ", view$current_overall, " > ", sep = "", file = out)

        line <- .warroom_read_line(con)
        if (is.na(line)) line <- "/quit"        # EOF -> save and quit cleanly
        line <- trimws(line)

        if (nzchar(line) && startsWith(line, "/")) {
          parts <- strsplit(line, "[[:space:]]+")[[1]]
          cmd   <- tolower(parts[1])
          arg   <- if (length(parts) > 1L) parts[2] else NULL
          if (cmd == "/quit") {
            safe_save(state)
            say("salvo em ", state_path, ". ate mais.")
            quitting <- TRUE
          } else if (cmd == "/save") {
            if (safe_save(state)) say("salvo em ", state_path)
          } else if (cmd == "/rec") {
            .warroom_show_recommendations(state, snapshot, view, say)
          } else if (cmd == "/board") {
            .warroom_print_board(view, arg, say)
          } else if (cmd == "/team") {
            .warroom_print_roster(view$rosters[[state$user_team]], state$user_team, say)
          } else if (cmd == "/teams") {
            for (tm in state$team_order) .warroom_print_roster(view$rosters[[tm]], tm, say)
          } else if (cmd == "/status") {
            .warroom_print_banner(state, view, say)
          } else if (cmd == "/undo") {
            state <- tryCatch({
              s <- undo_pick(state); safe_save(s); say("desfeito o ultimo pick"); s
            }, error = function(e) { say("nada a desfazer: ", conditionMessage(e)); state })
          } else if (cmd == "/help") {
            .warroom_print_help(say)
          } else {
            say("comando desconhecido: ", cmd, "  (/help)")
          }
        } else if (nzchar(line)) {
          ## bare line -> player name for the team on the clock
          res <- resolve_player(line, view$available, snapshot$players)
          if (res$status == "none") {
            say("nenhum jogador disponivel casa '", line, "'")
          } else {
            chosen <- NULL
            if (res$status == "ambiguous") {
              if (nrow(res$players) > 25L) {
                say(nrow(res$players), " jogadores casam '", line,
                    "' -- seja mais especifico")
              } else {
                say("varios jogadores casam '", line, "':")
                for (i in seq_len(nrow(res$players))) {
                  say(sprintf("  %d) %s", i, .warroom_fmt_player(res$players[i, ])))
                }
                cat("numero > ", file = out)
                sel <- .warroom_read_line(con)
                if (is.na(sel)) {
                  say("cancelado")
                } else {
                  sel <- suppressWarnings(as.integer(trimws(sel)))
                  if (is.na(sel) || sel < 1L || sel > nrow(res$players)) {
                    say("numero fora do range")
                  } else {
                    chosen <- res$players$player_id[sel]
                  }
                }
              }
            } else {
              chosen <- res$players$player_id[1L]
            }
            if (!is.null(chosen)) {
              team_on_clock <- view$team_on_clock
              state <- tryCatch({
                s  <- record_pick(state, chosen, snapshot)
                safe_save(s)
                pl <- snapshot$players[snapshot$players$player_id == chosen, ]
                say(sprintf("PICK %d: %s (%s) -> %s",
                            nrow(s$picks), pl$player, pl$pos, team_on_clock))
                s
              }, error = function(e) { say("pick rejeitado: ", conditionMessage(e)); state })
            }
          }
        }
        ## blank line: fall through -> reprompt
      }
    }, error = function(e) {
      say("erro inesperado: ", conditionMessage(e), " (draft segue; tente de novo ou /quit)")
    })
    if (quitting) break
  }

  invisible(state_path)
}

## Execute only under `Rscript scripts/draft.R` (top-level frame). When this file
## is source()d from tests/smoke.R the frame is deeper, so run_draft() is defined
## but not run.
if (sys.nframe() == 0L) {
  run_draft()
}
