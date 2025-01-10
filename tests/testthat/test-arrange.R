test_that("arrange block constructor", {
  # Test basic constructor
  blk <- new_arrange_block()
  expect_s3_class(blk, c("arrange_block", "transform_block", "block"))

  # Test constructor with parameters
  blk <- new_arrange_block("mpg", desc = TRUE)
  expect_s3_class(blk, c("arrange_block", "transform_block", "block"))

  # Test constructor with multiple columns
  blk <- new_arrange_block(c("mpg", "cyl"))
  expect_s3_class(blk, c("arrange_block", "transform_block", "block"))
})
