# Discover Block Chain using LLM
#
# Step-by-step discovery of a chain of blocks to solve a complex task.


#' Discover a chain of blocks to solve a task
#'
#' Uses an LLM to iteratively pick blocks and discover their arguments
#' until the task is complete.
#'
#' @param prompt User's task description
#' @param data Input data (data.frame)
#' @param max_steps Maximum number of blocks in chain (default: 5)
#' @param model LLM model to use (default: "gpt-4o-mini")
#' @param verbose Print progress (default: TRUE)
#'
#' @return List with:
#'   - result: Final data.frame
#'   - success: Logical
#'   - chain: List of steps, each with (block, args, result)
#'   - iterations: Total LLM calls
#'
#' @export
discover_block_chain <- function(
  prompt,
  data,
  max_steps = 5,
  model = "gpt-4o-mini",
  verbose = TRUE
) {

  if (verbose) {
    cat("\n")
    cat(strrep("=", 70), "\n")
    cat("Discovering block chain for task:\n")
    cat("  ", prompt, "\n")
    cat(strrep("=", 70), "\n\n")
  }

  start_time <- Sys.time()

  # Get available blocks
  blocks_info <- get_dplyr_block_info()
  blocks_prompt <- format_blocks_for_llm(blocks_info)

  # Build system prompt
  sys_prompt <- build_chain_system_prompt(blocks_prompt)

  # Create LLM client
  client <- ellmer::chat_openai(model = model)
  client$set_system_prompt(sys_prompt)

  # Track state
  current_data <- data
  chain <- list()
  step <- 0
  total_iterations <- 0

  # Main loop
  while (step < max_steps) {
    step <- step + 1

    if (verbose) {
      cat(strrep("-", 70), "\n")
      cat("Step ", step, "/", max_steps, "\n", sep = "")
      cat(strrep("-", 70), "\n\n")
    }

    # Build message asking for next step
    data_preview <- create_data_preview(list(data = current_data))

    # Break down the original task for the LLM
    user_msg <- paste0(
      "# Original Task\n\n",
      prompt,
      "\n\n# Current Data State\n\n",
      data_preview,
      "\n\n# Steps Completed\n\n",
      if (length(chain) == 0) {
        "None yet - this is the starting data."
      } else {
        paste(
          sapply(seq_along(chain), function(i) {
            paste0("- ", chain[[i]]$block, ": ", chain[[i]]$subtask)
          }),
          collapse = "\n"
        )
      },
      "\n\n# Instructions\n\n",
      "Look at the ORIGINAL TASK above. Check each part:\n",
      "1. Has the filtering/selection been done? (if requested)\n",
      "2. Have any new columns been created? (if requested)\n",
      "3. Has the aggregation/summary been calculated? (if requested)\n\n",
      "If ANY part of the original task is still missing, provide:\n",
      "BLOCK: <block_name>\n",
      "SUBTASK: <what this step should do>\n\n",
      "Only if EVERY part is complete, respond with: DONE"
    )

    if (verbose) {
      cat("Asking LLM for next step...\n")
    }

    # Get LLM response
    response <- tryCatch(
      client$chat(user_msg),
      error = function(e) {
        if (verbose) cat("  LLM error:", conditionMessage(e), "\n")
        NULL
      }
    )
    total_iterations <- total_iterations + 1

    if (is.null(response)) {
      break
    }

    # First try to parse for BLOCK: - if found, continue even if DONE is also present
    parsed <- parse_next_step_response(response)

    # Only check for DONE if we couldn't find a block instruction
    if (is.null(parsed) && is_done_response(response)) {
      if (verbose) cat("LLM says task is complete!\n\n")
      break
    }

    if (is.null(parsed)) {
      if (verbose) cat("Could not parse response, asking for clarification...\n")
      # Ask for clarification
      response <- client$chat(
        "Please respond in this format:\nBLOCK: block_name\nSUBTASK: what this step should do"
      )
      total_iterations <- total_iterations + 1
      parsed <- parse_next_step_response(response)

      if (is.null(parsed)) {
        if (verbose) cat("Still could not parse, stopping.\n")
        break
      }
    }

    if (verbose) {
      cat("Next block: ", parsed$block, "\n", sep = "")
      cat("Subtask: ", parsed$subtask, "\n\n", sep = "")
    }

    # Get block constructor
    block_ctor <- tryCatch(
      get_block_ctor(parsed$block),
      error = function(e) {
        if (verbose) cat("Unknown block:", parsed$block, "\n")
        NULL
      }
    )

    if (is.null(block_ctor)) {
      break
    }

    # Discover args for this step
    if (verbose) cat("Discovering arguments for ", parsed$block, "...\n\n", sep = "")

    step_result <- discover_block_args(
      prompt = parsed$subtask,
      data = current_data,
      block_ctor = block_ctor,
      block_name = paste0("new_", parsed$block),
      model = model,
      verbose = verbose
    )
    total_iterations <- total_iterations + step_result$iterations

    if (!step_result$success) {
      if (verbose) cat("Failed to discover args for this step.\n")
      break
    }

    # Store step in chain
    chain[[step]] <- list(
      block = parsed$block,
      subtask = parsed$subtask,
      args = step_result$args,
      result = step_result$result
    )

    # Update current data for next step
    current_data <- step_result$result

    if (verbose) {
      cat("\nStep ", step, " complete. Result: ",
          nrow(current_data), " rows x ", ncol(current_data), " cols\n\n", sep = "")
    }
  }

  duration <- as.numeric(difftime(Sys.time(), start_time, units = "secs"))
  success <- length(chain) > 0

  if (verbose) {
    cat(strrep("=", 70), "\n")
    cat("Chain discovery complete!\n")
    cat("  Steps: ", length(chain), "\n", sep = "")
    cat("  Total LLM calls: ", total_iterations, "\n", sep = "")
    cat("  Duration: ", round(duration, 1), "s\n", sep = "")
    cat("  Success: ", success, "\n", sep = "")
    cat(strrep("=", 70), "\n")
  }

  list(
    result = current_data,
    success = success,
    chain = chain,
    iterations = total_iterations,
    duration_secs = duration
  )
}


#' Build system prompt for chain discovery
#'
#' @param blocks_prompt Formatted block descriptions
#' @return Character string
#' @noRd
build_chain_system_prompt <- function(blocks_prompt) {
  paste0(
    "You are helping solve a data transformation task using blockr blocks.\n\n",
    "You will work step-by-step. For each step, you will:\n",
    "1. See the current data and what's been done so far\n",
    "2. Decide what block to use next\n",
    "3. Describe what that step should do\n\n",
    "IMPORTANT: Carefully check if ALL parts of the original task are complete.\n",
    "For example, if the task says 'filter, THEN calculate mean', you need BOTH steps.\n",
    "Only respond with DONE when every part of the task has been addressed.\n\n",
    "If more work is needed, respond with:\n",
    "BLOCK: <block_name>\n",
    "SUBTASK: <description of what this step should accomplish>\n\n",
    "Only when the ENTIRE task is complete, respond with just: DONE\n\n",
    blocks_prompt
  )
}


#' Parse LLM response for next step
#'
#' @param response LLM response text
#' @return List with block and subtask, or NULL if can't parse
#' @noRd
parse_next_step_response <- function(response) {
  # Look for BLOCK: and SUBTASK: patterns
  block_match <- regmatches(
    response,
    regexpr("BLOCK:\\s*([a-z_]+)", response, ignore.case = TRUE)
  )
  subtask_match <- regmatches(
    response,
    regexpr("SUBTASK:\\s*([^\n]+)", response, ignore.case = TRUE)
  )

  if (length(block_match) == 0 || length(subtask_match) == 0) {
    # Try alternative parsing - look for block name mentioned
    blocks <- names(get_dplyr_block_info())
    for (block in blocks) {
      if (grepl(block, response, ignore.case = TRUE)) {
        # Found a block name, try to extract subtask
        return(list(
          block = block,
          subtask = response  # Use whole response as subtask
        ))
      }
    }
    return(NULL)
  }

  block <- gsub("BLOCK:\\s*", "", block_match, ignore.case = TRUE)
  subtask <- gsub("SUBTASK:\\s*", "", subtask_match, ignore.case = TRUE)

  # Normalize block name
  block <- gsub("new_", "", block)
  block <- gsub("_block$", "_block", block)
  if (!grepl("_block$", block)) {
    block <- paste0(block, "_block")
  }

  list(
    block = block,
    subtask = subtask
  )
}
