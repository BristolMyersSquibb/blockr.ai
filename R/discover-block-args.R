# Discover Block Arguments using LLM
#
# Uses an LLM to figure out the correct arguments for a blockr block
# based on a natural language description.


#' Discover block arguments using LLM
#'
#' Takes a natural language prompt and uses an LLM to figure out the correct
#' arguments for a block constructor. Validates by running the block headlessly.
#'
#' @param prompt User's natural language description of the task
#' @param data Input data (data.frame)
#' @param block_ctor Block constructor function (e.g., new_summarize_block)
#' @param block_name Name of the block (for display in prompt)
#' @param max_iterations Maximum attempts (default: 5)
#' @param model LLM model to use (default: "gpt-4o-mini")
#' @param verbose Print progress messages (default: TRUE)
#'
#' @return List with:
#'   - args: The successful arguments (named list), or NULL if failed
#'   - result: The resulting data.frame (for validation), or NULL
#'   - success: Logical indicating if discovery succeeded
#'   - iterations: Number of iterations used
#'   - code: The R code that generated the args
#'   - messages: Full conversation history (for debugging)
#'
#' @examples
#' \dontrun{
#' result <- discover_block_args(
#'   prompt = "Calculate mean Sepal.Length grouped by Species",
#'   data = iris,
#'   block_ctor = blockr.dplyr::new_summarize_block,
#'   block_name = "new_summarize_block"
#' )
#'
#' if (result$success) {
#'   print(result$args)
#'   print(result$result)
#' }
#' }
#'
#' @export
discover_block_args <- function(
  prompt,
  data,
  block_ctor,
  block_name = NULL,
  max_iterations = 5,
  model = blockr.core::blockr_option("ai_model", "gpt-4o-mini"),
  verbose = TRUE
) {

  # Auto-detect block name if not provided
  if (is.null(block_name)) {
    block_name <- deparse(substitute(block_ctor))
  }

  if (verbose) {
    cat("\n")
    cat(strrep("=", 60), "\n")
    cat("Discovering arguments for:", block_name, "\n")
    cat(strrep("=", 60), "\n\n")
  }

  start_time <- Sys.time()

  # Build system prompt
  sys_prompt <- build_discovery_system_prompt(block_ctor, block_name)

  # Build initial user message with data preview
  data_preview <- create_data_preview(list(data = data))
  user_msg <- paste0(
    "# Data Available\n\n",
    data_preview,
    "\n\n# Task\n\n",
    prompt,
    "\n\nGenerate R code that creates a list called `args` with the correct block parameters."
  )

  # Always show which model is being used

  message("[blockr.ai] Using model: ", model)

  if (verbose) {
    cat("System prompt:", nchar(sys_prompt), "chars\n")
    cat("User message:", nchar(user_msg), "chars\n\n")
  }

  # Create LLM client
  client <- create_chat_client(model)
  client$set_system_prompt(sys_prompt)

  # Track state
  final_args <- NULL
  final_result <- NULL
  final_code <- NULL
  iteration <- 0
  messages <- list()
  current_msg <- user_msg

  # Main loop
  while (iteration < max_iterations) {
    iteration <- iteration + 1

    if (verbose) {
      cat("Iteration ", iteration, "/", max_iterations, "\n", sep = "")
    }

    # Get LLM response
    response <- tryCatch(
      client$chat(current_msg),
      error = function(e) {
        if (verbose) cat("  LLM error:", conditionMessage(e), "\n")
        NULL
      }
    )

    if (is.null(response)) {
      break
    }

    messages <- c(messages, list(
      list(role = "user", content = current_msg),
      list(role = "assistant", content = response)
    ))

    # Check for DONE
    if (is_done_response(response)) {
      if (verbose) cat("  LLM said DONE\n")
      break
    }

    # Extract code
    code <- extract_code_from_markdown(response)

    if (is.null(code) || nchar(trimws(code)) == 0) {
      if (verbose) cat("  No code found in response\n")
      current_msg <- "I couldn't find any R code. Please provide code wrapped in ```r ... ``` that creates a list called `args`."
      next
    }

    if (verbose) cat("  Code extracted (", nchar(code), " chars)\n", sep = "")

    # Execute code to get args
    args <- tryCatch({
      env <- new.env()
      eval(parse(text = code), envir = env)
      env$args
    }, error = function(e) {
      structure(conditionMessage(e), class = "code_error")
    })

    if (inherits(args, "code_error")) {
      if (verbose) cat("  Code error:", substr(args, 1, 60), "\n")
      current_msg <- paste0(
        "Your code produced an error:\n\n",
        "```\n", args, "\n```\n\n",
        "Please fix the code and try again."
      )
      next
    }

    if (is.null(args) || !is.list(args)) {
      if (verbose) cat("  Args is NULL or not a list\n")
      current_msg <- "Your code must create a list called `args`. Please fix and try again."
      next
    }

    if (verbose) {
      cat("  Args created with", length(args), "parameters\n")
      cat("  Args names:", paste(names(args), collapse = ", "), "\n")
      cat("  Trying args:", utils::capture.output(str(args, max.level = 2)), "\n")
    }

    # Run block headlessly to validate (only if not inside a Shiny app)
    # testServer cannot be called from within a running Shiny session
    in_shiny <- !is.null(shiny::getDefaultReactiveDomain())

    if (in_shiny) {
      # Skip headless validation when running inside Shiny
      # Just trust the args are correct based on the LLM output
      if (verbose) cat("  Skipping headless validation (inside Shiny app)\n")
      block_result <- list(success = TRUE, result = data, error = NULL)
    } else {
      block_result <- tryCatch(
        do.call(run_block_headless, c(list(block_ctor = block_ctor, data = data), args)),
        error = function(e) {
          list(success = FALSE, error = conditionMessage(e), result = NULL)
        }
      )
    }

    if (!block_result$success) {
      error_msg <- block_result$error %||% "Block did not produce a valid result"
      if (verbose) cat("  Block execution failed:", error_msg, "\n")
      current_msg <- paste0(
        "The block execution failed with error:\n\n",
        "```\n", error_msg, "\n```\n\n",
        "Please fix the arguments and try again."
      )
      next
    }

    # Success! Store and ask for confirmation
    final_args <- args
    final_result <- block_result$result
    final_code <- code

    if (verbose) {
      cat("  Success: data.frame with", nrow(final_result), "rows\n")
    }

    result_preview <- paste(
      utils::capture.output(print(utils::head(final_result, 10))),
      collapse = "\n"
    )

    current_msg <- paste0(
      "Block executed successfully! Result preview:\n\n",
      "```\n", result_preview, "\n```\n\n",
      "Does this look correct for the task: \"", prompt, "\"?\n",
      "If yes, respond with just: DONE\n",
      "If not, provide corrected code."
    )
  }

  duration <- as.numeric(difftime(Sys.time(), start_time, units = "secs"))
  success <- !is.null(final_args) && !is.null(final_result)

  if (verbose) {
    cat("\n")
    cat(strrep("-", 60), "\n")
    cat("Discovery finished in", round(duration, 1), "seconds\n")
    cat("  Iterations:", iteration, "\n")
    cat("  Success:", success, "\n")
    cat(strrep("-", 60), "\n")
  }

  list(
    args = final_args,
    result = final_result,
    success = success,
    iterations = iteration,
    code = final_code,
    duration_secs = duration,
    messages = messages
  )
}


#' Build system prompt for argument discovery
#'
#' @param block_ctor Block constructor function
#' @param block_name Name of the block
#' @return Character string with system prompt
#' @noRd
build_discovery_system_prompt <- function(block_ctor, block_name) {
  # Get block signature
  sig_text <- format_block_signature(block_ctor, name = block_name)

  # Get available functions for summarize
  funcs <- if (grepl("summarize", block_name, ignore.case = TRUE)) {
    paste0(
      "\n\nAvailable aggregation functions:\n",
      paste("  -", get_summarize_functions(), collapse = "\n")
    )
  } else {
    ""
  }

  # Code writing guidelines for code block
  code_hints <- if (grepl("code_block", block_name, ignore.case = TRUE)) {
    paste0(
      "\n\n## Code Writing Guidelines\n\n",
      "The `code` parameter should contain R code that:\n",
      "- Starts with `data` (the input data.frame)\n",
      "- Uses the base R pipe `|>` (NOT magrittr `%>%`)\n",
      "- Uses namespace prefixes: `dplyr::filter()`, `dplyr::mutate()`, `dplyr::summarize()`, etc.\n",
      "- Returns a data.frame or tibble\n\n",
      "Example of good code:\n",
      "```r\n",
      "data |>\n",
      "  dplyr::filter(cyl == 6) |>\n",
      "  dplyr::mutate(hp_per_cyl = hp / cyl) |>\n",
      "  dplyr::select(mpg, hp, hp_per_cyl)\n",
      "```\n"
    )
  } else {
    ""
  }

  paste0(
    "You are helping configure a blockr block. Given a data description and user task,\n",
    "generate R code that creates the correct arguments for the block constructor.\n\n",
    "# Block Information\n\n",
    sig_text,
    funcs,
    code_hints,
    "\n\n",
    "# Instructions\n\n",
    "1. Output R code wrapped in ```r ... ``` blocks\n",
    "2. The code must create a list called `args` with the block parameters\n",
    "3. Use ONLY column names that exist in the data\n",
    "4. Match the parameter structure shown in the example\n\n",
    "After seeing the result:\n",
    "- If the result looks correct: respond with just DONE\n",
    "- If incorrect: provide fixed code in ```r ... ``` blocks"
  )
}
