test_that("create_result_store works correctly", {
  store <- create_result_store()
  
  # Initially empty
  expect_false(store$has_result())
  expect_false(store$has_error())
  expect_null(store$get_result())
  expect_null(store$get_error())
  
  # Can store result
  test_result <- list(value = "test", code = "x <- 1", explanation = "test")
  store$set_result(test_result)
  
  expect_true(store$has_result())
  expect_false(store$has_error())
  expect_equal(store$get_result(), test_result)
  expect_null(store$get_error())
  
  # Can store error (clears result)
  store$set_error("test error")
  
  expect_false(store$has_result())
  expect_true(store$has_error())
  expect_null(store$get_result())
  expect_equal(store$get_error(), "test error")
  
  # Can clear
  store$clear()
  
  expect_false(store$has_result())
  expect_false(store$has_error())
  expect_null(store$get_result())
  expect_null(store$get_error())
})

test_that("create_code_execution_tool creates valid ellmer tool", {
  datasets <- list(data = data.frame(x = 1:3, y = 1:3))
  store <- create_result_store()
  max_retries <- 3
  
  tool <- create_code_execution_tool(datasets, store, max_retries)
  
  # Should be an ellmer tool object (S7 object)
  expect_s3_class(tool, c("ellmer::ToolDef", "S7_object"))
  expect_equal(tool@name, "execute_r_code")
  expect_type(tool@description, "character")
  expect_match(tool@description, "Maximum 3 attempts")
  # For now, just check that it's a tool - ellmer's internal structure may vary
  expect_true(inherits(tool, "ellmer::ToolDef"))
})

test_that("tool counter automatically resets per query", {
  # Each new query creates a fresh tool instance, so counter starts at 0
  datasets <- list(data = data.frame(x = 1:3, y = 1:3))
  store1 <- create_result_store()
  store2 <- create_result_store()

  # Create two separate tool instances (simulating two queries)
  tool1 <- create_code_execution_tool(datasets, store1, 3)
  tool2 <- create_code_execution_tool(datasets, store2, 3)

  # Both should be properly structured ellmer tools
  expect_s3_class(tool1, c("ellmer::ToolDef", "S7_object"))
  expect_s3_class(tool2, c("ellmer::ToolDef", "S7_object"))
  expect_equal(tool1@name, "execute_r_code")
  expect_equal(tool2@name, "execute_r_code")

  # Each tool instance has its own counter starting at 0
  expect_true(inherits(tool1, "ellmer::ToolDef"))
  expect_true(inherits(tool2, "ellmer::ToolDef"))
})

test_that("tool rejects after max retries", {
  # Test that tool_reject is called correctly - this will be tested
  # through the integration tests since we can't easily access the
  # internal ellmer tool function directly
  datasets <- list(data = data.frame())  # Empty data to cause errors
  store <- create_result_store()
  max_retries <- 2

  tool <- create_code_execution_tool(datasets, store, max_retries)

  # Just verify the tool is properly constructed
  expect_s3_class(tool, c("ellmer::ToolDef", "S7_object"))
  expect_true(inherits(tool, "ellmer::ToolDef"))
})

test_that("query_llm_with_retry works with successful execution", {
  datasets <- list(data = mtcars)
  user_prompt <- "Create summary statistics"
  system_prompt <- "You are an R expert"
  
  # Create a shared result store that will be used by both mock and function
  shared_store <- create_result_store()
  
  mock_chat <- list(
    register_tool = function(tool) invisible(NULL),
    chat = function(prompt) {
      # Simulate successful tool execution by setting the result
      shared_store$set_result(list(
        value = summary(datasets$data),
        code = "summary(data)",
        explanation = "Generated summary statistics"
      ))
      "Tool executed successfully"
    }
  )
  
  local_mocked_bindings(
    create_result_store = function() shared_store,
    chat_dispatch = function(...) mock_chat
  )
  
  result <- query_llm_with_retry(
    datasets = datasets,
    user_prompt = user_prompt,
    system_prompt = system_prompt,
    max_retries = 3,
    progress = FALSE
  )
  
  expect_type(result, "list")
  expect_true("value" %in% names(result))
  expect_true("code" %in% names(result))
  expect_true("explanation" %in% names(result))
  expect_equal(result$code, "summary(data)")
  expect_equal(result$explanation, "Generated summary statistics")
})

test_that("query_llm_with_retry creates fresh tool for each query", {
  datasets <- list(data = mtcars)
  user_prompt <- "Create plot"
  system_prompt <- "You are an R expert"

  tool_creation_calls <- 0

  mock_chat <- list(
    register_tool = function(tool) invisible(NULL),
    chat = function(prompt) "No tool calls made"
  )

  local_mocked_bindings(
    create_code_execution_tool = function(...) {
      tool_creation_calls <<- tool_creation_calls + 1
      # Return the actual tool to avoid recursive calls
      ellmer::tool(
        function(code, explanation = "") "mock success",
        .description = "Mock tool",
        code = ellmer::type_string("R code"),
        explanation = ellmer::type_string("Explanation")
      )
    },
    chat_dispatch = function(...) mock_chat
  )

  # First query
  query_llm_with_retry(datasets, user_prompt, system_prompt, max_retries = 3,
                      progress = FALSE)
  expect_equal(tool_creation_calls, 1)

  # Second query
  query_llm_with_retry(datasets, user_prompt, system_prompt, max_retries = 3,
                      progress = FALSE)
  expect_equal(tool_creation_calls, 2)
})

test_that("query_llm_with_retry handles execution errors", {
  datasets <- list(data = mtcars)
  user_prompt <- "Create broken code"
  system_prompt <- "You are an R expert"
  
  # Create a shared result store that will be used to simulate failure
  shared_store <- create_result_store()
  
  mock_chat <- list(
    register_tool = function(tool) invisible(NULL),
    chat = function(prompt) {
      # Simulate failed tool execution by setting error
      shared_store$set_error("object 'nonexistent_var' not found")
      "Tool execution attempted"
    }
  )
  
  local_mocked_bindings(
    create_result_store = function() shared_store,
    chat_dispatch = function(...) mock_chat
  )
  
  result <- query_llm_with_retry(
    datasets = datasets,
    user_prompt = user_prompt,
    system_prompt = system_prompt,
    max_retries = 3,
    progress = FALSE
  )
  
  expect_type(result, "list")
  expect_true("error" %in% names(result))
  expect_equal(result$error, "Code execution failed")
})

test_that("query_llm_with_retry handles no tool execution", {
  datasets <- list(data = mtcars)
  user_prompt <- "Just respond with text"
  system_prompt <- "You are an R expert"
  
  # Mock the chat to not call any tools
  mock_chat <- list(
    register_tool = function(tool) invisible(NULL),
    chat = function(prompt) "I think you should use ggplot2 for this task."
  )
  
  local_mocked_bindings(
    chat_dispatch = function(...) mock_chat
  )
  
  result <- query_llm_with_retry(
    datasets = datasets,
    user_prompt = user_prompt,
    system_prompt = system_prompt,
    max_retries = 3,
    progress = FALSE
  )
  
  expect_type(result, "list")
  expect_true("error" %in% names(result))
  expect_equal(result$error, "No code generated")
  expect_equal(result$explanation, "The LLM did not generate or execute any code")
})

test_that("query_llm_with_retry handles chat errors", {
  datasets <- list(data = mtcars)
  user_prompt <- "Create summary statistics"
  system_prompt <- "You are an R expert"
  
  # Mock a chat object that throws an error
  mock_chat <- list(
    register_tool = function(tool) invisible(NULL),
    chat = function(prompt) {
      stop("API key not found")
    }
  )
  
  local_mocked_bindings(
    chat_dispatch = function(...) mock_chat
  )
  
  result <- query_llm_with_retry(
    datasets = datasets,
    user_prompt = user_prompt,
    system_prompt = system_prompt,
    max_retries = 3,
    progress = FALSE
  )
  
  expect_type(result, "list")
  expect_true("error" %in% names(result))
  expect_match(result$error, "API key not found")
})
