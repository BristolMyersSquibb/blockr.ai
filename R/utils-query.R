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

get_help_topic <- function(topic, package = NULL) {

  pkg_form_path <- function(x) {
    basename(dirname(dirname(x)))
  }

  fetch_rd_db <- utils::getFromNamespace("fetchRdDB", "tools")

  get_help_file <- function(x) {

    path <- dirname(x)
    dirpath <- dirname(path)

    stopifnot(file.exists(dirpath))

    pkgname <- basename(dirpath)
    rd_db <- file.path(path, pkgname)

    stopifnot(file.exists(paste0(rd_db, ".rdx")))

    fetch_rd_db(rd_db, basename(x))
  }

  res <- tryCatch(
    utils::help((topic), (package), help_type = "text"),
    error = function(e) {
      paste0(
        "Error retrieving topic \"", topic, "\" for \"", package, "\": ",
        conditionMessage(e)
      )
    }
  )

  if (inherits(res, "help_files_with_topic")) {

    res <- format(res)

    if (length(res) == 0L) {

      paste0(
        "No help topics found for \"", topic, "\"",
        if (not_null(package)) paste0(" and package \"", package, "\""),
        ". Try different keywords or function names."
      )

    } else if (length(res) > 1L) {

      paste0(
        "Found \"", topic, "\" in ", length(res), " packages:\n",
        paste0("- ", pkg_form_path(res), collapse = "\n"),
        "\nChoose one of these packages to get more detailed information."
      )

    } else {

      pkg <- pkg_form_path(res)
      out <- character()

      tools::Rd2txt(
        get_help_file(res),
        out = textConnection("out", open = "w", local = TRUE),
        package = pkg
      )

      paste(out, collapse = "\n")
    }

  } else {

    stopifnot(is.character(res))
    paste(res, collapse = "\n")
  }
}

get_package_help <- function(package) {

  res <- tryCatch(
    utils::help(package = (package), help_type = "text"),
    error = function(e) {
      paste0(
        "Error retrieving package overview for '", package, "': ",
        conditionMessage(e)
      )
    }
  )

  if (length(res) == 0) {
    return(
      paste0(
        "Package '", package, "' is available but no overview help found. ",
        "Try specifying a topic or function name."
      )
    )
  }

  paste0(
    "R Help Documentation for Package '", package, "':\n\n",
    paste(format(res), collapse = "\n")
  )
}

create_r_help_tool <- function() {

  get_r_help <- function(topic = NULL, package = NULL) {

    if (is.null(topic) && is.null(package)) {
      return(
        paste0(
          "Error: Please provide at least one parameter:\n",
          "- \"topic\" for cross-package search\n",
          "- \"package\" for package-specific help\n",
          "- \"topic\" + \"package\" for specific function help"
        )
      )
    }

    log_debug(
      "Looking up R help for",
      if (!is.null(topic)) paste0(" topic '", topic, "'"),
      if (!is.null(package)) paste0(", package '", package, "'")
    )

    if (is.null(topic)) {
      get_package_help(package)
    } else {
      get_help_topic(topic, package)
    }
  }

  ellmer::tool(
    get_r_help,
    .description = paste(
      "Get R documentation and help. Use \"topic\" for cross-package search,",
      "\"package\" for package-specific help, or both \"package\" and",
      "\"topic\" for specific function documentation."
    ),
    topic = ellmer::type_string(
      "Optional: Search for a specific topic or function."
    ),
    package = ellmer::type_string(
      paste(
        "Optional: Restrict your search to a specific package or if no topic",
        "is specified, retrieve a package overview."
      )
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
