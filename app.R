#!/usr/bin/env Rscript
## app.R -- thin Shiny war room (CAP-11, story 8).
##
## Adapter only. This file owns UI layout, reactive plumbing, and rendering.
## Every rule lives in R/, reused exactly as scripts/draft.R reuses it:
##   * pick validation      -- record_pick() / undo_pick()   (R/core.R)
##   * schedule and views   -- derive_draft_view() / next_user_pick() /
##                             available_board() / make_snake_schedule()
##   * recommendation        -- recommend_players()          (R/recommendation.R)
##   * roster slotting       -- roster_slots()                (R/recommendation.R)
##   * persistence            -- load_state() / save_state()  (R/persistence.R)
## No formula (VOR, wait_cost, p_next, tier_cliff, lineup value, starter
## selection) is recomputed here. No network on this path (AGENTS.md).
##
## Run: make app   (Rscript -e 'shiny::runApp(".")')

source("R/load_core.R")
load_core()
library(shiny)

`%||%` <- function(a, b) if (is.null(a)) b else a

## config.R -- values only, isolated environment (same pattern as
## scripts/draft.R's .warroom_draft_config()).
.warroom_app_config <- function() {
  path <- .warroom_find_file("config.R")
  if (is.null(path)) {
    stop("config.R not found from '", getwd(), "'; run from the repo root")
  }
  env <- new.env(parent = baseenv())
  sys.source(path, envir = env)
  env
}

## --- UI ----------------------------------------------------------------

ui <- fluidPage(
  tags$head(
    tags$title("Draft War Room"),
    tags$link(rel = "stylesheet", href = "styles.css")
  ),
  div(class = "app-header", "Draft War Room"),

  fluidRow(
    column(12, h3(textOutput("banner")))
  ),

  fluidRow(
    column(5,
      selectizeInput("player_choice", "Jogador",
                     choices = NULL,
                     options = list(placeholder = "buscar jogador disponivel...")),
      actionButton("draft_btn", "Draft", class = "btn-primary"),
      actionButton("undo_btn", "Undo")
    ),
    column(3,
      selectInput("pos_filter", "Filtrar disponiveis por posicao",
                  choices = c("ALL", .warroom_pos_levels), selected = "ALL")
    )
  ),

  fluidRow(
    column(12, h4("Recomendacoes"),
           div(class = "recs-note", textOutput("recs_note")),
           tableOutput("recs_table"))
  ),

  fluidRow(
    column(6, h4("Seu roster"), tableOutput("roster_table")),
    column(6, h4("Picks recentes"), tableOutput("recent_picks_table"))
  ),

  fluidRow(
    column(12, h4("Disponiveis"), tableOutput("available_table"))
  )
)

## --- server --------------------------------------------------------------

#' Server for the thin Shiny war room (CAP-11).
#'
#' Same dependency-injection pattern as `scripts/draft.R`'s
#' `run_draft(con, out, snapshot, state_path, config)`: the extra args let
#' `shiny::testServer()` drive a fixture snapshot and a `tempdir()` state file
#' without touching `data/`/`state/`. Without them, uses `config.R` and the
#' real paths.
#'
#' @param input,output,session standard Shiny server args.
#' @param snapshot projection snapshot; `NULL` loads `config$paths$projections`.
#' @param state_path path to `state/draft.rds`; `NULL` uses
#'   `config$paths$draft_state`.
#' @param config config.R environment; `NULL` loads the real one.
server <- function(input, output, session, snapshot = NULL, state_path = NULL,
                   config = NULL) {
  cfg <- config %||% .warroom_app_config()
  if (is.null(state_path)) state_path <- cfg$paths$draft_state
  if (length(state_path) != 1L || is.na(state_path) || !nzchar(state_path)) {
    stop("server(): no draft-state path (config.R paths$draft_state is unset)")
  }
  if (is.null(snapshot)) {
    proj_path <- cfg$paths$projections
    if (length(proj_path) != 1L || is.na(proj_path) || !nzchar(proj_path)) {
      stop("server(): no projections path (config.R paths$projections is unset)")
    }
    snapshot <- load_projections(proj_path)
  }
  ## --- startup: resume or create -----------------------------------------
  ## No draft-order form (not in operations.md "Shiny (CAP-11)") -- a fresh
  ## draft uses the same default team_order / user_team recovery semantics as
  ## the terminal's config-driven start, saved immediately. A resumed draft's
  ## league is already in state$league, so config/league.yml is read only for a
  ## fresh draft.
  init_state <- tryCatch({
    if (file.exists(state_path)) {
      load_state(state_path)
    } else {
      league <- load_league()
      st <- new_draft(snapshot, sprintf("Team %02d", seq_len(league$teams)),
                      cfg$user_team, seed = cfg$seed, league = league)
      save_state(st, state_path)
      st
    }
  }, error = function(e) {
    stop("server(): could not load or create the draft state at '", state_path,
        "' (", conditionMessage(e), ")", call. = FALSE)
  })
  ## Same draft<->snapshot binding the terminal enforces on resume -- raised
  ## outside the load/create tryCatch so its own message reaches the operator.
  .warroom_assert_snapshot_binding(init_state, snapshot)
  state <- reactiveVal(init_state)

  ## record_pick()/undo_pick() then save_state() BEFORE updating the
  ## reactiveVal -- same order as the terminal (AGENTS.md: never update the UI
  ## before the save has succeeded). Errors propagate to the caller, which
  ## reports them via showNotification() and leaves `state` untouched.
  commit_state <- function(new_st) {
    save_state(new_st, state_path)
    state(new_st)
  }

  view <- reactive({ derive_draft_view(state(), snapshot) })
  recs <- reactive({ recommend_players(state(), snapshot) })

  ## --- player picker: choices follow the current available board ---------
  observe({
    av <- view()$available
    if (nrow(av) == 0L) {
      updateSelectizeInput(session, "player_choice", choices = character(0),
                           server = TRUE)
      return(invisible(NULL))
    }
    ord <- if ("overall_rank" %in% names(av)) {
      order(av$overall_rank, av$player_id, method = "radix")
    } else {
      order(-av$points, av$player_id, method = "radix")
    }
    av <- av[ord, , drop = FALSE]
    labels <- sprintf("%s (%s%s)", av$player, av$pos,
                      if ("points" %in% names(av))
                        sprintf(", %.1f pts", av$points) else "")
    choices <- stats::setNames(av$player_id, labels)
    updateSelectizeInput(session, "player_choice", choices = choices,
                         server = TRUE)
  })

  ## --- pick entry / undo ---------------------------------------------------
  observeEvent(input$draft_btn, {
    pid <- input$player_choice
    if (is.null(pid) || length(pid) != 1L || is.na(pid) || !nzchar(pid)) {
      showNotification("selecione um jogador antes de draftar", type = "warning")
      return(invisible(NULL))
    }
    tryCatch({
      st <- record_pick(state(), pid, snapshot)
      commit_state(st)
      updateSelectizeInput(session, "player_choice", selected = "")
    }, error = function(e) {
      showNotification(paste("pick rejeitado:", conditionMessage(e)), type = "error")
    })
  })

  observeEvent(input$undo_btn, {
    tryCatch({
      st <- undo_pick(state())
      commit_state(st)
    }, error = function(e) {
      showNotification(paste("nada a desfazer:", conditionMessage(e)), type = "error")
    })
  })

  ## --- rendering (pure formatting over derived views / recommendations) ---

  output$banner <- renderText({
    v <- view()
    if (isTRUE(v$is_complete)) {
      sprintf("=== DRAFT COMPLETO -- %d picks ===", nrow(state()$picks))
    } else {
      nup <- next_user_pick(state())
      sprintf("R%02d  overall %d  |  na vez: %s  |  seu proximo pick: %s",
              v$round_on_clock, v$current_overall, v$team_on_clock,
              if (is.na(nup)) "-" else as.character(nup))
    }
  })

  output$recs_note <- renderText({
    if (isTRUE(attr(recs(), "off_turn")))
      "Voce nao esta na vez -- estes numeros assumem que voce pica agora."
    else ""
  })

  output$recs_table <- renderTable({
    r <- recs()
    cols <- c("player", "pos", "points", "vor", "tier", "adp",
             "p_next", "wait_cost", "decision_score", "label", "reason")
    r[, intersect(cols, names(r)), drop = FALSE]
  })

  output$roster_table <- renderTable({
    st <- state()
    roster <- view()$rosters[[st$user_team]]
    if (is.null(roster) || nrow(roster) == 0L) {
      return(data.frame(slot = character(0), jogador = character(0),
                        pos = character(0), pontos = numeric(0),
                        vor = numeric(0), stringsAsFactors = FALSE))
    }
    slots   <- roster_slots(roster, st$league)
    slot_at <- slots$slot[match(roster$player_id, slots$player_id)]
    val     <- if ("vor" %in% names(roster)) roster$vor else roster$points
    slot_lv <- c("QB", "RB", "WR", "TE", "FLEX", "BENCH")
    ord <- order(match(slot_at, slot_lv), -val, roster$player_id, method = "radix")
    data.frame(
      slot    = slot_at[ord],
      jogador = roster$player[ord],
      pos     = roster$pos[ord],
      pontos  = roster$points[ord],
      vor     = if ("vor" %in% names(roster)) roster$vor[ord] else rep(NA_real_, length(ord)),
      stringsAsFactors = FALSE
    )
  })

  output$recent_picks_table <- renderTable({
    st    <- state()
    picks <- st$picks
    if (nrow(picks) == 0L) {
      return(data.frame(overall = integer(0), jogador = character(0),
                        pos = character(0), time = character(0),
                        stringsAsFactors = FALSE))
    }
    sched  <- make_snake_schedule(st$league$teams, st$league$rounds)
    n      <- nrow(picks)
    idx    <- seq.int(max(1L, n - 14L), n)
    recent <- picks[idx, , drop = FALSE]
    pl     <- snapshot$players[match(recent$player_id, snapshot$players$player_id), ]
    data.frame(
      overall = recent$overall,
      jogador = pl$player,
      pos     = pl$pos,
      time    = st$team_order[sched$slot[recent$overall]],
      stringsAsFactors = FALSE
    )[order(-recent$overall), ]
  })

  output$available_table <- renderTable({
    pos <- input$pos_filter
    pos <- if (is.null(pos) || identical(pos, "ALL") || !nzchar(pos)) NULL else pos
    board <- available_board(view(), pos = pos, n = 50L)
    cols  <- c("player", "pos", "points", "vor", "tier", "adp")
    board[, intersect(cols, names(board)), drop = FALSE]
  })
}

shinyApp(ui, server)
