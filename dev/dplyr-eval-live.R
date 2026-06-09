# BASELINE: do blockr.dplyr (state-list) blocks work on the CURRENT JSON-string
# config design? Tests the state-wrapper confusion (flat {conditions} vs nested
# {state:{conditions}}). Run before Phase 2 to get a regression baseline.
#   cd /tmp && Rscript --vanilla /workspace/blockr.ai/dev/dplyr-eval-live.R
readRenviron("/workspace/.Renviron")
.libPaths("/workspace/blockr.dev/.devcontainer/.library")
suppressMessages({
  pkgload::load_all("/workspace/blockr.dplyr", quiet = TRUE)
  pkgload::load_all("/workspace/blockr.ai", quiet = TRUE)
})
MODEL <- "gpt-5.1"
`%||%` <- function(a, b) if (is.null(a) || !nzchar(as.character(a)[1])) b else a

cases <- list(
  list(blk = function() new_filter_block(),    ask = "Keep only rows where Species is setosa."),
  list(blk = function() new_select_block(),     ask = "Keep only the columns Sepal.Length and Species."),
  list(blk = function() new_arrange_block(),    ask = "Sort the rows by Sepal.Length descending.")
)

cat("================= DPLYR BASELINE (gpt-5.1, current design) =================\n")
for (i in seq_along(cases)) {
  cs <- cases[[i]]
  blk <- tryCatch(cs$blk(), error = function(e) e)
  if (inherits(blk, "error")) { cat(sprintf("[%d] ctor-err: %s\n", i, conditionMessage(blk))); next }
  client <- ellmer::chat_openai(model = MODEL, echo = "none")
  res <- tryCatch(discover_block_args(prompt = cs$ask, block = blk, data = iris, client = client),
                  error = function(e) list(success = FALSE, error = conditionMessage(e)))
  if (isTRUE(res$success)) {
    eff <- tryCatch(data_effect(iris, res$result), error = function(e) paste("eff-err:", conditionMessage(e)))
    cat(sprintf("\n[%d] %-22s OK  effect: %s\n", i, class(blk)[1], substr(eff, 1, 90)))
  } else {
    cat(sprintf("\n[%d] %-22s FAIL/ASK: %s\n", i, class(blk)[1],
                substr(res$question %||% res$message %||% res$error %||% "(none)", 1, 150)))
  }
}
cat("\n================= END =================\n")
