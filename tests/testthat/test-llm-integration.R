test_that("system_prompt functions generate proper prompts", {
  # Test GT block system prompt
  gt_proxy <- structure(list(), class = c("llm_gt_block_proxy", "llm_block_proxy"))
  datasets <- list(data = mtcars[1:5, 1:3])
  
  prompt <- system_prompt(gt_proxy, datasets)
  expect_type(prompt, "character")
  expect_match(prompt, "CRITICAL")
  expect_match(prompt, "gt::gt")
  expect_match(prompt, "BAD examples")
  expect_no_match(prompt, "tab_header\\(\"")  # Should not have the old syntax error
  
  # Test plot block system prompt
  plot_proxy <- structure(list(), class = c("llm_plot_block_proxy", "llm_block_proxy"))
  prompt <- system_prompt(plot_proxy, datasets)
  expect_type(prompt, "character")
  expect_match(prompt, "CRITICAL")
  expect_match(prompt, "ggplot2::ggplot")
  expect_match(prompt, "BAD examples")
  
  # Test transform block system prompt  
  transform_proxy <- structure(list(), class = c("llm_transform_block_proxy", "llm_block_proxy"))
  prompt <- system_prompt(transform_proxy, datasets)
  expect_type(prompt, "character")
  expect_match(prompt, "CRITICAL")
  expect_match(prompt, "data.frame")
  expect_match(prompt, "BAD examples")
})

test_that("eval_code works with different object types", {
  datasets <- list(data = mtcars[1:5, 1:3])
  
  # Test GT code execution
  gt_code <- "gt::gt(data) |> gt::tab_header(title = 'Test Table')"
  result <- eval_code(gt_code, datasets)
  expect_s3_class(result, "gt_tbl")
  
  # Test ggplot code execution
  library(ggplot2)
  plot_code <- "ggplot2::ggplot(data, ggplot2::aes(x = mpg, y = hp)) + ggplot2::geom_point()"
  result <- eval_code(plot_code, datasets)
  expect_s3_class(result, "ggplot")
  
  # Test data.frame transformation
  transform_code <- "data |> dplyr::filter(mpg > 20)"
  result <- eval_code(transform_code, datasets)
  expect_s3_class(result, "data.frame")
  expect_true(all(result$mpg > 20))
})

test_that("try_eval_code catches and handles errors", {
  datasets <- list(data = mtcars[1:5, 1:3])
  
  # Test syntax error
  bad_code <- "gt::gt(data |> gt::tab_header("  # Incomplete syntax
  result <- try_eval_code(bad_code, datasets)
  expect_s3_class(result, "try-error")
  
  # Test runtime error
  bad_code2 <- "gt::gt(nonexistent_data)"
  result <- try_eval_code(bad_code2, datasets)
  expect_s3_class(result, "try-error")
  
  # Test ggplot validation
  library(ggplot2)
  plot_code <- "ggplot2::ggplot(data, ggplot2::aes(x = nonexistent_col)) + ggplot2::geom_point()"
  result <- try_eval_code(plot_code, datasets)
  expect_s3_class(result, "try-error")
})

test_that("style_code formats R code properly", {
  messy_code <- "gt::gt(data)|>gt::tab_header(title='Test')"
  styled <- style_code(messy_code)
  
  expect_match(styled, "gt::gt\\(data\\) \\|>")
  expect_match(styled, "gt::tab_header\\(")
  expect_match(styled, "title = \"Test\"")
})

test_that("type_response structure is valid", {
  response_type <- type_response()
  # type_response() returns a structured type object from ellmer
  expect_s3_class(response_type, c("ellmer::TypeObject", "ellmer::Type"))
})