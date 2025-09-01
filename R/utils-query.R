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

create_r_help_tool <- function() {

  get_r_help <- function(package, function_name = NULL, search_term = NULL) {

    log_debug("Looking up R help for package '", package, "'",
              if (!is.null(function_name)) paste0(", function '", function_name, "'"),
              if (!is.null(search_term)) paste0(", search term '", search_term, "'"))

    # Validate inputs
    if (missing(package) || is.null(package) || package == "") {
      return("Error: Package name is required.")
    }

    # Check if package is available
    if (!requireNamespace(package, quietly = TRUE)) {
      available_packages <- rownames(utils::installed.packages())
      similar_packages <- available_packages[
        grepl(package, available_packages, ignore.case = TRUE)
      ]

      error_msg <- paste0(
        "Package '", package, "' is not available or installed."
      )

      if (length(similar_packages) > 0) {
        error_msg <- paste0(
          error_msg, " Similar packages: ",
          paste(utils::head(similar_packages, 3), collapse = ", ")
        )
      }

      return(error_msg)
    }

    # Case 1: Package overview (no specific function or search term)
    if (is.null(function_name) && is.null(search_term)) {
      tryCatch({
        help_content <- utils::capture.output(
          utils::help(package = package, help_type = "text")
        )

        if (length(help_content) == 0) {
          return(paste0(
            "Package '", package, "' is available but no overview help found. ",
            "Try specifying a function name."
          ))
        }

        return(paste0(
          "R Help Documentation for Package '", package, "':\n\n",
          paste(help_content, collapse = "\n")
        ))
      }, error = function(e) {
        return(paste0(
          "Error retrieving package overview for '", package, "': ",
          conditionMessage(e)
        ))
      })
    }

    # Case 2: Specific function help
    if (!is.null(function_name)) {
      tryCatch({
        # Get help for specific function
        help_obj <- utils::help(function_name, package = package,
                        help_type = "text", verbose = FALSE)

        if (length(help_obj) == 0) {
          # Try to find similar function names in the package
          package_functions <- tryCatch({
            ls(paste0("package:", package))
          }, error = function(e) character(0))

          similar_functions <- package_functions[
            grepl(function_name, package_functions, ignore.case = TRUE)
          ]

          error_msg <- paste0(
            "Function '", function_name, "' not found in package '",
            package, "'."
          )

          if (length(similar_functions) > 0) {
            error_msg <- paste0(
              error_msg, " Similar functions: ",
              paste(utils::head(similar_functions, 5), collapse = ", ")
            )
          }

          return(error_msg)
        }

        help_content <- utils::capture.output(print(help_obj))

        return(paste0(
          "R Help Documentation for '", function_name, "' in package '",
          package, "':\n\n",
          paste(help_content, collapse = "\n")
        ))

      }, error = function(e) {
        return(paste0(
          "Error retrieving help for function '", function_name,
          "' in package '", package, "': ", conditionMessage(e)
        ))
      })
    }

    # Case 3: Search within package
    if (!is.null(search_term)) {
      tryCatch({
        # Get all functions in package and search
        package_functions <- ls(paste0("package:", package))
        matching_functions <- package_functions[
          grepl(search_term, package_functions, ignore.case = TRUE)
        ]

        if (length(matching_functions) == 0) {
          return(paste0(
            "No functions found matching '", search_term,
            "' in package '", package, "'."
          ))
        }

        result <- paste0(
          "Functions matching '", search_term, "' in package '",
          package, "':\n\n",
          paste(utils::head(matching_functions, 10), collapse = ", ")
        )

        if (length(matching_functions) > 10) {
          result <- paste0(result, "\n\n(Showing first 10 of ",
                          length(matching_functions), " matches)")
        }

        return(paste0(result, "\n\nUse the function parameter to get ",
                     "detailed help for any specific function."))

      }, error = function(e) {
        return(paste0(
          "Error searching for '", search_term, "' in package '",
          package, "': ", conditionMessage(e)
        ))
      })
    }
  }

  ellmer::tool(
    get_r_help,
    .description = paste0(
      "Get R documentation for packages and functions. Provide a package ",
      "name (required) and optionally a specific function name for ",
      "detailed help or a search term to find matching functions."
    ),
    package = ellmer::type_string("Name of the R package to query"),
    function_name = ellmer::type_string(
      "Optional: specific function name within the package"
    ),
    search_term = ellmer::type_string(
      "Optional: term to search for within the package functions"
    )
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
    "\n\nIMPORTANT: You have access to two tools:\n",
    "1. execute_r_code_with_retry: Use this to run any R code you generate. ",
    "This tool will automatically handle retries if your code fails - just ",
    "follow its guidance to fix any errors.\n",
    "2. get_r_help: Use this to look up R documentation for packages and ",
    "functions. This can help you understand function usage, parameters, ",
    "and examples before writing code."
  )

  chat <- chat_dispatch(enhanced_system_prompt)
  code_tool <- create_code_execution_tool(datasets, result_store, max_retries)
  help_tool <- create_r_help_tool()
  chat$register_tool(code_tool)
  chat$register_tool(help_tool)

  # Simple user prompt - tool handles retry logic
  full_prompt <- paste0(
    user_prompt,
    "\n\nPlease use the available tools to implement and test your solution. ",
    "Use get_r_help to look up documentation if needed, then use ",
    "execute_r_code_with_retry to run your code."
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
