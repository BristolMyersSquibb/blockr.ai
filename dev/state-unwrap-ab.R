# A/B: does state-unwrap (flat conditions/operator) configure better/faster than
# the nested {state:{...}} schema? Run this file with unwrap ON (current code),
# then revert R/param-schema.R + R/harness-ellmer.R to e13fe5a^ and run again.
#   cd /tmp && Rscript --vanilla /workspace/blockr.ai/dev/state-unwrap-ab.R
readRenviron("/workspace/.Renviron")
.libPaths("/workspace/blockr.dev/.devcontainer/.library")
suppressMessages({
  pkgload::load_all("/workspace/blockr.dplyr", quiet = TRUE)
  pkgload::load_all("/workspace/blockr.ai", quiet = TRUE)
})
MODEL <- "gpt-5.1"
`%||%` <- function(a, b) if (is.null(a) || (length(a) == 1 && !nzchar(as.character(a)[1]))) b else a

# Report whether unwrap is active (so each run is labelled).
mode <- if (!is.null(attr(blockr.ai:::block_param_types(new_filter_block()), "wrap_key"))) "UNWRAP" else "NESTED"

cases <- list(
  list(blk = function() new_filter_block(),    ask = "Keep only rows where Species is setosa.",                          chk = function(e) grepl("-> 50", e)),
  list(blk = function() new_filter_block(),    ask = "Keep rows where Species is setosa AND Sepal.Length is above 5.",  chk = function(e) grepl("removed", e)),
  list(blk = function() new_select_block(),    ask = "Keep only Sepal.Length and Species.",                             chk = function(e) grepl("removed", e)),
  list(blk = function() new_arrange_block(),   ask = "Sort by Sepal.Length descending.",                                chk = function(e) grepl("modified|UNCHANGED", e))
)

cat(sprintf("================= STATE A/B [%s] (gpt-5.1) =================\n", mode))
tot <- 0; ok_n <- 0
for (i in seq_along(cases)) {
  cs <- cases[[i]]
  blk <- tryCatch(cs$blk(), error = function(e) e)
  client <- ellmer::chat_openai(model = MODEL, echo = "none")
  t0 <- proc.time()[["elapsed"]]
  res <- tryCatch(discover_block_args(prompt = cs$ask, block = blk, data = iris, client = client),
                  error = function(e) list(success = FALSE, error = conditionMessage(e)))
  dt <- round(proc.time()[["elapsed"]] - t0, 1); tot <- tot + dt
  eff <- tryCatch(data_effect(iris, res$result), error = function(e) "")
  ok <- isTRUE(res$success) && tryCatch(cs$chk(eff), error = function(e) FALSE)
  ok_n <- ok_n + ok
  cat(sprintf("[%d] %-14s %-4s %5.1fs  %s\n", i, class(blk)[1], if (ok) "OK" else "MISS", dt, substr(eff, 1, 55)))
}
cat(sprintf("---- %s: %d/%d ok, total %.1fs ----\n", mode, ok_n, length(cases), tot))
