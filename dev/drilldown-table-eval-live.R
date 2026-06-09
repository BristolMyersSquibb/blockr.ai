# LIVE eval of the drilldown TABLE block (blockr.bi) on gpt-5.1 -- the "badly
# tested" sibling of the drilldown chart. Class D observability: result is a
# passthrough filter (row click filters downstream), so the artifact is the
# CONFIG (label_col / value_cols / drill / transform). We score res$args and show
# the config_effect feedback.
#   cd /tmp && Rscript --vanilla /workspace/blockr.ai/dev/drilldown-table-eval-live.R
readRenviron("/workspace/.Renviron")
.libPaths("/workspace/blockr.dev/.devcontainer/.library")
suppressMessages({
  pkgload::load_all("/workspace/blockr.ai", quiet = TRUE)   # ai first so bi's .onLoad registers config_effect
  pkgload::load_all("/workspace/blockr.bi", quiet = TRUE)
})
blockr.bi:::register_drilldown_ai_effect()
MODEL <- "gpt-5.1"
`%||%` <- function(a, b) if (is.null(a) || (length(a) == 1 && !nzchar(as.character(a)))) b else a

sales <- tryCatch(bi_demo_data(), error = function(e) NULL)
if (is.null(sales)) {
  set.seed(1)
  sales <- data.frame(
    Region = sample(c("North", "South", "East", "West"), 200, TRUE),
    Category = sample(c("Tech", "Furniture", "Office"), 200, TRUE),
    Revenue = round(runif(200, 100, 9000), 1),
    Profit = round(runif(200, -500, 3000), 1),
    Quantity = sample(1:50, 200, TRUE)
  )
}
cat("columns:", paste(names(sales), collapse = ", "), "\n\n")

cases <- list(
  list(ask = "Table with Region as the row label and Revenue and Profit as the value columns; clicking a row should drill on Region.",
       chk = function(a) identical(as.character(a$rowname %||% ""), "Region") &&
                         all(c("Revenue", "Profit") %in% unlist(a$values)) &&
                         identical(as.character(a$drill %||% ""), "Region")),
  list(ask = "Show a correlation table of the numeric columns.",
       chk = function(a) grepl("cor", tolower(as.character(a$transform %||% "")))),
  list(ask = "Table with Category as the rows and Quantity as the value, show 0 decimal places.",
       chk = function(a) identical(as.character(a$rowname %||% ""), "Category") &&
                         "Quantity" %in% unlist(a$values) &&
                         identical(as.integer(a$digits %||% -1), 0L))
)

cat("================= DRILLDOWN TABLE EVAL (gpt-5.1) =================\n")
for (i in seq_along(cases)) {
  cs <- cases[[i]]
  blk <- new_drilldown_table_block()
  client <- ellmer::chat_openai(model = MODEL, echo = "none")
  res <- tryCatch(discover_block_args(prompt = cs$ask, block = blk, data = sales, client = client),
                  error = function(e) list(success = FALSE, error = conditionMessage(e)))
  a <- res$args %||% list()
  ok <- tryCatch(cs$chk(a), error = function(e) FALSE)
  eff <- tryCatch(config_effect(blk, a, sales), error = function(e) NULL)
  cat(sprintf("\n[%d] %-6s  values=[%s] rowname=%s drill=%s\n", i, if (ok) "GOOD" else "MISS",
              paste(unlist(a$values) %||% "-", collapse = ","), a$rowname %||% "-", a$drill %||% "-"))
  cat("    args:", substr(gsub("\\s+", " ", paste(utils::capture.output(str(a)), collapse = " ")), 1, 140), "\n")
  cat("    effect:", substr(eff %||% "(none)", 1, 110), "\n")
}
cat("\n================= END =================\n")
