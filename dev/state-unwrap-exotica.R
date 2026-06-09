# Broad/exotic live test of state-unwrap: complex dplyr blocks + deep configs.
# Confirms the model produces the right FLAT structure (no `state` wrapper) and it
# re-wraps + applies. gpt-5.1.
#   cd /tmp && Rscript --vanilla /workspace/blockr.ai/dev/state-unwrap-exotica.R
readRenviron("/workspace/.Renviron")
.libPaths("/workspace/blockr.dev/.devcontainer/.library")
suppressMessages({
  pkgload::load_all("/workspace/blockr.dplyr", quiet = TRUE)
  pkgload::load_all("/workspace/blockr.ai", quiet = TRUE)
})
MODEL <- "gpt-5.1"
`%||%` <- function(a, b) if (is.null(a) || (length(a) == 1 && !nzchar(as.character(a)[1]))) b else a

iris2 <- iris
codes <- data.frame(id = 1:6, code = c("A-001","A-002","B-010","B-011","C-100","C-101"),
                    val = c(10,20,30,40,50,60), stringsAsFactors = FALSE)

cases <- list(
  list(nm="filter-poly", blk=function() new_filter_block(), d=iris2,
       ask="Keep rows where Species is setosa or versicolor AND Sepal.Length is between 5 and 6.",
       chk=function(e) grepl("removed", e)),
  list(nm="filter-expr", blk=function() new_filter_block(), d=iris2,
       ask="Keep rows where Sepal.Length is greater than Petal.Length.",
       chk=function(e) grepl("removed", e)),
  list(nm="summarize", blk=function() new_summarize_block(), d=iris2,
       ask="Mean and standard deviation of Sepal.Length and Sepal.Width, grouped by Species.",
       chk=function(e) grepl("-> 3|3 rows", e)),
  list(nm="mutate", blk=function() new_mutate_block(), d=iris2,
       ask="Add ratio = Sepal.Length / Sepal.Width and log_sl = log(Sepal.Length).",
       chk=function(e) grepl("ratio", e) && grepl("log_sl", e)),
  list(nm="slice", blk=function() new_slice_block(), d=iris2,
       ask="Keep the 10 rows with the largest Sepal.Length.",
       chk=function(e) grepl("-> 10", e)),
  list(nm="rename", blk=function() new_rename_block(), d=iris2,
       ask="Rename Sepal.Length to SL and Species to species.",
       chk=function(e) grepl("SL", e) && grepl("species", e)),
  list(nm="separate", blk=function() new_separate_block(), d=codes,
       ask="Split the code column into letter and number on the dash.",
       chk=function(e) grepl("letter|number|columns added", e)),
  list(nm="pivot_longer", blk=function() new_pivot_longer_block(), d=iris2,
       ask="Pivot the four numeric measurement columns into name/value long format, keeping Species.",
       chk=function(e) grepl("added|-> 600|600 rows|name", e))
)

cat("================= STATE-UNWRAP EXOTICA (gpt-5.1) =================\n")
ok_n <- 0
for (i in seq_along(cases)) {
  cs <- cases[[i]]
  blk <- tryCatch(cs$blk(), error=function(e) e)
  if (inherits(blk,"error")) { cat(sprintf("[%s] CTOR-ERR %s\n", cs$nm, conditionMessage(blk))); next }
  client <- ellmer::chat_openai(model = MODEL, echo = "none")
  res <- tryCatch(discover_block_args(prompt=cs$ask, block=blk, data=cs$d, client=client),
                  error=function(e) list(success=FALSE, error=conditionMessage(e)))
  eff <- tryCatch(data_effect(cs$d, res$result), error=function(e) paste("eff-err:",conditionMessage(e)))
  ok <- isTRUE(res$success) && tryCatch(cs$chk(eff), error=function(e) FALSE)
  ok_n <- ok_n + ok
  # flat structure check: the AI's args must NOT contain a `state` key
  flat <- !"state" %in% names(res$args %||% list())
  cat(sprintf("\n[%s] %-4s flat-args:%s\n   effect: %s\n", cs$nm, if(ok)"OK" else "MISS", flat, substr(eff,1,90)))
}
cat(sprintf("\n---- %d/%d ok ----\n", ok_n, length(cases)))
