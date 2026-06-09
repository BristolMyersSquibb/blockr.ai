# LIVE eval of the topline flextable block (blockr.topline) on gpt-5.1. Class B
# (small structured formatting config). Result = a flextable (always populated,
# no placeholders). Score res$args (formatting config correctness) + check the
# "can't filter, explain the limitation" behavior. Data = a topline-shaped table.
#   cd /tmp && Rscript --vanilla /workspace/blockr.ai/dev/topline-eval-live.R
readRenviron("/workspace/.Renviron")
.libPaths("/workspace/blockr.dev/.devcontainer/.library")
suppressMessages({
  pkgload::load_all("/workspace/blockr.ai", quiet = TRUE)
  pkgload::load_all("/workspace/blockr.topline", quiet = TRUE)
})
MODEL <- "gpt-5.1"
`%||%` <- function(a, b) if (is.null(a) || (length(a) == 1 && !nzchar(as.character(a)))) b else a

tl <- data.frame(
  label = c("Age, mean (SD)", "Sex, n (%)", "  Male", "  Female"),
  ".indent" = c(0, 0, 1, 1),
  "PBO N = 334" = c("65.2 (8.1)", "", "180 (54%)", "154 (46%)"),
  "DEUC 6 mg N = 336" = c("64.8 (7.9)", "", "175 (52%)", "161 (48%)"),
  check.names = FALSE, stringsAsFactors = FALSE
)
cat("topline columns:", paste(names(tl), collapse = " | "), "\n\n")

cases <- list(
  list(ask = "Show only the label and the two treatment-arm columns, and label the first column 'Characteristics'.",
       chk = function(a) "Characteristics" %in% (a$first_column_label %||% "") &&
                         all(c("PBO N = 334", "DEUC 6 mg N = 336") %in% unlist(a$selected_columns))),
  list(ask = "Set the font size to 12 and colour the columns gray, blue and orange.",
       chk = function(a) identical(as.integer(a$font_size %||% 0), 12L) &&
                         all(c("blue", "orange") %in% unlist(a$col_colors))),
  list(ask = "Filter to only the male subjects.",  # block CANNOT filter -> should decline
       chk = function(a) length(a) == 0)            # good = applied no config (declined)
)

cat("================= TOPLINE FLEXTABLE EVAL (gpt-5.1) =================\n")
for (i in seq_along(cases)) {
  cs <- cases[[i]]
  blk <- new_flextable_block()
  client <- ellmer::chat_openai(model = MODEL, echo = "none")
  res <- tryCatch(discover_block_args(prompt = cs$ask, block = blk, data = tl, client = client),
                  error = function(e) list(success = FALSE, error = conditionMessage(e)))
  a <- res$args %||% list()
  ok <- tryCatch(cs$chk(a), error = function(e) FALSE)
  cat(sprintf("\n[%d] %-6s %s\n", i, if (ok) "GOOD" else "MISS", substr(cs$ask, 1, 52)))
  cat("    args:", substr(gsub("\\s+", " ", paste(utils::capture.output(str(a)), collapse = " ")), 1, 150), "\n")
  if (i == 3 && length(a) == 0) cat("    (declined) reply:", substr(res$question %||% res$message %||% "", 1, 90), "\n")
}
cat("\n================= END =================\n")
