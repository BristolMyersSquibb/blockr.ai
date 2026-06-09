# Focused test of the topline flextable block's column-SELECTION capability
# (selected_columns + column_mode include/exclude) vs row-FILTER (can't do).
#   cd /tmp && Rscript --vanilla /workspace/blockr.ai/dev/topline-select-eval.R
readRenviron("/workspace/.Renviron")
.libPaths("/workspace/blockr.dev/.devcontainer/.library")
suppressMessages({
  pkgload::load_all("/workspace/blockr.ai", quiet = TRUE)
  pkgload::load_all("/workspace/blockr.topline", quiet = TRUE)
})
MODEL <- "gpt-5.1"
`%||%` <- function(a, b) if (is.null(a) || (length(a) == 1 && !nzchar(as.character(a)))) b else a

tl <- data.frame(
  label = c("Age, mean (SD)", "  Male", "  Female"),
  ".indent" = c(0, 1, 1),
  "PBO N = 334" = c("65.2 (8.1)", "180 (54%)", "154 (46%)"),
  "DEUC 6 mg N = 336" = c("64.8 (7.9)", "175 (52%)", "161 (48%)"),
  "Total N = 670" = c("65.0 (8.0)", "355 (53%)", "315 (47%)"),
  check.names = FALSE, stringsAsFactors = FALSE
)
cat("columns:", paste(names(tl), collapse = " | "), "\n\n")

cases <- list(
  list(ask = "Show only the label column and the DEUC arm.",                want = "select-include"),
  list(ask = "Hide the placebo column; keep the others.",                   want = "select-exclude"),
  list(ask = "Show every arm except Total.",                                want = "select-exclude2"),
  list(ask = "Keep only the rows for male subjects.",                       want = "row-filter (cannot)")
)

cat("================= TOPLINE SELECT EVAL (gpt-5.1) =================\n")
for (i in seq_along(cases)) {
  cs <- cases[[i]]
  blk <- new_flextable_block()
  client <- ellmer::chat_openai(model = MODEL, echo = "none")
  res <- tryCatch(discover_block_args(prompt = cs$ask, block = blk, data = tl, client = client),
                  error = function(e) list(success = FALSE, error = conditionMessage(e)))
  a <- res$args %||% list()
  cat(sprintf("\n[%d] %-22s applied:%s\n", i, cs$want, length(a) > 0))
  cat("    mode:", a$column_mode %||% "-", "| selected_columns:",
      paste(unlist(a$selected_columns) %||% "-", collapse = " ; "), "\n")
  if (!length(a)) cat("    -> declined; reply:", substr(res$question %||% res$message %||% "", 1, 90), "\n")
}
cat("\n================= END =================\n")
