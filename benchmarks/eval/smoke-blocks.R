#!/usr/bin/env Rscript
# Cross-block-type smoke test for the (ellmer) discovery harness.
#
# discover_block_args() is now ellmer-only, so this checks it works across block
# SHAPES that differ from the code/function blocks the benchmark focuses on:
#   - the state-wrapper filter (the tricky "{state:{...}}" config),
#   - column / aggregation transforms (select, summarize, mutate),
#   - a non-data.frame result (ggplot),
#   - conversation memory (client reuse across two turns),
#   - a dm input/output.
# Run this before trusting ellmer as the only harness on a new block set.
#
#   Rscript benchmarks/eval/smoke-blocks.R
#
# Needs a model key (OpenAI by default) and the block packages installed.
# Model via BLOCKR_SMOKE_MODEL (default gpt-5.1). Exits non-zero on any failure;
# skips cleanly (status 0) when no key is available.

`%||%` <- function(x, y) if (is.null(x)) y else x

for (f in c(".Renviron", "/workspace/.Renviron")) {
  if (file.exists(f) && !nzchar(Sys.getenv("OPENAI_API_KEY"))) readRenviron(f)
}
if (!nzchar(Sys.getenv("OPENAI_API_KEY"))) {
  message("SKIP: no OPENAI_API_KEY (live test) -- set it to run.")
  quit(status = 0)
}

suppressMessages(suppressWarnings({
  pkgload::load_all(".", quiet = TRUE)
  for (p in c("blockr.dplyr", "blockr.extra", "blockr.ggplot", "blockr.dm")) {
    if (requireNamespace(p, quietly = TRUE)) library(p, character.only = TRUE)
  }
}))
options(blockr.ai_model = Sys.getenv("BLOCKR_SMOKE_MODEL", "gpt-5.1"))
lg <- function(...) cat(format(Sys.time(), "%H:%M:%S"), ..., "\n")

mk <- function(pkg, fn) {
  if (requireNamespace(pkg, quietly = TRUE)) getExportedValue(pkg, fn)() else NULL
}

run <- function(label, block, data, prompt, check) {
  if (is.null(block)) {
    lg(sprintf("%-22s SKIP (block package not installed)", label))
    return(data.frame(label, success = NA, check = NA, secs = NA))
  }
  t0 <- Sys.time()
  res <- tryCatch(
    blockr.ai::discover_block_args(prompt = prompt, block = block, data = data),
    error = function(e) list(success = FALSE, error = conditionMessage(e))
  )
  secs <- round(as.numeric(difftime(Sys.time(), t0, units = "secs")), 1)
  ok <- isTRUE(res$success)
  chk <- if (ok) tryCatch(isTRUE(check(res$result)), error = function(e) NA) else NA
  lg(sprintf("%-22s success=%-5s check=%-5s %5ss %s", label, ok, chk, secs,
             if (!ok) paste0("ERR: ", substr(res$error %||% "", 1, 70)) else ""))
  data.frame(label, success = ok, check = chk, secs)
}

rows <- list(
  run("filter (state-wrapper)", mk("blockr.dplyr", "new_filter_block"), iris,
      "keep only the setosa species",
      function(r) is.data.frame(r) && all(r$Species == "setosa") && nrow(r) == 50),
  run("select", mk("blockr.dplyr", "new_select_block"), mtcars,
      "keep only the columns mpg, cyl and hp",
      function(r) is.data.frame(r) && setequal(names(r), c("mpg", "cyl", "hp"))),
  run("summarize", mk("blockr.dplyr", "new_summarize_block"), mtcars,
      "average mpg grouped by cyl",
      function(r) is.data.frame(r) && nrow(r) == 3),
  run("mutate", mk("blockr.dplyr", "new_mutate_block"), mtcars,
      "add a column kpl equal to mpg times 0.425",
      function(r) is.data.frame(r) && "kpl" %in% names(r) && nrow(r) == 32),
  run("ggplot (non-df result)", mk("blockr.ggplot", "new_ggplot_block"), iris,
      "scatter plot of Sepal.Length on x and Sepal.Width on y",
      function(r) inherits(r, "ggplot"))
)

# conversation memory across two turns (client reuse)
mem_ok <- NA
if (requireNamespace("blockr.dplyr", quietly = TRUE)) {
  lg("conversation memory: turn 1 ...")
  m1 <- tryCatch(
    blockr.ai::discover_block_args("keep only 6-cylinder cars",
                                   blockr.dplyr::new_filter_block(), mtcars),
    error = function(e) list(success = FALSE)
  )
  if (isTRUE(m1$success) && !is.null(m1$client)) {
    lg("conversation memory: turn 2 (reuse client) ...")
    m2 <- tryCatch(
      blockr.ai::discover_block_args("now also only those with mpg above 20",
        blockr.dplyr::new_filter_block(), mtcars, client = m1$client),
      error = function(e) list(success = FALSE)
    )
    mem_ok <- isTRUE(m2$success) && is.data.frame(m2$result) &&
      all(m2$result$cyl == 6) && all(m2$result$mpg > 20)
  } else {
    mem_ok <- FALSE
  }
  lg(sprintf("%-22s success=%-5s", "conversation memory", mem_ok))
}
rows[[length(rows) + 1]] <-
  data.frame(label = "conversation memory", success = mem_ok, check = mem_ok, secs = NA)

# dm input/output (best effort)
rows[[length(rows) + 1]] <- tryCatch({
  d <- dm::dm(cars = utils::head(mtcars, 10), plants = utils::head(iris, 10))
  run("dm (select tables)", mk("blockr.dm", "new_dm_select_block"), d,
      "keep only the cars table", function(r) inherits(r, "dm"))
}, error = function(e) {
  lg("dm: setup failed -", conditionMessage(e))
  data.frame(label = "dm (select tables)", success = NA, check = NA, secs = NA)
})

res <- do.call(rbind, rows)
cat("\n=== CROSS-BLOCK SMOKE SUMMARY ===\n")
print(res, row.names = FALSE)
fails <- res[!is.na(res$success) & (!res$success | (!is.na(res$check) & !res$check)), ]
if (nrow(fails)) {
  cat("\nFAILURES:\n"); print(fails, row.names = FALSE)
  quit(status = 1)
}
cat("\nALL PASS\n")
