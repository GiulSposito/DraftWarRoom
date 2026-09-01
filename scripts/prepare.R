#!/usr/bin/env Rscript
## scripts/prepare.R -- pre-draft projection preparation (CAP-1).
##
## The ONLY file in this repository that may call `ffanalytics` or `yaml`, and
## the only one that touches the network. It is an adapter: it orchestrates
## `ffanalytics` + the functional core and owns no formula of its own. Every
## calculation (scoring merge, field mapping, snapshot assembly) lives in
## R/projections.R (`warroom_scoring()`, `normalize_projections()`).
##
## Pipeline (preparation-pipeline.md):
##   1. load core + config.R
##   2. read league scoring overrides from config/score_settings.yml
##   3. warroom_scoring(ffanalytics::scoring, overrides)  -- copy-and-override
##   4. scrape_data() for QB/RB/WR/TE/K/DST, week = 0  (or reuse data/raw_scrape.rds)
##   5. save the raw scrape to data/raw_scrape.rds
##   6. projections_table(avg_type = method) + add_player_info() + add_adp()
##   7. normalize_projections() -> validated snapshot list
##   8. save the immutable snapshot to data/projections.rds
##
## Flags:
##   --rescrape   ignore an existing data/raw_scrape.rds and scrape fresh
##
## Run: make prepare   (Rscript scripts/prepare.R)

args     <- commandArgs(trailingOnly = TRUE)
unknown  <- setdiff(args, "--rescrape")
if (length(unknown)) {
  stop("unknown argument(s): ", paste(unknown, collapse = ", "),
       " -- the only accepted flag is --rescrape")
}
rescrape <- "--rescrape" %in% args

source("R/load_core.R")
load_core()

## config.R -- values only; sourced into an isolated environment.
config_env <- new.env(parent = baseenv())
sys.source("config.R", envir = config_env)
paths        <- config_env$paths
season       <- config_env$season
method       <- config_env$method
vor_baseline <- config_env$vor_baseline

stopifnot(
  is.list(paths), !is.null(paths$scoring),
  !is.null(season), !is.null(method), !is.null(vor_baseline)
)

## --- Step 1-3: league scoring by copy-and-override -----------------------------
if (!file.exists(paths$scoring)) {
  stop("scoring overrides not found at '", paths$scoring, "'")
}
overrides <- yaml::read_yaml(paths$scoring)
if (!is.list(overrides) || length(overrides) == 0L ||
    is.null(names(overrides)) || any(!nzchar(names(overrides)))) {
  stop("scoring overrides at '", paths$scoring,
       "' did not parse to a non-empty fully-named list ",
       "(an empty or all-comments YAML file parses to NULL)")
}
scoring <- warroom_scoring(ffanalytics::scoring, overrides)

## --- Step 4-5: scrape (or reuse the saved raw result) -------------------------
scrape_pos <- c("QB", "RB", "WR", "TE", "K", "DST")
if (file.exists(paths$raw_scrape) && !rescrape) {
  message("Reusing existing raw scrape: ", paths$raw_scrape,
          " (pass --rescrape to force a fresh scrape)")
  raw <- readRDS(paths$raw_scrape)
  raw_season <- attr(raw, "season")
  if (!is.null(raw_season) &&
      !identical(as.integer(raw_season), as.integer(season))) {
    stop("saved raw scrape is for season ", raw_season,
         " but config.R season is ", season, "; pass --rescrape to refresh it")
  }
} else {
  message("Scraping projections for ", paste(scrape_pos, collapse = "/"),
          " (season ", season, ", week 0) ...")
  ## week = 0 is mandatory: add_adp() aborts when week != 0.
  raw <- ffanalytics::scrape_data(pos = scrape_pos, season = season, week = 0)
  dir.create(dirname(paths$raw_scrape), showWarnings = FALSE, recursive = TRUE)
  saveRDS(raw, paths$raw_scrape)
  message("Saved raw scrape: ", paths$raw_scrape)
}

## --- Step 6: aggregate + attach player info and ADP --------------------------
proj <- ffanalytics::projections_table(
  raw,
  scoring_rules = scoring,
  vor_baseline  = vor_baseline,
  avg_type      = method
)
proj <- ffanalytics::add_player_info(proj)
proj <- tryCatch(
  ffanalytics::add_adp(proj),
  error = function(e) {
    warning("add_adp() failed (", conditionMessage(e),
            "); snapshot will be written without adp/adp_sd")
    proj
  }
)
proj <- as.data.frame(proj)

## --- Step 7-8: normalize, validate, persist the immutable snapshot ----------
snap <- normalize_projections(
  proj,
  cfg = list(season = season, method = method, vor_baseline = vor_baseline),
  scoring    = scoring,
  created_at = Sys.time()
)

dir.create(dirname(paths$projections), showWarnings = FALSE, recursive = TRUE)
saveRDS(snap, paths$projections)

## --- Summary ----------------------------------------------------------------
pos_tab <- table(factor(snap$players$pos,
                        levels = c("QB", "RB", "WR", "TE", "K", "DST")))
ff_sha  <- utils::packageDescription("ffanalytics")$RemoteSha
if (is.null(ff_sha) || !length(ff_sha)) {
  ff_sha <- utils::packageDescription("ffanalytics")$GithubSHA1
}
if (is.null(ff_sha) || !length(ff_sha)) ff_sha <- "unknown"

cat(sprintf("\nprepared %s -- %d players (season %d, method %s)\n",
            paths$projections, nrow(snap$players), snap$season, snap$method))
for (p in names(pos_tab)) cat(sprintf("  %-3s %3d\n", p, pos_tab[[p]]))
cat(sprintf("adp columns: %s\n",
            if (all(c("adp", "adp_sd") %in% names(snap$players))) "yes" else "no (unavailable)"))
cat(sprintf("ffanalytics: %s @ %s\n",
            utils::packageDescription("ffanalytics")$Version, ff_sha))
cat(sprintf("raw scrape:  %s\n", paths$raw_scrape))
