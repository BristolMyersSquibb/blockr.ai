# Tests for discover_block_args with filter_block — all options
#
# These test the LLM's ability to set all filter parameters correctly:
# include mode, exclude mode, numeric values, multiple values.

test_that("discover_block_args filter: include mode", {
  skip_on_cran()
  skip_on_ci()
  skip_if(
    !identical(Sys.getenv("BLOCKR_TEST_LLM"), "true"),
    "LLM integration tests disabled (set BLOCKR_TEST_LLM=true to enable)"
  )

  blk <- blockr.dplyr::new_filter_block()
  result <- blockr.ai::discover_block_args(
    prompt = "only setosa species",
    block = blk,
    data = iris
  )

  expect_true(result$success)
  conds <- result$args$conditions
  expect_true(length(conds) > 0)
  expect_equal(conds[[1]]$column, "Species")
  expect_true("setosa" %in% conds[[1]]$values)

  expect_equal(nrow(result$result), 50)
  expect_true(all(result$result$Species == "setosa"))
})

test_that("discover_block_args filter: exclude mode", {
  skip_on_cran()
  skip_on_ci()
  skip_if(
    !identical(Sys.getenv("BLOCKR_TEST_LLM"), "true"),
    "LLM integration tests disabled (set BLOCKR_TEST_LLM=true to enable)"
  )

  blk <- blockr.dplyr::new_filter_block()
  result <- blockr.ai::discover_block_args(
    prompt = "exclude setosa from Species (use mode: exclude)",
    block = blk,
    data = iris
  )

  expect_true(result$success)
  conds <- result$args$conditions
  expect_true(length(conds) > 0)
  expect_equal(conds[[1]]$column, "Species")
  expect_equal(conds[[1]]$mode, "exclude")
  expect_true("setosa" %in% conds[[1]]$values)

  expect_equal(nrow(result$result), 100)
  expect_false("setosa" %in% result$result$Species)
})

test_that("discover_block_args filter: numeric values", {
  skip_on_cran()
  skip_on_ci()
  skip_if(
    !identical(Sys.getenv("BLOCKR_TEST_LLM"), "true"),
    "LLM integration tests disabled (set BLOCKR_TEST_LLM=true to enable)"
  )

  blk <- blockr.dplyr::new_filter_block()
  result <- blockr.ai::discover_block_args(
    prompt = "only 4 cylinder cars",
    block = blk,
    data = mtcars
  )

  expect_true(result$success)
  conds <- result$args$conditions
  expect_true(length(conds) > 0)
  expect_equal(conds[[1]]$column, "cyl")

  expect_true(all(result$result$cyl == 4))
  expect_equal(nrow(result$result), 11)
})

test_that("discover_block_args filter: multiple values", {
  skip_on_cran()
  skip_on_ci()
  skip_if(
    !identical(Sys.getenv("BLOCKR_TEST_LLM"), "true"),
    "LLM integration tests disabled (set BLOCKR_TEST_LLM=true to enable)"
  )

  blk <- blockr.dplyr::new_filter_block()
  result <- blockr.ai::discover_block_args(
    prompt = "setosa and versicolor species",
    block = blk,
    data = iris
  )

  expect_true(result$success)
  conds <- result$args$conditions
  expect_true(length(conds) > 0)
  expect_equal(conds[[1]]$column, "Species")
  expect_true("setosa" %in% conds[[1]]$values)
  expect_true("versicolor" %in% conds[[1]]$values)

  expect_equal(nrow(result$result), 100)
  expect_true(all(result$result$Species %in% c("setosa", "versicolor")))
})

test_that("discover_block_args filter: OR operator across columns", {
  skip_on_cran()
  skip_on_ci()
  skip_if(
    !identical(Sys.getenv("BLOCKR_TEST_LLM"), "true"),
    "LLM integration tests disabled (set BLOCKR_TEST_LLM=true to enable)"
  )

  blk <- blockr.dplyr::new_filter_block()
  result <- blockr.ai::discover_block_args(
    prompt = "cyl is 4 or hp is 110",
    block = blk,
    data = mtcars
  )

  expect_true(result$success)
  conds <- result$args$conditions
  expect_true(length(conds) >= 2)

  # At least one condition should use the OR operator
  operators <- vapply(conds, function(c) c$operator %||% "&", character(1))
  expect_true("|" %in% operators)

  # All result rows should match: cyl == 4 OR hp == 110
  expect_true(all(result$result$cyl == 4 | result$result$hp == 110))
})
