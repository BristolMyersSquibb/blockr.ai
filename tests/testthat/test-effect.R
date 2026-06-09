# Tests for data_effect() — the config-effect infrastructure.
# The data.frame method is the common case and is covered thoroughly here.

# --- data.frame method: row changes -----------------------------------------

test_that("rows removed (filter)", {
  e <- data_effect(iris, iris[iris$Species == "setosa", ])
  expect_match(e, "rows: 150 -> 50 \\(100 removed\\)")
})

test_that("no-op filter is flagged UNCHANGED", {
  e <- data_effect(iris, iris)
  expect_match(e, "UNCHANGED")
  expect_match(e, "no rows or columns changed")
})

test_that("rows added (e.g. reshape/join)", {
  inp <- data.frame(id = 1:3)
  out <- data.frame(id = c(1, 1, 2, 2, 3, 3))
  expect_match(data_effect(inp, out), "rows: 3 -> 6 \\(3 added\\)")
})

test_that("empty result (all rows removed)", {
  e <- data_effect(iris, iris[0, ])
  expect_match(e, "rows: 150 -> 0 \\(150 removed\\)")
})

# --- data.frame method: column changes --------------------------------------

test_that("column added (mutate) with rows unchanged", {
  out <- cbind(iris, ratio = iris$Sepal.Length / iris$Sepal.Width)
  e <- data_effect(iris, out)
  expect_match(e, "UNCHANGED")
  expect_match(e, "columns added: ratio")
  expect_no_match(e, "no rows or columns changed")  # a column DID change
})

test_that("columns removed (select)", {
  e <- data_effect(iris, iris[, c("Species"), drop = FALSE])
  expect_match(e, "columns removed: ")
  expect_match(e, "Sepal.Length")
})

test_that("column renamed reports both added and removed", {
  out <- iris
  names(out)[names(out) == "Species"] <- "species"
  e <- data_effect(iris, out)
  expect_match(e, "columns added: species")
  expect_match(e, "columns removed: Species")
})

test_that("rows and columns change together", {
  out <- iris[1:10, c("Species"), drop = FALSE]
  e <- data_effect(iris, out)
  expect_match(e, "140 removed")
  expect_match(e, "columns removed: ")
})

# --- data.frame method: in-place column changes -----------------------------

test_that("in-place type change is reported, not UNCHANGED", {
  out <- iris
  out$Species <- as.character(out$Species)
  e <- data_effect(iris, out)
  expect_match(e, "columns modified: Species: type factor -> character")
  expect_no_match(e, "no rows or columns changed")
})

test_that("in-place value change (mutate) is reported", {
  out <- iris
  out$Sepal.Length <- out$Sepal.Length * 2
  e <- data_effect(iris, out)
  expect_match(e, "Sepal.Length: values changed")
  expect_no_match(e, "no rows or columns changed")
})

test_that("a genuinely identical frame still reads UNCHANGED", {
  e <- data_effect(iris, iris)
  expect_match(e, "no rows or columns changed")
  expect_no_match(e, "columns modified")
})

test_that("in-place change is not inspected when row count differs", {
  # filter then mutate: the row-delta is the signal; no spurious 'values changed'
  out <- iris[iris$Species == "setosa", ]
  out$Sepal.Length <- out$Sepal.Length * 2
  e <- data_effect(iris, out)
  expect_match(e, "100 removed")
  expect_no_match(e, "columns modified")
})

# Note: composer/gt/flextable result methods live in blockr.sandbox
# (composer-ai-view.R), which owns composer; dm methods live in blockr.dm. Both
# register onto these generics at load. blockr.ai keeps only the data.frame / dm
# / default methods.

# --- input shapes -----------------------------------------------------------

test_that("NULL input (source block) describes the output", {
  expect_match(data_effect(NULL, iris), "output: 150 rows x 5 cols")
})

test_that("single data.frame inside a named input list is used", {
  e <- data_effect(list(x = iris), iris[1:30, ])
  expect_match(e, "rows: 150 -> 30 \\(120 removed\\)")
})

test_that("ambiguous multi-input list falls back to output description", {
  e <- data_effect(list(x = iris, y = mtcars), iris[1:10, ])
  expect_match(e, "output: 10 rows x 5 cols")
})

test_that("tibble result dispatches to the data.frame method", {
  skip_if_not_installed("tibble")
  out <- tibble::as_tibble(iris[1:5, ])
  expect_match(data_effect(iris, out), "rows: 150 -> 5 \\(145 removed\\)")
})

# --- default method: non-data.frame results --------------------------------

test_that("non-data.frame result yields no effect summary (graceful)", {
  expect_identical(data_effect(iris, ggplot2::ggplot(iris)), "")
  expect_identical(data_effect(iris, list(1, 2, 3)), "")
  expect_identical(data_effect(iris, 42), "")
})

test_that("empty dm result yields empty effect", {
  expect_identical(data_effect(iris, structure(list(), class = "dm")), "")
})

test_that("dm input + data.frame result describes output (no per-row diff)", {
  fake_dm <- structure(list(a = iris), class = "dm")
  expect_match(data_effect(fake_dm, iris[1:3, ]), "output: 3 rows x 5 cols")
})

# --- dm method: per-table row diff (lightweight) ----------------------------

test_that("data_effect.dm reports per-table row changes", {
  mk <- function(n) data.frame(x = seq_len(n))
  inp <- structure(list(AE = mk(1200), LB = mk(5000), DM = mk(100)), class = "dm")
  out <- structure(list(AE = mk(12), LB = mk(40), DM = mk(1)), class = "dm")
  e <- data_effect(inp, out)
  expect_match(e, "AE: 1200 -> 12")
  expect_match(e, "LB: 5000 -> 40")
  expect_match(e, "DM: 100 -> 1")
})

test_that("data_effect.dm flags UNCHANGED when no table changed", {
  mk <- function(n) data.frame(x = seq_len(n))
  d <- structure(list(AE = mk(10), LB = mk(20)), class = "dm")
  expect_match(data_effect(d, d), "2 tables, UNCHANGED")
})

test_that("data_effect.dm notes removed and new tables", {
  mk <- function(n) data.frame(x = seq_len(n))
  inp <- structure(list(AE = mk(10), LB = mk(20)), class = "dm")
  out <- structure(list(AE = mk(10), NEW = mk(5)), class = "dm")
  e <- data_effect(inp, out)
  expect_match(e, "NEW: 5 rows \\(new\\)")
  expect_match(e, "tables removed: LB")
})

# --- helper -----------------------------------------------------------------

test_that("effect_primary_df picks the right input", {
  expect_identical(effect_primary_df(iris), iris)
  expect_identical(effect_primary_df(list(x = iris)), iris)
  expect_null(effect_primary_df(list(x = iris, y = mtcars)))
  expect_null(effect_primary_df(structure(list(), class = "dm")))
  expect_null(effect_primary_df(NULL))
})
