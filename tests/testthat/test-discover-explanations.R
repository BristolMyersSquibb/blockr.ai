# Tests for explanatory LLM responses in discover_block_args
#
# These verify that the LLM includes a brief explanation alongside JSON,
# not just raw JSON. The explanation is shown to the user in the chat UI
# via strip_json_block(). Tests use verbose = TRUE to inspect conversation.

skip_boilerplate <- function() {
  skip_on_cran()
  skip_on_ci()
  skip_if(
    !identical(Sys.getenv("BLOCKR_TEST_LLM"), "true"),
    "LLM integration tests disabled (set BLOCKR_TEST_LLM=true to enable)"
  )
}

test_that("filter_block: response includes explanation text", {
  skip_boilerplate()

  result <- blockr.ai::discover_block_args(
    prompt = "only setosa species",
    block = blockr.dplyr::new_filter_block(),
    data = iris,
    verbose = TRUE
  )

  expect_true(result$success)

  # The message shown to the user should not be empty
  expect_true(nzchar(result$message %||% ""))

  # Check that the first assistant response contains text outside the JSON block
  assistant_msgs <- Filter(
    function(m) m$role == "assistant",
    result$conversation
  )
  expect_true(length(assistant_msgs) > 0)

  first_reply <- assistant_msgs[[1]]$content
  explanation <- blockr.ai:::strip_json_block(first_reply)
  expect_true(
    nzchar(explanation),
    info = paste("Expected explanation text, got empty. Full response:", first_reply)
  )
})

test_that("filter_block: numeric comparison includes explanation of value selection", {
  skip_boilerplate()

  result <- blockr.ai::discover_block_args(
    prompt = "sepal length less than 5",
    block = blockr.dplyr::new_filter_block(),
    data = iris,
    verbose = TRUE
  )

  expect_true(result$success)
  expect_true(nzchar(result$message %||% ""))

  # The explanation should mention something about the values or the column
  explanation <- result$message
  expect_true(
    grepl("Sepal|sepal|length|values|less|include", explanation, ignore.case = TRUE),
    info = paste("Explanation should reference the filter logic. Got:", explanation)
  )
})

test_that("select_block: response includes explanation text", {
  skip_boilerplate()

  result <- blockr.ai::discover_block_args(
    prompt = "keep only mpg and cyl columns",
    block = blockr.dplyr::new_select_block(),
    data = mtcars,
    verbose = TRUE
  )

  expect_true(result$success)
  expect_true(nzchar(result$message %||% ""))
})

test_that("summarize_block: response includes explanation text", {
  skip_boilerplate()

  result <- blockr.ai::discover_block_args(
    prompt = "average sepal length by species",
    block = blockr.dplyr::new_summarize_block(),
    data = iris,
    verbose = TRUE
  )

  expect_true(result$success)
  expect_true(nzchar(result$message %||% ""))
})
