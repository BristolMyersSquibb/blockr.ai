test_that("llm plot block constructor works", {
  # Test default constructor
  blk <- new_llm_plot_block()
  expect_s3_class(blk, c("llm_plot_block", "transform_block", "block"))
})

test_that("llm plot block constructor handles parameters", {
  # Test constructor with all parameters
  blk <- new_llm_plot_block(
    question = "Plot x vs y",
    code = "plot(x, y)",
    max_retries = 5
  )
  expect_s3_class(blk, c("llm_plot_block", "transform_block", "block"))

  # Test constructor with empty strings
  blk <- new_llm_plot_block(
    question = character(),
    code = character()
  )
  expect_s3_class(blk, c("llm_plot_block", "transform_block", "block"))
})
