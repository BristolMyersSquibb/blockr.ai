test_that("query_llm_with_tools validates tools parameter", {
  user_prompt <- "Create summary statistics"
  system_prompt <- "You are an R expert"
  
  # Should fail with non-list tools
  expect_error(
    query_llm_with_tools(user_prompt, system_prompt, "not a list"),
    "is\\.list\\(tools\\)"
  )
  
  # Should fail with invalid tool objects
  expect_error(
    query_llm_with_tools(user_prompt, system_prompt, list("not a tool")),
    "all\\(lgl_ply\\(tools, is_llm_tool\\)\\)"
  )
})

test_that("query_llm_with_tools handles successful execution", {
  user_prompt <- "Create summary statistics" 
  system_prompt <- "You are an R expert"
  datasets <- list(data = mtcars)
  
  # Create valid tools
  eval_tool <- new_eval_tool(datasets, max_retries = 3)
  help_tool <- new_help_tool()
  tools <- list(eval_tool, help_tool)
  
  # Mock successful chat interaction
  mock_chat <- list(
    register_tool = function(tool) invisible(NULL),
    chat = function(prompt) "I'll create a summary",
    chat_structured = function(response, type) {
      list(
        explanation = "Generated summary statistics for the dataset",
        code = "summary(data)"
      )
    }
  )
  
  local_mocked_bindings(
    chat_dispatch = function(...) mock_chat
  )
  
  result <- query_llm_with_tools(user_prompt, system_prompt, tools, progress = FALSE)
  
  expect_type(result, "list")
  expect_true("explanation" %in% names(result))
  expect_true("code" %in% names(result))
  expect_equal(result$explanation, "Generated summary statistics for the dataset")
  expect_match(result$code, "summary\\(data\\)") # Should be styled
})

test_that("query_llm_with_tools handles chat errors", {
  user_prompt <- "Create plot"
  system_prompt <- "You are an R expert"
  datasets <- list(data = mtcars)
  
  tools <- list(new_eval_tool(datasets), new_help_tool())
  
  # Mock chat that throws error
  mock_chat <- list(
    register_tool = function(tool) invisible(NULL),
    chat = function(prompt) stop("API key not found"),
    chat_structured = function(response, type) stop("API key not found")
  )
  
  local_mocked_bindings(
    chat_dispatch = function(...) mock_chat
  )
  
  result <- query_llm_with_tools(user_prompt, system_prompt, tools, progress = FALSE)
  
  expect_type(result, "list")
  expect_true("error" %in% names(result))
  expect_match(result$error, "API key not found")
})

test_that("query_llm_with_tools registers tools correctly", {
  user_prompt <- "Test prompt"
  system_prompt <- "Test system"
  datasets <- list(data = data.frame(x = 1:3))
  
  # Track registered tools
  registered_tools <- list()
  
  mock_chat <- list(
    register_tool = function(tool) {
      registered_tools <<- append(registered_tools, list(tool))
      invisible(NULL)
    },
    chat = function(prompt) "response",
    chat_structured = function(response, type) {
      list(explanation = "test", code = "1 + 1")
    }
  )
  
  local_mocked_bindings(
    chat_dispatch = function(...) mock_chat
  )
  
  eval_tool <- new_eval_tool(datasets)
  help_tool <- new_help_tool() 
  tools <- list(eval_tool, help_tool)
  
  query_llm_with_tools(user_prompt, system_prompt, tools, progress = FALSE)
  
  # Should have registered 2 tools
  expect_length(registered_tools, 2)
  expect_type(registered_tools[[1]], "closure")
  expect_type(registered_tools[[2]], "closure")
})

test_that("query_llm_with_tools creates enhanced system prompt for logging", {
  user_prompt <- "Test prompt"
  system_prompt <- "You are an R expert"
  datasets <- list(data = data.frame(x = 1:3))
  
  mock_chat <- list(
    register_tool = function(tool) invisible(NULL),
    chat = function(prompt) "response", 
    chat_structured = function(response, type) {
      list(explanation = "test", code = "1 + 1")
    }
  )
  
  local_mocked_bindings(
    chat_dispatch = function(sys_prompt) {
      # chat_dispatch gets the original system prompt
      expect_equal(sys_prompt, "You are an R expert")
      mock_chat
    }
  )
  
  tools <- list(new_eval_tool(datasets), new_help_tool())
  
  # Test that the function works properly - the enhanced system prompt
  # is used for logging but original is passed to chat_dispatch
  result <- query_llm_with_tools(user_prompt, system_prompt, tools, progress = FALSE)
  expect_type(result, "list")
})

test_that("query_llm_with_tools handles structured response parsing errors", {
  user_prompt <- "Test prompt"
  system_prompt <- "Test system"
  tools <- list(new_eval_tool(list(data = data.frame(x = 1:3))))
  
  mock_chat <- list(
    register_tool = function(tool) invisible(NULL),
    chat = function(prompt) "response",
    chat_structured = function(response, type) {
      stop("Failed to parse structured response")
    }
  )
  
  local_mocked_bindings(
    chat_dispatch = function(...) mock_chat
  )
  
  result <- query_llm_with_tools(user_prompt, system_prompt, tools, progress = FALSE)
  
  expect_type(result, "list")
  expect_true("error" %in% names(result))
  expect_match(result$error, "Failed to parse structured response")
})

test_that("query_llm_with_tools styles code in response", {
  user_prompt <- "Test"
  system_prompt <- "Test"
  tools <- list(new_eval_tool(list(data = data.frame(x = 1))))
  
  mock_chat <- list(
    register_tool = function(tool) invisible(NULL),
    chat = function(prompt) "response",
    chat_structured = function(response, type) {
      list(
        explanation = "test explanation",
        code = "x<-1;y<-2" # Unststyled code
      )
    }
  )
  
  local_mocked_bindings(
    chat_dispatch = function(...) mock_chat
  )
  
  result <- query_llm_with_tools(user_prompt, system_prompt, tools, progress = FALSE)
  
  expect_type(result, "list")
  expect_true("code" %in% names(result))
  # Code should be styled (style_code adds spaces around operators)
  expect_match(result$code, "x <- 1")
  expect_match(result$code, "y <- 2")
})