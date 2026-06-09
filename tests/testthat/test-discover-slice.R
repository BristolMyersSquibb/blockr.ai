# Tests for discover_block_args with slice_block
#
# These test the LLM's ability to use prop mode and conversation memory.

make_client <- function(block) {
  client <- blockr.ai:::llm_client()
  var_names <- blockr.ai:::block_ctor_inputs(block)
  sp <- blockr.ai:::build_tool_system_prompt(var_names, block)
  client$set_system_prompt(sp)
  client
}

test_that("discover_block_args slice: prop mode (top 5%)", {
  skip_on_cran()
  skip_on_ci()
  skip_if(
    !identical(Sys.getenv("BLOCKR_TEST_LLM"), "true"),
    "LLM integration tests disabled (set BLOCKR_TEST_LLM=true to enable)"
  )

  blk <- blockr.dplyr::new_slice_block()
  result <- blockr.ai::discover_block_args(
    prompt = "top 5% by mpg",
    block = blk,
    data = mtcars
  )

  expect_true(result$success)
  expect_equal(result$args$prop, 0.05)
  expect_equal(result$args$type, "max")
  expect_equal(result$args$order_by, "mpg")
})

test_that("discover_block_args slice: follow-up with memory", {
  skip_on_cran()
  skip_on_ci()
  skip_if(
    !identical(Sys.getenv("BLOCKR_TEST_LLM"), "true"),
    "LLM integration tests disabled (set BLOCKR_TEST_LLM=true to enable)"
  )

  blk <- blockr.dplyr::new_slice_block()
  client <- make_client(blk)

  # First: top 5% by mpg
  r1 <- blockr.ai::discover_block_args(
    prompt = "top 5% by mpg",
    block = blk,
    data = mtcars,
    client = client
  )
  expect_true(r1$success)
  expect_equal(r1$args$prop, 0.05)

  # Follow-up: change to 10%
  r2 <- blockr.ai::discover_block_args(
    prompt = "make it 10% instead",
    block = blk,
    data = mtcars,
    client = client
  )
  expect_true(r2$success)
  expect_equal(r2$args$prop, 0.1)
  expect_equal(r2$args$type, "max")
  expect_equal(r2$args$order_by, "mpg")
})
