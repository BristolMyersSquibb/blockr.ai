create_result_store <- function() {

  result <- NULL
  error <- NULL

  list(
    set_result = function(value) {
      result <<- value
      error <<- NULL
    },
    set_error = function(err) {
      error <<- err
      result <<- NULL
    },
    get_result = function() result,
    get_error = function() error,
    has_result = function() !is.null(result),
    has_error = function() !is.null(error),
    clear = function() {
      result <<- NULL
      error <<- NULL
    }
  )
}

create_code_execution_tool <- function(datasets, result_store) {

  execute_r_code <- function(code, explanation = "") {

    log_debug("Executing R code:\n", code)

    result <- try_eval_code(code, datasets)

    if (inherits(result, "try-error")) {
      error_msg <- unclass(result)
      log_warn("Code execution failed:\n", error_msg)
      # Store error for retrieval
      result_store$set_error(error_msg)
      # Return error message that LLM can use to retry
      paste("Error:", error_msg)
    } else {
      log_debug("Code execution successful")
      # Store result for retrieval
      result_store$set_result(list(
        value = result,
        code = code,
        explanation = explanation
      ))

      "Code executed successfully. Result stored."
    }
  }

  ellmer::tool(
    execute_r_code,
    .description = paste0(
      "Execute R code against the provided datasets. ",
      "Returns success message or error details."
    ),
    code = ellmer::type_string("R code to execute"),
    explanation = ellmer::type_string("Explanation of what the code does")
  )
}

query_llm_with_retry <- function(datasets, user_prompt, system_prompt,
                                 max_retries = 5, progress = FALSE) {

  if (isTRUE(progress)) {
    shinyjs::show(id = "progress_container", anim = TRUE)
    on.exit(
      shinyjs::hide(id = "progress_container", anim = TRUE)
    )
  }

  # Create a result store for this chat session
  result_store <- create_result_store()

  # Enhanced system prompt with retry instructions
  enhanced_system_prompt <- paste0(
    system_prompt,
    "\n\nIMPORTANT INSTRUCTIONS:\n",
    "1. You must use the execute_r_code tool to run any R code you generate.\n",
    "2. If code execution fails, examine the error and try again with ",
    "corrected code.\n",
    "3. You have up to ", max_retries, " attempts to generate working code.\n",
    "4. Keep trying until you produce code that executes successfully, or ",
    "you reach the maximum attempts.\n",
    "5. Do not give up after a single failure - analyze errors and iterate."
  )

  chat <- chat_dispatch(enhanced_system_prompt)
  code_tool <- create_code_execution_tool(datasets, result_store)
  chat$register_tool(code_tool)

  # Enhanced user prompt with retry expectations
  full_prompt <- paste0(
    user_prompt,
    "\n\nPlease use the execute_r_code tool to develop and test your ",
    "solution. If the first attempt fails, analyze the error and try ",
    "again with corrections. You have up to ", max_retries, " attempts."
  )

  log_wrap(
    "\n----------------- user prompt ---------\n\n",
    full_prompt,
    "\n",
    level = "debug"
  )

  # Single chat call - let LLM handle retries internally
  response <- try(
    chat$chat(full_prompt),
    silent = TRUE
  )

  if (inherits(response, "try-error")) {
    msg <- if (is.null(attr(response, "condition"))) {
      unclass(response)
    } else {
      conditionMessage(attr(response, "condition"))
    }

    log_error("Error encountered during chat: ", msg)
    return(list(error = msg))
  }

  # Check if successful result was stored by our tool
  if (result_store$has_result()) {
    result <- result_store$get_result()
    log_debug("Successfully executed code via ellmer tool")
    return(result)
  }

  # If no successful result, return error
  if (result_store$has_error()) {
    last_error <- result_store$get_error()
    log_warn("Final code execution failed: ", last_error)
    return(list(
      error = "Code execution failed",
      explanation = last_error
    ))
  }

  # No tool was called at all
  log_warn("No code execution tool was called")
  list(
    error = "No code generated",
    explanation = "The LLM did not generate or execute any code"
  )
}

default_chat <- function(system_prompt) {
  ellmer::chat_openai(system_prompt, model = "gpt-4o")
}

chat_dispatch <- function(...) {

  fun <- blockr_option(
    "chat_function",
    default_chat
  )

  fun(...)
}
