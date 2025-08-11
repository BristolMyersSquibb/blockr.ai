test_that("llm gt block constructor works", {
  # Test default constructor
  blk <- new_llm_gt_block()
  expect_s3_class(blk, c("llm_gt_block", "transform_block", "block"))
})

test_that("llm gt block constructor handles parameters", {
  # Test constructor with all parameters
  blk <- new_llm_gt_block(
    question = "Create a summary table",
    code = "gt::gt(data)",
    max_retries = 5
  )
  expect_s3_class(blk, c("llm_gt_block", "transform_block", "block"))

  # Test constructor with empty strings
  blk <- new_llm_gt_block(
    question = character(),
    code = character()
  )
  expect_s3_class(blk, c("llm_gt_block", "transform_block", "block"))
})

test_that("llm gt block result_ptype returns gt object", {
  # Create a proxy object like the server does
  proxy <- structure(list(), class = c("llm_gt_block_proxy", "llm_block_proxy"))
  ptype <- result_ptype(proxy)
  expect_s3_class(ptype, "gt_tbl")
})

test_that("validate_gt_object works correctly", {
  # Test with proper gt object
  proper_gt <- gt::gt(mtcars[1:5, 1:3])
  result <- validate_gt_object(proper_gt)
  expect_true(result$valid)
  expect_equal(result$message, "")
  
  # Test with non-gt object
  result <- validate_gt_object(data.frame(x = 1))
  expect_false(result$valid)
  expect_match(result$message, "Object is not a gt_tbl")
  
  # Test with malformed object
  fake_gt <- structure(list(), class = "gt_tbl")
  result <- validate_gt_object(fake_gt)
  expect_false(result$valid)
  expect_match(result$message, "missing essential components")
})

test_that("validate_ggplot_object works correctly", {
  # Test with proper ggplot object
  library(ggplot2)
  proper_plot <- ggplot(mtcars, aes(x = mpg, y = hp)) + geom_point()
  result <- validate_ggplot_object(proper_plot)
  expect_true(result$valid)
  expect_equal(result$message, "")
  
  # Test with non-ggplot object
  result <- validate_ggplot_object(data.frame(x = 1))
  expect_false(result$valid)
  expect_match(result$message, "Object is not a ggplot")
  
  # Test with empty ggplot
  empty_plot <- ggplot()
  result <- validate_ggplot_object(empty_plot)
  expect_false(result$valid)
  expect_match(result$message, "no data or layers")
})

test_that("validate_dataframe_object works correctly", {
  # Test with proper data.frame
  result <- validate_dataframe_object(mtcars)
  expect_true(result$valid)
  expect_equal(result$message, "")
  
  # Test with non-data.frame object
  result <- validate_dataframe_object(list(x = 1))
  expect_false(result$valid)
  expect_match(result$message, "Object is not a data.frame")
  
  # Test with empty data.frame
  empty_df <- data.frame()
  result <- validate_dataframe_object(empty_df)
  expect_false(result$valid)
  expect_match(result$message, "completely empty")
})

test_that("validate_block_result dispatches correctly", {
  # Test GT validation with proper object
  proper_gt <- gt::gt(mtcars[1:3, 1:3])
  gt_proxy <- structure(list(), class = c("llm_gt_block_proxy", "llm_block_proxy"))
  result <- validate_block_result(proper_gt, gt_proxy)
  expect_true(result$valid)
  
  # Test wrong type for GT block
  result <- validate_block_result(data.frame(x = 1), gt_proxy)
  expect_false(result$valid)
  expect_match(result$message, "Expected object inheriting from")
  
  # Test ggplot validation
  library(ggplot2)
  proper_plot <- ggplot(mtcars, aes(x = mpg, y = hp)) + geom_point()
  plot_proxy <- structure(list(), class = c("llm_plot_block_proxy", "llm_block_proxy"))
  result <- validate_block_result(proper_plot, plot_proxy)
  expect_true(result$valid)
  
  # Test data.frame validation
  transform_proxy <- structure(list(), class = c("llm_transform_block_proxy", "llm_block_proxy"))
  result <- validate_block_result(mtcars, transform_proxy)
  expect_true(result$valid)
})