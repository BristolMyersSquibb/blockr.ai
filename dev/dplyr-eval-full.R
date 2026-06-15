# Broader blockr.dplyr eval across the COMPLEX blocks (polymorphic-array params)
# whose registry `examples` carried the canonical shape. Run before/after the
# flat-args registry migration to measure the example-shape lever.
#   cd /tmp && Rscript --vanilla /workspace/blockr.ai/dev/dplyr-eval-full.R
readRenviron("/workspace/.Renviron")
.libPaths("/workspace/blockr.dev/.devcontainer/.library")
suppressMessages({
  pkgload::load_all("/workspace/blockr.dplyr", quiet = TRUE)
  pkgload::load_all("/workspace/blockr.ai", quiet = TRUE)
})
MODEL <- "gpt-5.1"
N <- 2  # runs per case (variance)
`%||%` <- function(a, b) if (is.null(a) || !nzchar(as.character(a)[1])) b else a

mtcars2 <- mtcars; mtcars2$car <- rownames(mtcars); rownames(mtcars2) <- NULL
band <- dplyr::band_members; inst <- dplyr::band_instruments

cases <- list(
  list(nm = "filter-multi", blk = function() new_filter_block(), data = mtcars2,
       ask = "Keep rows where mpg is greater than 20 AND cyl is less than 8."),
  list(nm = "filter-values", blk = function() new_filter_block(), data = iris,
       ask = "Keep only setosa and versicolor species."),
  list(nm = "arrange-multi", blk = function() new_arrange_block(), data = mtcars2,
       ask = "Sort by cyl ascending, then by mpg descending."),
  list(nm = "mutate-grouped", blk = function() new_mutate_block(), data = mtcars2,
       ask = "Add a column mean_mpg = the mean of mpg within each cyl group."),
  list(nm = "summarize-grouped", blk = function() new_summarize_block(), data = mtcars2,
       ask = "For each cyl, the average mpg and the number of rows.")
)

run_one <- function(cs) {
  blk <- tryCatch(cs$blk(), error = function(e) e)
  if (inherits(blk, "error")) return(paste("ctor-err:", conditionMessage(blk)))
  client <- ellmer::chat_openai(model = MODEL, echo = "none")
  args <- list(prompt = cs$ask, block = blk, data = cs$data, client = client)
  res <- tryCatch(do.call(discover_block_args, args),
                  error = function(e) list(success = FALSE, error = conditionMessage(e)))
  if (isTRUE(res$success)) {
    eff <- tryCatch(data_effect(cs$data, res$result),
                    error = function(e) paste("eff-err:", conditionMessage(e)))
    paste("OK:", substr(eff, 1, 110))
  } else {
    paste("FAIL/ASK:", substr(res$question %||% res$message %||% res$error %||% "(none)", 1, 130))
  }
}

cat("============ DPLYR FULL (gpt-5.1) ============\n")
for (cs in cases) {
  for (k in seq_len(N)) {
    out <- run_one(cs)
    cat(sprintf("[%-18s #%d] %s\n", cs$nm, k, out))
  }
}
cat("============ END ============\n")
