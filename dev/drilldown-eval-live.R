# LIVE eval of the drilldown CHART block (blockr.bi) on gpt-5.1. Class D
# observability: result is a passthrough filter, so the artifact is the CHART
# CONFIG. We score res$args (chart_type + column bindings) and print the new
# config_effect feedback the model now receives.
#   cd /tmp && Rscript --vanilla /workspace/blockr.ai/dev/drilldown-eval-live.R
readRenviron("/workspace/.Renviron")
.libPaths("/workspace/blockr.dev/.devcontainer/.library")
suppressMessages({
  pkgload::load_all("/workspace/blockr.ai", quiet = TRUE)   # ai first so bi's .onLoad can register config_effect
  pkgload::load_all("/workspace/blockr.bi", quiet = TRUE)
})
blockr.bi:::register_drilldown_ai_effect()
MODEL <- "gpt-5.1"
`%||%` <- function(a, b) if (is.null(a) || (length(a) == 1 && !nzchar(as.character(a)))) b else a

sales <- tryCatch(bi_demo_data(), error = function(e) NULL)
if (is.null(sales)) {
  set.seed(1)
  sales <- data.frame(
    Region = sample(c("North", "South", "East", "West"), 400, TRUE),
    Country = sample(c("DE", "FR", "IT", "ES"), 400, TRUE),
    Category = sample(c("Tech", "Furniture", "Office"), 400, TRUE),
    Channel = sample(c("Online", "Retail"), 400, TRUE),
    Year = sample(2019:2023, 400, TRUE),
    Revenue = round(runif(400, 100, 9000), 1),
    Quantity = sample(1:50, 400, TRUE)
  )
}
cat("data columns:", paste(names(sales), collapse = ", "), "\n\n")

cases <- list(
  list(ask = "Bar chart of total revenue by region, clickable to filter by region.", type = "bar",     col = "Region"),
  list(ask = "Scatter plot of revenue versus quantity, coloured by category.",        type = "scatter", col = "Revenue"),
  list(ask = "Show the number of records per channel as a bar chart.",                type = "bar",     col = "Channel"),
  list(ask = "Pie chart of revenue share by category.",                               type = "pie",     col = "Category"),
  list(ask = "Line chart of average revenue over the years.",                         type = "line",    col = "Year")
)

cat("================= DRILLDOWN CHART EVAL (gpt-5.1) =================\n")
for (i in seq_along(cases)) {
  cs <- cases[[i]]
  blk <- new_drilldown_chart_block()
  client <- ellmer::chat_openai(model = MODEL, echo = "none")
  res <- tryCatch(discover_block_args(prompt = cs$ask, block = blk, data = sales, client = client),
                  error = function(e) list(success = FALSE, error = conditionMessage(e)))
  a <- res$args %||% list()
  bound <- unlist(a[c("group", "x", "y", "metric", "color", "drill")])
  type_ok <- identical(as.character(a$chart_type %||% ""), cs$type)
  col_ok <- cs$col %in% bound
  eff <- tryCatch(config_effect(blk, a, sales), error = function(e) paste("err:", conditionMessage(e)))
  verdict <- if (length(a) == 0) "NO-CONFIG" else if (type_ok && col_ok) "GOOD" else "PARTIAL"
  cat(sprintf("\n[%d] %-10s want %s/%s | got type=%s type_ok=%s col_ok=%s\n",
              i, verdict, cs$type, cs$col, a$chart_type %||% "-", type_ok, col_ok))
  cat("    effect: ", substr(eff %||% "(none)", 1, 120), "\n", sep = "")
}
cat("\n================= END =================\n")
