test_that("llm transform block constructor works", {
  # Test default constructor
  blk <- new_llm_transform_block()
  expect_s3_class(blk, c("llm_transform_block", "transform_block", "block"))
})

test_that("llm transform block constructor handles parameters", {
  # Test constructor with all parameters
  blk <- new_llm_transform_block(
    question = "What is the mean of x?",
    code = "mean(x)",
    max_retries = 5
  )
  expect_s3_class(blk, c("llm_transform_block", "transform_block", "block"))

  # Test constructor with empty strings
  blk <- new_llm_transform_block(
    question = character(),
    code = character()
  )
  expect_s3_class(blk, c("llm_transform_block", "transform_block", "block"))
})
