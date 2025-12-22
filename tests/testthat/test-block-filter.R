# Tests for filter block with AI assistance

test_that("filter block constructor works", {
  # Test basic constructor
  blk <- new_filter_block()
  expect_s3_class(blk, c("filter_block", "transform_block", "block"))

  # Test constructor with initial conditions
  conditions <- list(
    list(
      column = "Species",
      values = c("setosa", "versicolor"),
      mode = "include"
    )
  )
  blk <- new_filter_block(conditions = conditions)
  expect_s3_class(blk, c("filter_block", "transform_block", "block"))

  # Test constructor with multiple conditions
  conditions <- list(
    list(column = "Species", values = c("setosa"), mode = "include"),
    list(column = "Sepal.Length", values = c(5.1, 5.4), mode = "exclude")
  )
  blk <- new_filter_block(conditions = conditions)
  expect_s3_class(blk, c("filter_block", "transform_block", "block"))
})

test_that("parse_value_filter function works", {
  # Test empty conditions
  expr <- blockr.ai:::parse_value_filter(list())
  expect_type(expr, "language")

  # Test single include condition with character values
  conditions <- list(
    list(
      column = "Species",
      values = c("setosa", "versicolor"),
      mode = "include"
    )
  )
  expr <- blockr.ai:::parse_value_filter(conditions)
  expect_type(expr, "language")
  expect_true(grepl("Species.*%in%.*\"setosa\".*\"versicolor\"", deparse(expr)))

  # Test single exclude condition with character values
  conditions <- list(
    list(column = "Species", values = c("virginica"), mode = "exclude")
  )
  expr <- blockr.ai:::parse_value_filter(conditions)
  expect_type(expr, "language")
  expect_true(grepl("!.*Species.*%in%.*\"virginica\"", deparse(expr)))

  # Test single include condition with numeric values
  conditions <- list(
    list(column = "Sepal.Length", values = c(5.1, 5.4), mode = "include")
  )
  expr <- blockr.ai:::parse_value_filter(conditions)
  expect_type(expr, "language")
  expect_true(grepl("Sepal.Length.*%in%.*5.1.*5.4", deparse(expr)))

  # Test multiple conditions (combined with AND)
  conditions <- list(
    list(column = "Species", values = c("setosa"), mode = "include"),
    list(column = "Sepal.Length", values = c(5.1), mode = "exclude")
  )
  expr <- blockr.ai:::parse_value_filter(conditions)
  expect_type(expr, "language")
  expr_str <- paste(deparse(expr), collapse = " ")
  expect_true(grepl(
    "Species.*%in%.*\"setosa\".*&.*!.*Sepal.Length.*%in%.*5.1",
    expr_str
  ))
})

test_that("parse_value_filter handles edge cases", {
  # Test condition with NULL column
  conditions <- list(
    list(column = NULL, values = c("test"), mode = "include")
  )
  expr <- blockr.ai:::parse_value_filter(conditions)
  expect_true(grepl("TRUE", deparse(expr)))

  # Test condition with empty values
  conditions <- list(
    list(column = "Species", values = character(0), mode = "include")
  )
  expr <- blockr.ai:::parse_value_filter(conditions)
  expect_true(grepl("TRUE", deparse(expr)))

  # Test condition with NULL values
  conditions <- list(
    list(column = "Species", values = NULL, mode = "include")
  )
  expr <- blockr.ai:::parse_value_filter(conditions)
  expect_true(grepl("TRUE", deparse(expr)))

  # Test mixed valid and invalid conditions
  conditions <- list(
    list(column = "Species", values = c("setosa"), mode = "include"),
    list(column = NULL, values = c("test"), mode = "include"),
    list(column = "Sepal.Length", values = c(5.1), mode = "exclude")
  )
  expr <- blockr.ai:::parse_value_filter(conditions)
  expect_type(expr, "language")
  expr_str <- paste(deparse(expr), collapse = " ")
  expect_true(grepl(
    "Species.*%in%.*\"setosa\".*&.*!.*Sepal.Length.*%in%.*5.1",
    expr_str
  ))
})

test_that("value filter generates correct dplyr expressions", {
  # Test include mode with single value
  conditions <- list(
    list(column = "Species", values = c("setosa"), mode = "include")
  )
  expr <- blockr.ai:::parse_value_filter(conditions)

  # Test that it creates a valid dplyr filter
  result <- eval(expr, envir = list(data = iris))
  expect_s3_class(result, "data.frame")
  expect_equal(as.character(unique(result$Species)), "setosa")

  # Test exclude mode with single value
  conditions <- list(
    list(column = "Species", values = c("setosa"), mode = "exclude")
  )
  expr <- blockr.ai:::parse_value_filter(conditions)

  result <- eval(expr, envir = list(data = iris))
  expect_s3_class(result, "data.frame")
  expect_false("setosa" %in% result$Species)
  expect_true(all(c("versicolor", "virginica") %in% result$Species))

  # Test include mode with multiple values
  conditions <- list(
    list(
      column = "Species",
      values = c("setosa", "versicolor"),
      mode = "include"
    )
  )
  expr <- blockr.ai:::parse_value_filter(conditions)

  result <- eval(expr, envir = list(data = iris))
  expect_s3_class(result, "data.frame")
  expect_true(all(result$Species %in% c("setosa", "versicolor")))
  expect_false("virginica" %in% result$Species)
})

test_that("value filter works with numeric columns", {
  # Test with numeric values
  conditions <- list(
    list(column = "Sepal.Length", values = c(5.1, 5.4, 5.8), mode = "include")
  )
  expr <- blockr.ai:::parse_value_filter(conditions)

  result <- eval(expr, envir = list(data = iris))
  expect_s3_class(result, "data.frame")
  expect_true(all(result$Sepal.Length %in% c(5.1, 5.4, 5.8)))

  # Test exclude with numeric values
  conditions <- list(
    list(column = "Sepal.Length", values = c(5.1), mode = "exclude")
  )
  expr <- blockr.ai:::parse_value_filter(conditions)

  result <- eval(expr, envir = list(data = iris))
  expect_s3_class(result, "data.frame")
  expect_false(5.1 %in% result$Sepal.Length)
})

test_that("value filter handles multiple conditions", {
  # Test multiple include conditions (AND logic)
  conditions <- list(
    list(
      column = "Species",
      values = c("setosa", "versicolor"),
      mode = "include"
    ),
    list(column = "Sepal.Length", values = c(5.1, 5.4, 5.8), mode = "include")
  )
  expr <- blockr.ai:::parse_value_filter(conditions)

  result <- eval(expr, envir = list(data = iris))
  expect_s3_class(result, "data.frame")
  expect_true(all(result$Species %in% c("setosa", "versicolor")))
  expect_true(all(result$Sepal.Length %in% c(5.1, 5.4, 5.8)))

  # Test mixed include/exclude conditions
  conditions <- list(
    list(column = "Species", values = c("setosa"), mode = "include"),
    list(column = "Sepal.Length", values = c(5.1), mode = "exclude")
  )
  expr <- blockr.ai:::parse_value_filter(conditions)

  result <- eval(expr, envir = list(data = iris))
  expect_s3_class(result, "data.frame")
  expect_true(all(result$Species == "setosa"))
  expect_false(5.1 %in% result$Sepal.Length)
})

test_that("parse_value_filter supports logic operators", {
  # Test OR logic between conditions
  conditions <- list(
    list(column = "Species", values = c("setosa"), mode = "include"),
    list(
      column = "Species",
      values = c("versicolor"),
      mode = "include",
      operator = "|"
    )
  )
  expr <- blockr.ai:::parse_value_filter(conditions)

  result <- eval(expr, envir = list(data = iris))
  expect_s3_class(result, "data.frame")
  expect_true(all(result$Species %in% c("setosa", "versicolor")))
  expect_false("virginica" %in% result$Species)
})

test_that("value filter handles NA values correctly", {
  # Create test data with NAs
  test_data <- data.frame(
    x = c(1, 2, NA, 4, 5),
    y = c("a", "b", NA, "d", "e"),
    stringsAsFactors = FALSE
  )

  # Test include mode with NA in numeric column
  conditions <- list(
    list(column = "x", values = c("1", "<NA>"), mode = "include")
  )
  expr <- blockr.ai:::parse_value_filter(conditions)
  result <- eval(expr, envir = list(data = test_data))

  expect_equal(nrow(result), 2)
  expect_true(1 %in% result$x)
  expect_true(any(is.na(result$x)))

  # Test exclude mode with NA
  conditions <- list(
    list(column = "x", values = c("<NA>"), mode = "exclude")
  )
  expr <- blockr.ai:::parse_value_filter(conditions)
  result <- eval(expr, envir = list(data = test_data))

  expect_equal(nrow(result), 4)
  expect_false(any(is.na(result$x)))
})

test_that("value filter handles empty strings correctly", {
  # Create test data with empty strings
  test_data <- data.frame(
    x = c("a", "b", "", "d", "e"),
    y = c("foo", "", "bar", "", "baz"),
    stringsAsFactors = FALSE
  )

  # Test include mode with empty string
  conditions <- list(
    list(column = "x", values = c("a", "<empty>"), mode = "include")
  )
  expr <- blockr.ai:::parse_value_filter(conditions)
  result <- eval(expr, envir = list(data = test_data))

  expect_equal(nrow(result), 2)
  expect_true("a" %in% result$x)
  expect_true("" %in% result$x)

  # Test exclude mode with empty string
  conditions <- list(
    list(column = "y", values = c("<empty>"), mode = "exclude")
  )
  expr <- blockr.ai:::parse_value_filter(conditions)
  result <- eval(expr, envir = list(data = test_data))

  expect_equal(nrow(result), 3)
  expect_false("" %in% result$y)
  expect_true(all(result$y != ""))
})

test_that("helper functions convert values correctly", {
  # Test actual_to_display
  expect_equal(blockr.ai:::actual_to_display(NA), "<NA>")
  expect_equal(blockr.ai:::actual_to_display(""), "<empty>")
  expect_equal(blockr.ai:::actual_to_display("test"), "test")
  expect_equal(blockr.ai:::actual_to_display(123), "123")

  # Test display_to_actual
  expect_true(is.na(blockr.ai:::display_to_actual("<NA>")))
  expect_equal(blockr.ai:::display_to_actual("<empty>"), "")
  expect_equal(blockr.ai:::display_to_actual("test"), "test")
  expect_equal(blockr.ai:::display_to_actual("123", "numeric"), 123)
  expect_equal(blockr.ai:::display_to_actual("123", "character"), "123")
})
