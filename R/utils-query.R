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

create_code_execution_tool <- function(datasets, result_store,
                                       max_retries = 5) {

  # Track invocation count using closure
  invocation_count <- 0

  execute_r_code <- function(code, explanation = "") {

    invocation_count <<- invocation_count + 1

    log_debug("Executing R code (attempt ", invocation_count, "/", max_retries,
              "):\n", code)

    # Check if we've exceeded the retry limit
    if (invocation_count > max_retries) {
      log_warn("Maximum attempts (", max_retries, ") exceeded")
      ellmer::tool_reject(
        paste0(
        "Maximum number of attempts (", max_retries, ") exceeded. ",
        "Unable to execute code successfully after multiple tries."
        )
      )
    }

    result <- try_eval_code(code, datasets)

    if (inherits(result, "try-error")) {
      error_msg <- unclass(result)
      log_warn("Code execution failed on attempt ", invocation_count, ":\n",
               error_msg)

      if (invocation_count < max_retries) {
        # Return error with retry suggestion
        return(
          paste0(
            "Error on attempt ", invocation_count, "/", max_retries, ": ",
            error_msg, "\n\nPlease analyze this error and provide corrected ",
            "code. Call this tool again with the fixed code."
          )
        )
      } else {
        # Final attempt failed, store error and reject further calls
        log_warn("Final attempt failed")
        result_store$set_error(error_msg)
        ellmer::tool_reject(paste0(
          "Final error after ", max_retries, " attempts: ", error_msg,
          "\n\nUnable to execute code successfully."
        ))
      }
    } else {
      log_debug("Code execution successful on attempt ", invocation_count)
      # Store successful result
      result_store$set_result(list(
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

  ellmer::tool(
    execute_r_code,
    .description = paste0(
      "Execute R code against the provided datasets. If code fails, you ",
      "can call this tool again with corrected code. Maximum ", max_retries,
      " attempts allowed before the tool rejects further calls."
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

  # Simple system prompt - tool handles retry instructions
  enhanced_system_prompt <- paste0(
    system_prompt,
    "\n\nIMPORTANT: You must use the execute_r_code_with_retry tool to run ",
    "any R code you generate. This tool will automatically handle retries ",
    "if your code fails - just follow its guidance to fix any errors."
  )

  chat <- chat_dispatch(enhanced_system_prompt)
  code_tool <- create_code_execution_tool(datasets, result_store, max_retries)
  chat$register_tool(code_tool)

  # Simple user prompt - tool handles retry logic
  full_prompt <- paste0(
    user_prompt,
    "\n\nPlease use the execute_r_code_with_retry tool to implement and ",
    "test your solution."
  )

  log_wrap(
    "\n----------------- user prompt ---------\n\n",
    full_prompt,
    "\n",
    level = "debug"
  )

  # Single chat call - tool handles all retry complexity
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
