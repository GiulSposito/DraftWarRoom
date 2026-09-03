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

  ## Fixed status strip (DESIGN.md "Faixa de estado", A2). Direct child of
  ## fluidPage, sibling to .app-header -- so its sticky container block is
  ## .container-fluid (the whole scroll area), not a one-row .col-sm-12. This
  ## is a header element like .app-header, not the story-14 layout grid.
  uiOutput("status_strip"),

  ## Persistent pick/undo feedback region (DESIGN.md "Feedback e erro", A5).
  ## Sibling immediately below the status strip -- a renderUI over a
  ## reactiveVal, never a dismissible toast: confirmations are brief and
  ## textual, errors persist until the next pick/undo.
  uiOutput("draft_feedback"),

  fluidRow(
    column(5,
      selectizeInput("player_choice", "Jogador",
                     choices = NULL,
                     options = list(placeholder = "buscar jogador disponível...")),
      actionButton("draft_btn", "Registrar", class = "btn-primary"),
      actionButton("undo_btn", "Undo")
    ),
    column(3,
      selectInput("pos_filter", "Filtrar disponíveis por posição",
                  choices = c("ALL", .warroom_pos_levels), selected = "ALL")
    )
  ),

  fluidRow(
    column(12, h4("Recomendações"),
           div(class = "recs-note", textOutput("recs_note")),
           div(class = "recs-filters",
               radioButtons("recs_pos_filter",
                            "Filtrar recomendações por posição",
                            choices = c("Todos", .warroom_pos_levels),
                            selected = "Todos", inline = TRUE)),
           uiOutput("recs_table"))
  ),

  fluidRow(
    column(6, h4("Seu roster"), uiOutput("roster_table")),
    column(6, h4("Picks recentes"), tableOutput("recent_picks_table"))
  ),

  fluidRow(
    column(12, h4("Disponíveis"), tableOutput("available_table"))
  ),

  ## All-team rosters (story 15). Full-width row at the foot of the page -- the
  ## board / opponent-roster tier sits below the operational core (status,
  ## recommendations, operator roster), DESIGN.md Layout & Spacing. The native
  ## <details>/<summary> lives here in the static ui (not in the renderUI) so its
  ## collapsed/open DOM state survives every per-pick re-render of the grid.
  ## `open = NA` -> `<details ... open>` (open by default). The <summary> wraps
  ## the section's <h4> so it is both the disclosure control and a heading.
  fluidRow(
    column(12,
      tags$details(class = "all-rosters", open = NA,
        tags$summary(tags$h4("Rosters dos times")),
        uiOutput("all_rosters_table")))
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

  ## Persistent pick/undo feedback (story 13, A5). Holds the last event as
  ## list(kind = "ok" | "error", text = <string>); NULL before the first
  ## event. Written only by the two observeEvent handlers below -- and only
  ## after commit_state() has succeeded, or in the tryCatch error branch. No
  ## timer / invalidateLater: the region changes only on the next pick or undo.
  feedback <- reactiveVal(NULL)

  ## record_pick()/undo_pick() then save_state() BEFORE updating the
  ## reactiveVal -- same order as the terminal (AGENTS.md: never update the UI
  ## before the save has succeeded). Errors propagate to the caller, which
  ## writes the feedback region and leaves `state` untouched.
  commit_state <- function(new_st) {
    save_state(new_st, state_path)
    state(new_st)
  }

  view <- reactive({ derive_draft_view(state(), snapshot) })
  recs <- reactive({ recommend_players(state(), snapshot) })

  ## Position-badge view over the cached recs() frame (story 11 / 14). Pure
  ## subset -- recommend_players() is never re-called on a badge change or a row
  ## click (AGENTS.md performance guardrail). The smart list renders this; the
  ## row-click observers register recs_view()$player_id[k].
  recs_view <- reactive({
    r   <- recs()
    pos <- input$recs_pos_filter %||% "Todos"
    if (!identical(pos, "Todos")) {
      r <- r[!is.na(r$pos) & r$pos == pos, , drop = FALSE]
    }
    r
  })

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
  ## record_pick()/undo_pick()/commit_state() are called exactly as before, in
  ## the same order, inside the same tryCatch. Only the operator feedback path
  ## changed: each branch now writes feedback() with an EXPERIENCE.md Voice and
  ## Tone string instead of raising a transient notification. The pick number N
  ## in the already-drafted / undo messages is derived from state()$picks
  ## (overall of the matching row) -- a persisted fact, never a new field.
  ##
  ## do_pick() is the single pick code path (story 14): both the "Registrar"
  ## button and a click on a candidate row call it, so record_pick() is invoked
  ## in exactly one place. `empty_msg` is the caller-specific text shown when the
  ## incoming id is missing (the search box vs an out-of-range recommendation).
  do_pick <- function(pid, empty_msg) {
    if (is.null(pid) || length(pid) != 1L || is.na(pid) || !nzchar(pid)) {
      feedback(list(kind = "error", text = empty_msg))
      return(invisible(NULL))
    }
    tryCatch({
      st <- record_pick(state(), pid, snapshot)
      commit_state(st)
      updateSelectizeInput(session, "player_choice", selected = "")
      nome <- snapshot$players$player[match(pid, snapshot$players$player_id)]
      feedback(list(kind = "ok", text = sprintf("Registrado: %s", nome)))
    }, error = function(e) {
      msg <- conditionMessage(e)
      picks_now <- state()$picks
      n <- picks_now$overall[match(pid, picks_now$player_id)]
      if (grepl("already been drafted", msg, fixed = TRUE) && !is.na(n)) {
        feedback(list(kind = "error", text = sprintf(
          "Já escolhido no pick %d. Busque outro jogador.", as.integer(n))))
      } else {
        feedback(list(kind = "error",
                      text = sprintf("Pick não registrado: %s", msg)))
      }
    })
  }

  observeEvent(input$draft_btn, {
    do_pick(input$player_choice,
            "Selecione um jogador na busca antes de registrar.")
  })

  ## Click-to-pick (story 14). Each candidate row is a <button id="pick_row_k">
  ## bound as a Shiny action button; row k registers the player at rank k of the
  ## currently filtered frame (recs_view()). Fixed at 10 rows -- the n = 10L
  ## default of recommend_players(). Same do_pick() path as the button above; a
  ## row click never re-calls recommend_players().
  ## lapply (not `for`) so the index never leaks into the server environment;
  ## force() pins it before observeEvent captures the deferred eventExpr.
  lapply(seq_len(10L), function(rank_i) {
    force(rank_i)
    nm <- sprintf("pick_row_%d", rank_i)
    observeEvent(input[[nm]], {
      rv  <- recs_view()
      pid <- if (rank_i <= nrow(rv)) rv$player_id[rank_i] else NA_character_
      do_pick(pid, "Essa recomendação não está mais na lista.")
    }, ignoreInit = TRUE)
  })

  observeEvent(input$undo_btn, {
    pk <- state()$picks
    had_pick <- nrow(pk) > 0L
    ov <- if (had_pick) as.integer(pk$overall[nrow(pk)]) else NA_integer_
    tryCatch({
      st <- undo_pick(state())
      commit_state(st)
      feedback(list(kind = "ok", text = if (is.na(ov)) "Undo aplicado."
        else sprintf("Undo aplicado — pick %d voltou a aberto.", ov)))
    }, error = function(e) {
      ## undo_pick() only raises when there are no picks; anything else that
      ## lands here (e.g. save_state() failing) is a real failure and must be
      ## surfaced, not reported as "nothing to undo" (EXPERIENCE.md "Falha
      ## local de persistência").
      feedback(list(kind = "error", text = if (had_pick)
        sprintf("Undo não aplicado: %s", conditionMessage(e))
        else "Nada a desfazer — nenhum pick efetivo."))
    })
  })

  ## --- rendering (pure formatting over derived views / recommendations) ---

  ## Fixed status strip -- pure formatting over the same derived views
  ## output$banner used (derive_draft_view(), next_user_pick()), plus the
  ## "Ultimo" line derived every render from state()$picks + the snake schedule
  ## + team_order + snapshot$players (same join as output$recent_picks_table).
  ## Nothing here is persisted or held in a reactiveVal. "atualiza como uma
  ## unidade" (EXPERIENCE.md) -> one renderUI, not several textOutput.
  output$status_strip <- renderUI({
    v     <- view()
    st    <- state()
    picks <- st$picks
    npicks <- nrow(picks)

    last_line <- if (npicks == 0L) {
      tags$div(class = "status-strip-last",
               tags$span(class = "status-strip-label", "Último"),
               tags$span("—"))
    } else {
      sched <- make_snake_schedule(st$league$teams, st$league$rounds)
      last  <- picks[npicks, ]
      pl    <- snapshot$players[match(last$player_id, snapshot$players$player_id), ]
      time  <- st$team_order[sched$slot[last$overall]]
      ## nfl_team is an optional snapshot field (R/projections.R:333 -- only
      ## player_id/player/pos/points are required); drop it rather than print NA.
      nfl   <- pl$nfl_team
      meta  <- if (is.null(nfl) || is.na(nfl) || !nzchar(nfl)) {
        sprintf("%s · %s", pl$pos, time)
      } else {
        sprintf("%s · %s · %s", pl$pos, nfl, time)
      }
      tags$div(class = "status-strip-last",
        tags$span(class = "status-strip-label", "Último"),
        tags$strong(sprintf("%d · %s", last$overall, pl$player)),
        tags$span(class = "status-strip-last-meta", meta))
    }

    if (isTRUE(v$is_complete)) {
      main <- tags$div(class = "status-strip-main",
        tags$div(class = "live-pick live-pick--done",
                 sprintf("DRAFT COMPLETO · %d picks", npicks)))
    } else {
      nup <- next_user_pick(st)
      main <- tags$div(class = "status-strip-main",
        tags$div(class = "live-pick live-pick--current",
                 sprintf("PICK %d", v$current_overall)),
        tags$div(class = "status-strip-clock",
          tags$span(class = "status-strip-eyebrow",
                    sprintf("Round %02d · no relógio", v$round_on_clock)),
          tags$strong(v$team_on_clock, title = v$team_on_clock)),
        tags$div(class = "status-strip-next",
          if (is.na(nup)) "Próximo: —"
          else sprintf("Próximo: seu pick %d", nup)))
    }

    tags$div(class = "status-strip", `aria-label` = "Estado do draft",
      main,
      last_line,
      tags$div(class = "status-strip-saved", "sessão local · salva"))
  })

  ## Persistent feedback region (story 13, A5) -- pure formatting over the
  ## feedback() reactiveVal, same renderUI-over-a-reactiveVal shape the status
  ## strip / smart list / roster panel use. NULL -> an empty .draft-feedback
  ## container (collapsed by `:empty` in styles.css, nothing visible). An event
  ## -> one line with .draft-feedback--ok / --error. Static `aria-label` only;
  ## the aria-live announcement of the event is story 21.
  output$draft_feedback <- renderUI({
    fb <- feedback()
    if (is.null(fb)) {
      return(tags$div(class = "draft-feedback",
                      `aria-label` = "Feedback do registro"))
    }
    cls <- if (identical(fb$kind, "ok")) "draft-feedback draft-feedback--ok"
           else "draft-feedback draft-feedback--error"
    tags$div(class = cls, `aria-label` = "Feedback do registro", fb$text)
  })

  output$recs_note <- renderText({
    if (isTRUE(attr(recs(), "off_turn")))
      "Voce nao esta na vez -- estes numeros assumem que voce pica agora."
    else ""
  })

  ## Smart list of candidates (story 11, A3). Pure formatting over the frame
  ## recommend_players() already returned -- no column is recomputed and the
  ## row order is never touched (DESIGN.md "Lista inteligente"). The position
  ## badge subsets the cached recs() reactive (via recs_view());
  ## recommend_players() is not re-called on a filter change or a row click
  ## (AGENTS.md performance guardrail). Story 14: each row is a click target
  ## (<button>) and the reason/tier/score render at --ink (see www/styles.css).
  output$recs_table <- renderUI({
    if (nrow(recs()) == 0L) {
      return(tags$p(class = "smart-list-empty", "Nenhum candidato disponível."))
    }
    pos     <- input$recs_pos_filter %||% "Todos"
    all_pos <- identical(pos, "Todos")
    r <- recs_view()
    if (nrow(r) == 0L) {
      return(tags$p(class = "smart-list-empty",
                    sprintf("Nenhum candidato %s nas recomendações.", pos)))
    }
    dash <- "—"
    ## nfl_team is an optional snapshot field (R/projections.R -- only
    ## player_id/player/pos/points are required) and is not part of the
    ## recommend_players() frame; join it from the snapshot the same way
    ## output$recent_picks_table and the status strip do. Column absent ->
    ## bare pos, no separator, no NA.
    has_nfl <- "nfl_team" %in% names(snapshot$players)
    pl <- snapshot$players[match(r$player_id, snapshot$players$player_id), ,
                           drop = FALSE]
    rows <- lapply(seq_len(nrow(r)), function(i) {
      ## tier is the numeric source tier, rendered as it came; NA -> dash.
      tier_txt   <- if (is.na(r$tier[i])) dash else as.character(r$tier[i])
      score_txt  <- if (is.na(r$decision_score[i])) dash
                    else sprintf("%.1f", r$decision_score[i])
      reason_txt <- if (is.na(r$reason[i]) || !nzchar(r$reason[i])) dash
                    else r$reason[i]
      pos_txt <- if (is.na(r$pos[i])) "" else r$pos[i]
      nfl     <- if (has_nfl) pl$nfl_team[i] else NA_character_
      if (nzchar(pos_txt) && !is.na(nfl) && nzchar(nfl)) {
        pos_txt <- paste(pos_txt, nfl)
      }
      ## nº 1 marker: the action-green rank only when the list is unfiltered
      ## (then row 1 is the pick a click / Enter would register). Under a
      ## position badge row 1 is only "best <POS>" -- emphasised by weight, not
      ## colour. Class leads with "candidate" so story-11 row counts still match;
      ## "action-button" makes the row a Shiny click target (story 14).
      row_cls <- if (i != 1L) "candidate action-button"
                 else if (all_pos) "candidate action-button candidate--top"
                 else "candidate action-button candidate--first"
      ## Native <button>: a click anywhere on the row -- and Enter / Space --
      ## registers the pick via do_pick(). role="listitem" keeps the .smart-list
      ## (role="list") item count / position for AT until story 23 promotes the
      ## list to a proper listbox/option surface.
      tags$button(
        type = "button",
        id = sprintf("pick_row_%d", i),
        class = row_cls,
        role = "listitem",
        `aria-label` = paste("Registrar", r$player[i]),
        tags$span(class = "rank", sprintf("%02d", i)),
        tags$span(class = "name",
                  tags$span(class = "name-text", r$player[i]),
                  tags$span(class = "pos", pos_txt)),
        tags$span(class = "tier", tier_txt),
        tags$span(class = "score", score_txt),
        tags$span(class = "reason", reason_txt)
      )
    })
    tags$div(class = "smart-list", role = "list",
             `aria-label` = "Recomendações de pick",
      tags$div(class = "smart-list-head", role = "presentation",
               tags$span("#"), tags$span("Jogador"),
               tags$span("Tier"), tags$span("Score")),
      rows)
  })

  ## Grouped roster panel builder (story 12, A4; factored out of
  ## output$roster_table in story 15 so the all-team panel reuses the exact same
  ## slotting and markup -- one slotting path, AGENTS.md). Pure formatting over a
  ## derive_draft_view()$rosters[[team]] frame (0 rows or a data frame) +
  ## roster_slots() -- three fixed visual groups (Titulares / FLEX / Banco), one
  ## row per league roster slot, unfilled slots explicit ("- aberto" for
  ## starters/FLEX, "-" for the bench). roster_slots() is the sole source for
  ## QB/RB/WR/TE/FLEX; K and DST are placed into their dedicated Titulares slots
  ## by pos identity (a 1-to-1 placement, not starter selection -- roster_slots()
  ## returns them as BENCH, mirroring lineup_value()), and the bench excludes the
  ## K/DST so placed. No number (points/vor) is shown; `val` (vor, points
  ## fallback -- same currency the old renderTable used, duplication noted in
  ## deferred-work.md) only orders multi-slot rows and the bench. Slot label is
  ## ink-muted / label type, deliberately NOT the reserved action green
  ## (DESIGN.md section Colors). `aria_label` names the panel per team.
  roster_panel_ui <- function(roster, league,
                              aria_label = "Roster do operador") {
    rc <- league$roster
    has_players <- is.data.frame(roster) && nrow(roster) > 0L

    slot_at <- character(0)
    val_v   <- numeric(0)
    if (has_players) {
      sl      <- roster_slots(roster, league)
      slot_at <- sl$slot[match(roster$player_id, sl$player_id)]
      val_v   <- if ("vor" %in% names(roster)) as.numeric(roster$vor)
                 else as.numeric(roster$points)
      ## Pull K and DST out of BENCH into their own Titulares slots by pos
      ## identity, highest `val` first; any surplus K/DST stays BENCH.
      for (p in c("K", "DST")) {
        want <- rc[[p]]
        if (want > 0L) {
          cand <- which(!is.na(roster$pos) & roster$pos == p & slot_at == "BENCH")
          if (length(cand)) {
            cand <- cand[order(-val_v[cand], roster$player_id[cand],
                               method = "radix")]
            slot_at[cand[seq_len(min(want, length(cand)))]] <- p
          }
        }
      }
    }
    has_nfl <- has_players && "nfl_team" %in% names(roster)

    ## position isolated when the league carries one slot (QB, TE, K, DST),
    ## numbered when > 1 (RB1, RB2); FLEX -> FLEX; bench -> BN.
    slot_labels <- function(pos, count) {
      if (count <= 0L) character(0)
      else if (count == 1L) pos
      else paste0(pos, seq_len(count))
    }
    filled_row <- function(label, i) {
      pos_txt  <- if (is.na(roster$pos[i])) "" else as.character(roster$pos[i])
      name_txt <- if (is.na(roster$player[i])) "" else as.character(roster$player[i])
      nt       <- if (has_nfl) roster$nfl_team[i] else NA_character_
      has_nt   <- !is.na(nt) && nzchar(nt)
      meta <- if (nzchar(pos_txt) && has_nt) paste(pos_txt, nt, sep = " · ")
              else if (has_nt) nt
              else pos_txt
      tags$div(class = "roster-row",
        tags$span(class = "slot", label),
        tags$span(class = "name", name_txt),
        tags$span(class = "meta", meta))
    }
    empty_row <- function(label, placeholder) {
      tags$div(class = "roster-row roster-row--empty",
        tags$span(class = "slot", label),
        tags$span(class = "empty", placeholder))
    }
    ## players -> the group's labelled slots, ordered by `val` desc (tie:
    ## player_id); free slots always come last.
    fill_rows <- function(indices, labels, placeholder) {
      if (length(indices) > 1L) {
        indices <- indices[order(-val_v[indices], roster$player_id[indices],
                                 method = "radix")]
      }
      lapply(seq_along(labels), function(j) {
        if (j <= length(indices)) filled_row(labels[[j]], indices[[j]])
        else empty_row(labels[[j]], placeholder)
      })
    }
    group <- function(label, rows) {
      tags$div(class = "roster-group",
        tags$div(class = "roster-group-label", label),
        rows)
    }

    starter_rows <- list()
    for (p in c("QB", "RB", "WR", "TE", "K", "DST")) {
      idx <- if (has_players) which(slot_at == p) else integer(0)
      starter_rows <- c(starter_rows,
                        fill_rows(idx, slot_labels(p, rc[[p]]), "— aberto"))
    }

    flex_idx  <- if (has_players) which(slot_at == "FLEX") else integer(0)
    flex_rows <- fill_rows(flex_idx, slot_labels("FLEX", rc[["FLEX"]]),
                           "— aberto")

    bench_idx  <- if (has_players) which(slot_at == "BENCH") else integer(0)
    n_bench    <- max(rc[["BENCH"]], length(bench_idx))
    bench_rows <- fill_rows(bench_idx, rep("BN", n_bench), "—")

    tags$div(class = "roster-panel", role = "group",
             `aria-label` = aria_label,
      group("Titulares", starter_rows),
      group("FLEX", flex_rows),
      group("Banco", bench_rows))
  }

  output$roster_table <- renderUI({
    st <- state()
    roster_panel_ui(view()$rosters[[st$user_team]], st$league,
                    "Roster do operador")
  })

  ## All-team rosters grid (story 15). Read-only, derived every render from the
  ## single derive_draft_view() call in `view`. It surfaces the same
  ## per-team rosters the terminal's /teams command iterates over team_order to
  ## print (the slot grouping here is this app's, not /teams' flat list).
  ## EXPERIENCE.md frames opponent rosters as an occasional lookup ("outros
  ## rosters acessiveis no board"); the board grid itself is story 18, so this
  ## foot-of-page collapsible panel is the interim surface. Renders ONLY the
  ## .all-rosters-grid: the native <details>/<summary> that collapses it lives in
  ## the static `ui` tree, so the operator's collapse survives every per-pick
  ## re-render (Shiny would discard <details open> DOM state if this output
  ## emitted it). One .team-roster card per team, built by the same
  ## roster_panel_ui() as the operator panel. The operator's own team carries a
  ## textual "VOCE" tag, not colour alone (DESIGN.md section Colors).
  ## `view()$rosters` is indexed by POSITION -- it is built as
  ## lapply(seq_along(team_order), ...) so element i is team_order[i], and a
  ## blank / NA team name in a legacy state file cannot break the panel; such a
  ## name also falls back to "Time <i>" in the card head rather than printing NA.
  output$all_rosters_table <- renderUI({
    st  <- state()
    ros <- view()$rosters
    cards <- lapply(seq_along(st$team_order), function(i) {
      tm  <- st$team_order[i]
      nm  <- if (is.na(tm) || !nzchar(tm)) sprintf("Time %d", i) else tm
      you <- !is.na(tm) && identical(tm, st$user_team)
      tags$div(
        class = if (you) "team-roster team-roster--you" else "team-roster",
        tags$div(class = "team-roster-head",
          tags$span(class = "team-roster-name", nm),
          if (you) tags$span(class = "team-roster-you", "VOCÊ")),
        roster_panel_ui(ros[[i]], st$league, paste("Roster", nm)))
    })
    tags$div(class = "all-rosters-grid", cards)
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
