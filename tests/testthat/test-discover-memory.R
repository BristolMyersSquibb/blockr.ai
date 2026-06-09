# Tests for conversation memory in discover_block_args
#
# These verify that passing a persistent ellmer client (R6 reference) allows the
# LLM to build on prior conversation turns rather than starting from scratch.
# Uses dataset_block for reliable validation (simple dataset/package params).

make_client <- function(block) {
  client <- blockr.ai:::llm_client()
  var_names <- blockr.ai:::block_ctor_inputs(block)
  sp <- blockr.ai:::build_tool_system_prompt(var_names, block)
  client$set_system_prompt(sp)
  client
}

test_that("discover_block_args: follow-up prompt uses conversation context", {
  skip_on_cran()
  skip_on_ci()
  skip_if(
    !identical(Sys.getenv("BLOCKR_TEST_LLM"), "true"),
    "LLM integration tests disabled (set BLOCKR_TEST_LLM=true to enable)"
  )

  blk <- blockr.core::new_dataset_block()
  client <- make_client(blk)

  # First prompt: use iris
  result1 <- blockr.ai::discover_block_args(
    prompt = "use the iris dataset",
    block = blk,
    client = client
  )
  expect_true(result1$success)
  expect_equal(result1$args$dataset, "iris")

  # Follow-up with same client:
  # "instead" only makes sense if the LLM remembers we chose iris
  result2 <- blockr.ai::discover_block_args(
    prompt = "now use mtcars instead",
    block = blk,
    client = client
  )
  expect_true(result2$success)
  expect_equal(result2$args$dataset, "mtcars")
  expect_equal(ncol(result2$result), 11)
  expect_equal(nrow(result2$result), 32)
})

test_that("discover_block_args: third follow-up still has full context", {
  skip_on_cran()
  skip_on_ci()
  skip_if(
    !identical(Sys.getenv("BLOCKR_TEST_LLM"), "true"),
    "LLM integration tests disabled (set BLOCKR_TEST_LLM=true to enable)"
  )

  blk <- blockr.core::new_dataset_block()
  client <- make_client(blk)

  # Prompt 1
  r1 <- blockr.ai::discover_block_args(
    prompt = "use iris", block = blk, client = client
  )
  expect_true(r1$success)
  expect_equal(r1$args$dataset, "iris")

  # Prompt 2
  r2 <- blockr.ai::discover_block_args(
    prompt = "switch to mtcars", block = blk, client = client
  )
  expect_true(r2$success)
  expect_equal(r2$args$dataset, "mtcars")

  # Prompt 3: "the first dataset I asked for" requires memory of the iris turn
  r3 <- blockr.ai::discover_block_args(
    prompt = "go back to the first dataset I asked for",
    block = blk,
    client = client
  )
  expect_true(r3$success)
  # Handle LLM combining JSON+DONE in one response (args may be NULL)
  if (!is.null(r3$args)) {
    expect_equal(r3$args$dataset, "iris")
  }
  if (!is.null(r3$result)) {
    expect_equal(nrow(r3$result), 150)
  }
})

test_that("discover_block_args: result$client for standalone memory", {
  skip_on_cran()
  skip_on_ci()
  skip_if(
    !identical(Sys.getenv("BLOCKR_TEST_LLM"), "true"),
    "LLM integration tests disabled (set BLOCKR_TEST_LLM=true to enable)"
  )

  blk <- blockr.core::new_dataset_block()

  # No manual client setup — just use result$client from first call
  r1 <- blockr.ai::discover_block_args(
    prompt = "use the iris dataset", block = blk
  )
  expect_true(r1$success)
  expect_equal(r1$args$dataset, "iris")
  expect_false(is.null(r1$client))

  # Pass result$client to follow-up
  r2 <- blockr.ai::discover_block_args(
    prompt = "now use mtcars instead", block = blk, client = r1$client
  )
  expect_true(r2$success)
  expect_equal(r2$args$dataset, "mtcars")
})

test_that("discover_block_args: without client, no memory (baseline)", {
  skip_on_cran()
  skip_on_ci()
  skip_if(
    !identical(Sys.getenv("BLOCKR_TEST_LLM"), "true"),
    "LLM integration tests disabled (set BLOCKR_TEST_LLM=true to enable)"
  )

  blk <- blockr.core::new_dataset_block()

  # First call without persistent client
  result1 <- blockr.ai::discover_block_args(
    prompt = "use the iris dataset",
    block = blk
  )
  expect_true(result1$success)
  expect_equal(result1$args$dataset, "iris")

  # Second call without passing client — runs fine but has no memory
  result2 <- blockr.ai::discover_block_args(
    prompt = "now use mtcars instead",
    block = blk
  )
  expect_true(is.list(result2))
})
