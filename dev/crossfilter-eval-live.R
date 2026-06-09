# LIVE eval of the crossfilter block (blockr.dm) on gpt-5.1. Unlike drilldown,
# its OUTPUT is the filtered data, so data_effect works directly. Challenge: the
# AI must produce the nested per-table filter structure (single data.frame => the
# ".tbl" table key). Scored on data_effect (did the filter take).
#   cd /tmp && Rscript --vanilla /workspace/blockr.ai/dev/crossfilter-eval-live.R
readRenviron("/workspace/.Renviron")
.libPaths("/workspace/blockr.dev/.devcontainer/.library")
suppressMessages({
  pkgload::load_all("/workspace/blockr.ai", quiet = TRUE)
  pkgload::load_all("/workspace/blockr.dm", quiet = TRUE)
})
MODEL <- "gpt-5.1"
`%||%` <- function(a, b) if (is.null(a) || (length(a) == 1 && !nzchar(as.character(a)))) b else a

cases <- list(
  list(ask = "Keep only the setosa species.",                        check = function(e) grepl("-> 50", e)),
  list(ask = "Filter to versicolor and virginica only.",             check = function(e) grepl("-> 100", e)),
  list(ask = "Show only flowers with Sepal.Length above 6.",         check = function(e) grepl("removed", e))
)

cat("================= CROSSFILTER EVAL (gpt-5.1) =================\n")
for (i in seq_along(cases)) {
  cs <- cases[[i]]
  blk <- new_crossfilter_block()
  client <- ellmer::chat_openai(model = MODEL, echo = "none")
  res <- tryCatch(discover_block_args(prompt = cs$ask, block = blk, data = iris, client = client),
                  error = function(e) list(success = FALSE, error = conditionMessage(e)))
  eff <- tryCatch(data_effect(iris, res$result), error = function(e) paste("eff-err:", conditionMessage(e)))
  ok <- isTRUE(res$success) && tryCatch(cs$check(eff), error = function(e) FALSE)
  cat(sprintf("\n[%d] %-8s %s\n    effect: %s\n", i, if (ok) "GOOD" else "MISS",
              substr(cs$ask, 1, 45), substr(eff %||% "(none)", 1, 80)))
  cat("    filters arg:", substr(gsub("\\s+", " ", paste(utils::capture.output(str(res$args$filters)), collapse = " ")), 1, 120), "\n")
}
cat("\n================= END =================\n")
