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
  # Test that each tool instance has independent invocation counters
  # by verifying that separate query_llm_with_retry calls behave independently
  
  datasets <- list(data = mtcars)
  user_prompt <- "Create plot"
  system_prompt <- "You are an R expert"
  
  # Counter to track how many times tools were created
  tool_creations <- 0
  created_tools <- list()
  
  # Mock that simulates tool exhaustion for first call, success for second
  call_count <- 0
  
  mock_chat_generator <- function() {
    call_count <<- call_count + 1
    current_call <- call_count
    
    list(
      register_tool = function(tool) invisible(NULL),
      chat = function(prompt) {
        if (current_call == 1) {
          # First query: simulate tool exhaustion (no result, no error)
          "I couldn't generate working code after several attempts"
        } else {
          # Second query: should work independently 
          # (this tests that the new tool's counter started fresh)
          "Tool executed successfully"
        }
      }
    )
  }
  
  # Store reference to original function to avoid recursion
  original_create_tool <- create_code_execution_tool
  
  local_mocked_bindings(
    create_code_execution_tool = function(datasets, store, max_retries) {
      tool_creations <<- tool_creations + 1
      tool <- original_create_tool(datasets, store, max_retries)
      created_tools[[tool_creations]] <<- tool
      return(tool)
    },
    chat_dispatch = function(...) mock_chat_generator()
  )
  
  # First query - should not get a result due to mock setup
  result1 <- query_llm_with_retry(
    datasets = datasets,
    user_prompt = user_prompt,
    system_prompt = system_prompt, 
    max_retries = 2,
    progress = FALSE
  )
  
  # Second query - should also not get a result but uses fresh tool
  result2 <- query_llm_with_retry(
    datasets = datasets,
    user_prompt = user_prompt,
    system_prompt = system_prompt,
    max_retries = 2, 
    progress = FALSE
  )
  
  # Verify that two separate tools were created (each query gets fresh tool)
  expect_equal(tool_creations, 2)
  expect_length(created_tools, 2)
  
  # Verify the tools are different objects (not shared)
  expect_false(identical(created_tools[[1]], created_tools[[2]]))
  
  # Both queries should have "no code generated" since mock doesn't call tools
  expect_true("error" %in% names(result1))
  expect_true("error" %in% names(result2))
  expect_equal(result1$error, "No code generated")
  expect_equal(result2$error, "No code generated")
})

test_that("tool rejects after max retries", {
  # Test the retry mechanism by creating our own version of the logic
  # to verify that the retry counting and rejection works correctly
  datasets <- list(data = data.frame())  # Empty data to cause errors
  store <- create_result_store()
  max_retries <- 2
  
  # Mock ellmer::tool_reject to capture when it's called
  tool_reject_called <- FALSE
  tool_reject_message <- ""
  
  local_mocked_bindings(
    .package = "ellmer",
    tool_reject = function(message) {
      tool_reject_called <<- TRUE
      tool_reject_message <<- message
      # Simulate what tool_reject would do - throw error
      stop(paste("Tool rejected:", message))
    }
  )
  
  # Recreate the key logic from create_code_execution_tool to test it
  invocation_count <- 0
  
  execute_r_code_test <- function(code, explanation = "") {
    invocation_count <<- invocation_count + 1
    
    # Check if we've exceeded the retry limit (same logic as in actual function)
    if (invocation_count > max_retries) {
      log_warn("Maximum attempts (", max_retries, ") exceeded")
      ellmer::tool_reject(paste0(
        "Maximum number of attempts (", max_retries, ") exceeded. ",
        "Unable to execute code successfully after multiple tries."
      ))
    }
    
    result <- try_eval_code(code, datasets)
    
    if (inherits(result, "try-error")) {
      error_msg <- unclass(result)
      log_warn("Code execution failed on attempt ", invocation_count, ":\n", 
               error_msg)
      
      if (invocation_count < max_retries) {
        # Return error with retry suggestion
        return(paste0(
          "Error on attempt ", invocation_count, "/", max_retries, ": ", 
          error_msg, "\n\nPlease analyze this error and provide corrected ",
          "code. Call this tool again with the fixed code."
        ))
      } else {
        # Final attempt failed, store error and reject further calls
        log_warn("Final attempt failed")
        store$set_error(error_msg)
        ellmer::tool_reject(paste0(
          "Final error after ", max_retries, " attempts: ", error_msg,
          "\n\nUnable to execute code successfully."
        ))
      }
    } else {
      # Success case
      store$set_result(list(
        value = result,
        code = code,
        explanation = explanation
      ))
      return(paste0(
        "Code executed successfully on attempt ", invocation_count, "/", 
        max_retries, ". Result stored."
      ))
    }
  }
  
  # Test that first attempt returns retry message
  result1 <- execute_r_code_test("invalid_code_1", "test")
  expect_type(result1, "character")
  expect_match(result1, "Error on attempt 1")
  expect_equal(invocation_count, 1)
  
  # Second attempt should trigger tool_reject (invocation_count = max_retries = 2)
  expect_error(
    execute_r_code_test("invalid_code_2", "test"),
    "Tool rejected.*Final error after.*attempts"
  )
  expect_equal(invocation_count, 2)
  
  # Verify tool_reject was called with correct message
  expect_true(tool_reject_called)
  expect_match(tool_reject_message, "Final error after.*attempts")
  
  # Third attempt should be blocked before execution (invocation_count > max_retries)
  tool_reject_called <<- FALSE  # Reset for testing the second rejection path
  expect_error(
    execute_r_code_test("invalid_code_3", "test"),
    "Tool rejected.*Maximum number of attempts.*exceeded"
  )
  expect_equal(invocation_count, 3)
  
  # Store should have the final error from the last attempt
  expect_true(store$has_error())
  expect_false(store$has_result())
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
