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
  
  tool <- create_code_execution_tool(datasets, store)
  
  # Should be an ellmer tool object (S7 object)
  expect_s3_class(tool, c("ellmer::ToolDef", "S7_object"))
  expect_equal(tool@name, "execute_r_code")
  expect_type(tool@description, "character")
  # For now, just check that it's a tool - ellmer's internal structure may vary
  expect_true(inherits(tool, "ellmer::ToolDef"))
})

test_that("query_llm_with_retry works with successful execution", {
  datasets <- list(data = mtcars)
  user_prompt <- "Create summary statistics"
  system_prompt <- "You are an R expert"
  
  # Create a mock chat that simulates successful code execution
  registered_tool <- NULL
  mock_chat <- list(
    register_tool = function(tool) {
      registered_tool <<- tool
      invisible(NULL)
    },
    chat = function(prompt) {
      # Simulate the LLM successfully calling our tool
      if (!is.null(registered_tool)) {
        # Call the actual tool function with test code
        result <- registered_tool@.fn("summary(data)", "Generated summary statistics")
      }
      "Tool executed successfully"
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
  expect_true("value" %in% names(result))
  expect_true("code" %in% names(result))
  expect_true("explanation" %in% names(result))
  expect_equal(result$code, "summary(data)")
  expect_equal(result$explanation, "Generated summary statistics")
})

test_that("query_llm_with_retry handles execution errors", {
  datasets <- list(data = mtcars)
  user_prompt <- "Create broken code"
  system_prompt <- "You are an R expert"
  
  # Create a mock chat that simulates failed code execution
  registered_tool <- NULL
  mock_chat <- list(
    register_tool = function(tool) {
      registered_tool <<- tool
      invisible(NULL)
    },
    chat = function(prompt) {
      # Simulate the LLM calling our tool with broken code
      if (!is.null(registered_tool)) {
        # Call the tool with code that will fail
        result <- registered_tool@.fn("nonexistent_var", "This should fail")
      }
      "Tool execution attempted"
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
  expect_equal(result$error, "Code execution failed")
}

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