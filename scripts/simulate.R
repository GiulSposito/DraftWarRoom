#!/usr/bin/env Rscript
## scripts/simulate.R -- mock-draft simulator + weight calibration (CAP-10).
##
## Adapter only: I/O, arg parsing, printing. Every rule lives in R/simulation.R
## (opponent_pick, simulate_draft, compare_strategies, default_weight_grid,
## calibrate_weights). No network here or anywhere on the live path (AGENTS.md).
##
## Default (no args): a reduced, fast suite -- compare_strategies() for a
## couple of seeds, printed, all_rosters_valid checked; exits 1 if any
## strategy left an invalid roster.
##
## --calibrate: the full weight-grid calibration (default_weight_grid(),
## default seeds/slots) -- much heavier, run only on explicit request.
##
## Run: make simulate                        (reduced suite)
##      Rscript scripts/simulate.R --calibrate  (full calibration)

source("R/load_core.R")
load_core()

cfg      <- .warroom_load_config()
snapshot <- load_projections(cfg$paths$projections)

team_order <- sprintf("Team %02d", seq_len(cfg$league$teams))
user_team  <- if (!is.null(cfg$user_team) && cfg$user_team %in% team_order) {
  cfg$user_team
} else {
  team_order[1L]
}
base_seed <- if (is.null(cfg$seed) || is.na(cfg$seed)) 1L else as.integer(cfg$seed)

args <- commandArgs(trailingOnly = TRUE)
if (length(args) > 0L && !all(args == "--calibrate")) {
  unknown <- args[!(args == "--calibrate")][1L]
  stop("scripts/simulate.R: argumento desconhecido '", unknown, "'. ",
       "Uso valido: 'Rscript scripts/simulate.R' (suite reduzida) ou ",
       "'Rscript scripts/simulate.R --calibrate' (calibracao completa)")
}
calibrate <- "--calibrate" %in% args

if (!calibrate) {
  cat("== simulador: suite reduzida (adp / vor / warroom) ==\n")
  seeds  <- c(base_seed, base_seed + 1L)
  all_ok <- TRUE
  tryCatch({
    for (sd in seeds) {
      cat(sprintf("\n-- seed %d (usuario = %s) --\n", sd, user_team))
      cmp <- compare_strategies(snapshot, team_order, user_team, seed = sd)
      print(cmp, row.names = FALSE)
      if (!all(cmp$all_rosters_valid)) all_ok <- FALSE
    }
  }, error = function(e) {
    message("SIMULATE FAIL: ", conditionMessage(e))
    quit(status = 1L, save = "no")
  })

  if (!all_ok) {
    message("SIMULATE FAIL: pelo menos uma estrategia deixou um roster invalido")
    quit(status = 1L, save = "no")
  }
  cat("\ntodas as estrategias completaram com os 12 rosters validos.\n")
  quit(status = 0L, save = "no")
}

cat("== calibracao completa (grade default -- pode demorar) ==\n")
grid <- calibrate_weights(snapshot, team_order)
print(grid, row.names = FALSE)
cat("\nmelhor configuracao (maior risk_score):\n")
top <- utils::head(grid, 1L)
print(top, row.names = FALSE)
if (!isTRUE(top$all_valid[1L])) {
  cat("AVISO: melhor configuracao encontrada nao passou all_valid (pelo menos um roster ficou invalido em alguma simulacao)\n")
}
quit(status = 0L, save = "no")
