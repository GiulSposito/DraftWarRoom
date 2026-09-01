## R/load_core.R -- source every other R/*.R file so adapters (scripts/, tests/,
## app.R) get the whole functional core with one call. No business logic here.

## Walk up from `start` looking for a directory named `name`; path or NULL.
.warroom_find_dir <- function(name, start = getwd()) {
  dir <- normalizePath(start, mustWork = FALSE)
  repeat {
    candidate <- file.path(dir, name)
    if (dir.exists(candidate)) return(candidate)
    parent <- dirname(dir)
    if (identical(parent, dir)) return(NULL)
    dir <- parent
  }
}

load_core <- function(root = ".") {
  r_dir <- file.path(root, "R")
  if (!dir.exists(r_dir)) {
    r_dir <- .warroom_find_dir("R")
  }
  if (is.null(r_dir) || !dir.exists(r_dir)) {
    stop("R/ directory not found from '", root, "' or any parent of '",
         getwd(), "'")
  }

  files <- list.files(r_dir, pattern = "\\.[Rr]$", full.names = TRUE)
  files <- files[basename(files) != "load_core.R"]
  files <- files[order(basename(files), method = "radix")]  # stable, locale-independent
  if (!length(files)) {
    stop("no core R files found in '", r_dir, "' (only load_core.R present)")
  }

  for (f in files) {
    tryCatch(
      source(f, local = FALSE),
      error = function(e) {
        stop("while loading R/", basename(f), ": ", conditionMessage(e),
             call. = FALSE)
      }
    )
  }
  invisible(basename(files))
}
