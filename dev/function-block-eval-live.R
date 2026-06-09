# LIVE eval of the PLAIN function block (blockr.extra::new_function_block) on
# gpt-5.1 -- exercises the base function-block prompt + the typed schema, with no
# composer involved. Mix of transforms and UI-control exposure.
#   cd /tmp && Rscript --vanilla /workspace/blockr.ai/dev/function-block-eval-live.R
readRenviron("/workspace/.Renviron")
.libPaths("/workspace/blockr.dev/.devcontainer/.library")
suppressMessages({
  pkgload::load_all("/workspace/blockr.extra", quiet = TRUE)
  pkgload::load_all("/workspace/blockr.ai", quiet = TRUE)
})
MODEL <- "gpt-5.1"
`%||%` <- function(a, b) if (is.null(a) || !nzchar(as.character(a)[1])) b else a

cases <- list(
  list(ask = "Add a column z_sepal with the z-score (scaled) of Sepal.Length.",
       want = "transform"),
  list(ask = "Let the user pick which Species to include, as a multi-select that defaults to all species.",
       want = "multiselect"),
  list(ask = "Let the user choose a column to sort by (a dropdown) and how many rows to show (a number, default 10).",
       want = "dropdown+number"),
  list(ask = "Keep only rows where Sepal.Length is above a cutoff the user can set (default 5).",
       want = "numeric-filter"),
  list(ask = "Let the user select which columns to keep, as a multi-select defaulting to all columns.",
       want = "multiselect-cols")
)

cat("================= FUNCTION-BLOCK EVAL (gpt-5.1) =================\n")
for (i in seq_along(cases)) {
  cs <- cases[[i]]
  blk <- new_function_block()
  client <- ellmer::chat_openai(model = MODEL, echo = "none")
  res <- tryCatch(discover_block_args(prompt = cs$ask, block = blk, data = iris, client = client),
                  error = function(e) list(success = FALSE, error = conditionMessage(e)))
  fn <- res$args$fn %||% ""
  has_list <- grepl("=\\s*list\\(", fn)
  has_cvec <- grepl("=\\s*c\\(", fn)
  has_num  <- grepl("=\\s*[0-9]", fn)
  if (isTRUE(res$success)) {
    eff <- tryCatch(data_effect(iris, res$result), error = function(e) paste("eff-err:", conditionMessage(e)))
    cat(sprintf("\n[%d] %-16s OK   list:%-5s c():%-5s num:%-5s | %s\n",
                i, cs$want, has_list, has_cvec, has_num, substr(eff, 1, 70)))
    cat("    lines:", length(strsplit(fn, "\n")[[1]]),
        "| fn:", substr(gsub("\\s+", " ", fn), 1, 90), "\n")
  } else {
    cat(sprintf("\n[%d] %-16s ASK/FAIL: %s\n", i, cs$want,
                substr(res$question %||% res$message %||% res$error %||% "(none)", 1, 110)))
  }
}
cat("\n================= END =================\n")
