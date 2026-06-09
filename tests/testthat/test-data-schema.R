# Tests for data_schema() methods and the column-summary describer.

# --- format_column_summaries graft ------------------------------------------

test_that("low-cardinality categorical lists all values", {
  df <- data.frame(g = c("a", "a", "b", "c"), stringsAsFactors = FALSE)
  s <- format_column_summaries(df)
  expect_match(s, "g: 3 unique: a, b, c")
})

test_that("high-cardinality categorical shows top counts, not a dump", {
  df <- data.frame(g = rep(paste0("lvl", 1:20), times = 20:1),
                   stringsAsFactors = FALSE)
  s <- format_column_summaries(df)
  expect_match(s, "g: 20 unique, top: lvl1 \\(20\\)")
  expect_no_match(s, "lvl20")  # capped — not every level enumerated
})

test_that("high-cardinality numeric shows a distribution summary", {
  df <- data.frame(x = 1:100)
  s <- format_column_summaries(df)
  expect_match(s, "x: 100 unique, min/p25/median/p75/max = 1/25.75/50.5/75.25/100")
  expect_match(s, "mean 50.5")
})

test_that("NA counts are noted", {
  df <- data.frame(x = c(1, 2, NA, NA))
  expect_match(format_column_summaries(df), "\\(2 NA\\)")
})

# Note: data_schema.dm lives in blockr.dm (data-schema.R) and the composer
# gt/flextable methods in blockr.sandbox (composer-ai-view.R) -- the packages
# that own those types register them onto blockr.ai's generic. blockr.ai itself
# carries only the data.frame / default / ggplot methods, tested above.
