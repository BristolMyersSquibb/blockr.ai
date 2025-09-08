test_that("eval_code works with simple expressions", {
  data <- list(x = 1:3, y = 4:6)
  result <- eval_code("x + y", data)
  expect_equal(result, c(5, 7, 9))
})

test_that("eval_code works with data frames", {
  data <- list(df = data.frame(a = 1:3, b = 4:6))
  result <- eval_code("sum(df$a)", data)
  expect_equal(result, 6)
})

test_that("eval_code uses isolated environment", {
  # Variables in data should not interfere with global env
  data <- list(x = 100)
  result <- eval_code("x", data)
  expect_equal(result, 100)

  # Global x should not be accessible
  x <- 999
  result2 <- eval_code("x", data)  # Should still use data$x, not global x
  expect_equal(result2, 100)
})

test_that("try_eval_code returns result on success", {
  # Use existing transform block proxy which expects data.frame result
  transform_block <- structure(list(), class = "llm_transform_block_proxy")
  data <- list(df = data.frame(x = 1:3, y = 4:6))

  result <- try_eval_code(
    transform_block,
    "data.frame(sum_x = sum(df$x))",
    data
  )
  expect_equal(result$sum_x, 6)
  expect_false(inherits(result, "try-error"))
})

test_that("try_eval_code returns try-error on failure", {
  # Use existing transform block proxy
  transform_block <- structure(list(), class = "llm_transform_block_proxy")
  data <- list(x = 1:3)

  result <- try_eval_code(transform_block, "nonexistent_function(x)", data)
  expect_true(inherits(result, "try-error"))
  expect_type(result, "character")
  expect_match(result, "could not find function")
})

test_that("try_eval_code handles ggplot objects", {
  skip_if_not_installed("ggplot2")

  # Use existing plot block proxy which expects ggplot result
  plot_block <- structure(list(), class = "llm_plot_block_proxy")
  data <- list(df = data.frame(x = 1:3, y = 1:3))

  # Valid ggplot should work
  result <- try_eval_code(
    plot_block,
    "ggplot2::ggplot(df, ggplot2::aes(x, y)) + ggplot2::geom_point()",
    data
  )

  expect_true(ggplot2::is_ggplot(result))
  expect_false(inherits(result, "try-error"))

  # Invalid ggplot should fail early
  result2 <- try_eval_code(
    plot_block,
    "ggplot2::ggplot(nonexist_df, ggplot2::aes(x, y)) + ggplot2::geom_point()",
    data
  )

  expect_true(inherits(result2, "try-error"))
})

test_that("extract_try_error extracts error message", {
  # Create a try-error object
  error_obj <- structure("object 'x' not found", class = "try-error")

  result <- extract_try_error(error_obj)
  expect_type(result, "character")
  expect_equal(result, "object 'x' not found")
})

test_that("extract_try_error fails on non-try-error objects", {
  expect_error(
    extract_try_error("not an error"),
    "inherits\\(x, \"try-error\"\\)"
  )
})

test_that("new_eval_tool creates valid ellmer tool", {
  transform_block <- structure(list(), class = "llm_transform_block_proxy")
  datasets <- list(data = data.frame(x = 1:3, y = 1:3))
  tool <- new_eval_tool(transform_block, datasets, max_retries = 3)

  # Should be an ellmer tool object
  expect_true(is_llm_tool(tool))
  # Note: tool structure may vary with ellmer versions, just test basic
  # functionality
  expect_type(get_tool(tool), "closure")
})

test_that("eval tool invocation counting works", {
  transform_block <- structure(list(), class = "llm_transform_block_proxy")
  datasets <- list(data = data.frame(x = 1:3))
  tool <- new_eval_tool(transform_block, datasets, max_retries = 2)

  # Get the actual tool function for testing
  tool_func <- get_tool(tool)

  # Mock ellmer::tool_reject to capture rejections
  tool_reject_called <- FALSE
  tool_reject_message <- ""

  local_mocked_bindings(
    .package = "ellmer",
    tool_reject = function(message) {
      tool_reject_called <<- TRUE
      tool_reject_message <<- message
      stop(paste("Tool rejected:", message))
    }
  )

  # First failed attempt should return retry message
  result1 <- tool_func(code = "nonexistent_var", explanation = "test")
  expect_type(result1, "character")
  expect_match(result1, "Error on attempt 1/2")
  expect_match(result1, "Please analyze this error")

  # Second failed attempt should trigger tool_reject
  expect_error(
    tool_func(code = "another_nonexistent_var", explanation = "test"),
    "Tool rejected"
  )

  expect_true(tool_reject_called)
  expect_match(tool_reject_message, "Final error after 2 attempts")
})

test_that("eval tool resets counter on success", {
  transform_block <- structure(list(), class = "llm_transform_block_proxy")
  datasets <- list(data = data.frame(x = 1:3))

  tool <- new_eval_tool(transform_block, datasets, max_retries = 3)
  tool_func <- get_tool(tool)

  # Successful execution should work and reset counter
  result <- tool_func(
    code = "data.frame(sum_x = sum(data$x))",
    explanation = "sum the x values"
  )
  expect_type(result, "character")
  expect_match(result, "Code executed successfully")
  expect_match(
    result,
    "```r\\ndata\\.frame\\(sum_x = sum\\(data\\$x\\)\\)\\n```"
  )
})

test_that("eval tool handles max retries exceeded", {
  transform_block <- structure(list(), class = "llm_transform_block_proxy")
  datasets <- list(data = data.frame(x = 1:3))
  tool <- new_eval_tool(transform_block, datasets, max_retries = 1)
  tool_func <- get_tool(tool)

  # Mock ellmer::tool_reject
  tool_reject_called <- FALSE
  local_mocked_bindings(
    .package = "ellmer",
    tool_reject = function(message) {
      tool_reject_called <<- TRUE
      stop(paste("Tool rejected:", message))
    }
  )

  # First call should fail and trigger rejection immediately since
  # max_retries = 1
  expect_error(
    tool_func(code = "nonexistent_var", explanation = "test"),
    "Tool rejected"
  )

  expect_true(tool_reject_called)
})
