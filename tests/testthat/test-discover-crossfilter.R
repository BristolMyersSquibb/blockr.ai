# Tests for discover_block_args with crossfilter_block
#
# These test the LLM's ability to set crossfilter parameters correctly:
# categorical filters and numeric range filters.

test_that("discover_block_args crossfilter: categorical filter", {
  skip_on_cran()
  skip_on_ci()
  skip_if(
    !identical(Sys.getenv("BLOCKR_TEST_LLM"), "true"),
    "LLM integration tests disabled (set BLOCKR_TEST_LLM=true to enable)"
  )

  blk <- blockr.dm::new_crossfilter_block()
  result <- blockr.ai::discover_block_args(
    prompt = "only setosa species",
    block = blk,
    data = iris
  )

  expect_true(result$success)
  expect_true("Species" %in% names(result$args$filters))
  expect_true("setosa" %in% result$args$filters$Species)

  expect_equal(nrow(result$result), 50)
  expect_true(all(result$result$Species == "setosa"))
})

test_that("discover_block_args crossfilter: numeric range", {
  skip_on_cran()
  skip_on_ci()
  skip_if(
    !identical(Sys.getenv("BLOCKR_TEST_LLM"), "true"),
    "LLM integration tests disabled (set BLOCKR_TEST_LLM=true to enable)"
  )

  blk <- blockr.dm::new_crossfilter_block()
  result <- blockr.ai::discover_block_args(
    prompt = "sepal length between 5 and 6",
    block = blk,
    data = iris
  )

  expect_true(result$success)
  expect_true("Sepal.Length" %in% names(result$args$range_filters))
  expect_equal(result$args$range_filters$Sepal.Length, c(5, 6))

  expect_true(all(result$result$Sepal.Length >= 5))
  expect_true(all(result$result$Sepal.Length <= 6))
})
