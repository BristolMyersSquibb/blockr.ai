test_that("deterministic llm transform block constructor works", {
  # Test default constructor
  blk <- new_llm_transform_block_det()
  expect_s3_class(blk, c("llm_transform_block_det", "transform_block", "block"))
})

test_that("proxy class is correct for result_ptype dispatch", {
  # This test ensures the proxy class name doesn't have double "_det"
  blk <- new_llm_transform_block_det()

  # The proxy should be "llm_transform_block_det_proxy", NOT "llm_transform_block_det_det_proxy"
  # We can verify by checking result_ptype method exists
  proxy <- structure(list(), class = "llm_transform_block_det_proxy")
  expect_equal(blockr.ai:::result_ptype(proxy), data.frame())
})

test_that("deterministic llm transform block constructor handles parameters", {
  # Test constructor with messages
  blk <- new_llm_transform_block_det(
    messages = list(
      list(role = "user", content = "What is the mean of mpg?")
    ),
    code = "data |> dplyr::summarize(mean_mpg = mean(mpg))"
  )
  expect_s3_class(blk, c("llm_transform_block_det", "transform_block", "block"))

  # Test constructor with empty values
  blk <- new_llm_transform_block_det(
    messages = list(),
    code = character()
  )
  expect_s3_class(blk, c("llm_transform_block_det", "transform_block", "block"))
})

test_that("helper functions work correctly", {
  # Test is_done_response
  expect_true(is_done_response("DONE"))
  expect_true(is_done_response("done"))
  expect_true(is_done_response("  DONE  "))
  expect_true(is_done_response("The result looks correct. DONE"))
  expect_false(is_done_response("Here is the code:\n```r\ndata\n```"))
  expect_false(is_done_response("Not done yet"))

 # Test extract_code_from_markdown
  code <- extract_code_from_markdown("Here is code:\n```r\ndata |> dplyr::filter(mpg > 20)\n```")
  expect_equal(code, "data |> dplyr::filter(mpg > 20)")

  code <- extract_code_from_markdown("```R\nmtcars\n```")
  expect_equal(code, "mtcars")

  code <- extract_code_from_markdown("No code here")
  expect_null(code)

  # Test create_data_preview
  preview <- create_data_preview(list(data = mtcars[1:5, 1:3]))
  expect_type(preview, "character")
  expect_true(grepl("Dataset: data", preview))
  expect_true(grepl("5 rows x 3 cols", preview))
})

test_that("system_prompt_det returns correct prompt", {
  # Use the default method directly
  prompt <- blockr.ai:::system_prompt_det.default(NULL, list(data = mtcars))
  expect_type(prompt, "character")
  expect_true(grepl("dplyr", prompt))
  expect_true(grepl("DONE", prompt))
  expect_true(grepl("native pipe", prompt, ignore.case = TRUE))
})
