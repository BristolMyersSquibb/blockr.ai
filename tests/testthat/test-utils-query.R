test_that("query_llm_with_tools sets up system prompt correctly", {
  user_prompt <- "Test user prompt"
  system_prompt <- "Test system prompt"

  # Mock client and task
  mock_client <- list(
    set_system_prompt = function(prompt) invisible(NULL),
    set_tools = function(tools) invisible(NULL)
  )

  mock_task <- list(
    invoke = function(client, method, prompt) invisible(NULL)
  )

  # Create tools with prompts
  datasets <- list(data = data.frame(x = 1:3))
  transform_block <- structure(list(), class = "llm_transform_block_proxy")
  tools <- list(
    new_eval_tool(transform_block, datasets, max_retries = 3),
    new_help_tool()
  )

  # Should run without error
  expect_invisible(
    query_llm_with_tools(
      mock_client, mock_task, user_prompt, system_prompt, tools
    )
  )
})
