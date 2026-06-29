# collect_block_errors must read the REACTIVE `cond` (a data frame of conditions
# with phase/severity/message), and the validator must surface real block errors
# instead of a content-free "returned NULL".

test_that("collect_block_errors reads the data-frame condition shape", {
  cond <- data.frame(
    phase = c("eval", "eval", "data"),
    severity = c("error", "warning", "fatal"),
    message = c("could not find function \"frobnicate\"", "a warning", "bad input"),
    stringsAsFactors = FALSE
  )
  errs <- collect_block_errors(cond)
  expect_setequal(errs, c("could not find function \"frobnicate\"", "bad input"))
})

test_that("collect_block_errors calls a reactive and tolerates empty/NULL", {
  reactive_like <- function() data.frame(
    phase = "eval", severity = "error", message = "undefined columns selected",
    stringsAsFactors = FALSE
  )
  expect_equal(collect_block_errors(reactive_like), "undefined columns selected")

  expect_equal(collect_block_errors(NULL), character())
  expect_equal(
    collect_block_errors(data.frame(phase = character(), severity = character(),
                                    message = character())),
    character()
  )
})

test_that("collect_block_errors still handles the legacy stage/$error shape", {
  legacy <- list(eval = list(error = list("legacy boom")))
  expect_equal(collect_block_errors(legacy), "legacy boom")
})

test_that("validator surfaces real block errors and an actionable NULL message", {
  skip_if_not_installed("blockr.extra")
  blk <- blockr.extra::new_function_block(fn = function(data) data)
  v <- standalone_validator_internal(attr(blk, "ctor"), mtcars)

  expect_error(v(list(fn = "function(data) frobnicate(data)")),
               "could not find function")
  expect_error(v(list(fn = "function(data) data[, \"NOPE\"]")),
               "undefined columns selected")
  expect_error(v(list(fn = "function(data) NULL")),
               "produced no result")

  # a valid function still returns its result
  expect_s3_class(v(list(fn = "function(data) head(data)")), "data.frame")
})
