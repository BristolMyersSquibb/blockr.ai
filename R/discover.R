#' Discover Block Arguments via LLM
#'
#' Uses an LLM to discover block arguments from a natural language prompt.
#' The function iteratively queries the LLM, validates responses, and
#' refines until successful or max iterations reached.
#'
#' @param prompt User prompt describing what they want (e.g., "setosa only")
#' @param block A block object (e.g., `new_filter_block()`).
#' @param data Input data.frame (or NULL for source blocks like dataset_block)
#' @param validate Validation function. If NULL, uses standalone validator
#'   with testServer (for testing outside of Shiny).
#' @param max_iter Maximum LLM iterations (default 5)
#' @param verbose If TRUE, print conversation to console
#'
#' @return List with:
#'   \item{success}{TRUE if args were discovered successfully}
#'   \item{args}{List of discovered arguments}
#'   \item{result}{The resulting data.frame (if successful)}
#'   \item{error}{Error message (if failed)}
#'   \item{conversation}{List of message exchanges (if verbose)}
#'
#' @examples
#' \dontrun{
#' # Filter block
#' result <- discover_block_args(
#'   prompt = "setosa only",
#'   block = new_filter_block(),
#'   data = iris,
#'   verbose = TRUE
#' )
#' result$success
#' result$result
#'
#' # Dataset block (no input data)
#' result <- discover_block_args(
#'   prompt = "use mtcars",
#'   block = new_dataset_block()
#' )
#'
#' # Summarize block
#' result <- discover_block_args(
#'   prompt = "average sepal length by species",
#'   block = new_summarize_block(),
#'   data = iris
#' )
#' }
#'
#' @export
discover_block_args <- function(
    prompt,
    block,
    data = NULL,
    validate = NULL,
    max_iter = 5,
    verbose = FALSE
) {
  # Get controllable var_names from block's external_ctrl attribute
  var_names <- attr(block, "external_ctrl")

  # Create standalone validator if none provided
  if (is.null(validate)) {
    ctor <- attr(block, "ctor")
    validate <- standalone_validator_internal(ctor, data)
  }

  conversation <- if (verbose) list() else NULL
  log_msg <- function(role, content) {
    if (verbose) {
      conversation <<- c(conversation, list(list(role = role, content = content)))
      cat(sprintf("[%s] %s\n\n", toupper(role), substr(content, 1, 500)))
    }
  }

  client <- llm_client()
  system_prompt <- build_system_prompt(var_names, block)
  client$set_system_prompt(system_prompt)
  log_msg("system", system_prompt)

  # Build initial message
  msg <- paste0(
    data_preview(data),
    "# Task\n\n", prompt,
    "\n\nReturn JSON with parameter values."
  )

  last_error <- NULL
  final_args <- NULL
  final_result <- NULL

  for (i in seq_len(max_iter)) {
    log_msg("user", msg)

    response <- tryCatch(client$chat(msg), error = function(e) NULL)
    if (is.null(response)) {
      last_error <- "LLM error"
      break
    }

    log_msg("assistant", response)

    if (is_done_response(response)) break

    json_str <- extract_json(response)
    if (is.null(json_str)) {
      msg <- "No JSON found. Please return a JSON object like {\"param\": \"value\"}."
      next
    }

    # Parse JSON to get args
    new_args <- tryCatch({
      jsonlite::fromJSON(json_str, simplifyVector = FALSE)
    }, error = function(e) {
      last_error <<- conditionMessage(e)
      NULL
    })

    if (is.null(new_args) || !is.list(new_args)) {
      msg <- paste0("Error: ", last_error %||% "Invalid JSON")
      next
    }

    # Validate using provided function
    result <- tryCatch({
      validate(new_args)
    }, error = function(e) {
      last_error <<- conditionMessage(e)
      NULL
    })

    if (is.null(result) || !is.data.frame(result)) {
      msg <- paste0("Validation failed: ", last_error, "\nPlease fix.")
      next
    }

    # Success - ask for confirmation
    final_args <- new_args
    final_result <- result
    preview <- paste(utils::capture.output(print(utils::head(result, 3))),
                     collapse = "\n")
    msg <- paste0("Result:\n```\n", preview, "\n```\nCorrect? Say DONE or fix.")
    last_error <- NULL
  }

  list(
    success = is.null(last_error),
    args = final_args,
    conversation = conversation,
    result = final_result,
    error = last_error
  )
}


# Internal validator factory - takes constructor function
standalone_validator_internal <- function(ctor, data) {
  # Get constructor name for building calls (do.call breaks resolve_ctor)
  ctor_name <- as.name(attr(ctor, "fun"))

  function(args) {
    # Build call manually and eval (do.call breaks blockr.core's resolve_ctor)
    call_expr <- as.call(c(list(ctor_name), args))
    test_block <- eval(call_expr)

    result <- NULL

    # Determine if block needs data input (arity > 0)
    arity <- blockr.core::block_arity(test_block)
    server_args <- list(x = test_block)
    if (arity > 0) {
      server_args$data <- list(data = function() data)
    }

    # Use testServer to get proper reactive context
    shiny::testServer(
      blockr.core:::get_s3_method("block_server", test_block),
      {
        session$flushReact()
        result <<- session$returned$result()
      },
      args = server_args
    )

    if (is.null(result) || !is.data.frame(result)) {
      stop("Block evaluation did not return a data.frame")
    }

    result
  }
}


#' Print Conversation from Discovery Result
#'
#' Prints the full conversation history from a [discover_block_args()] result
#' in a readable format.
#'
#' @param x Result from [discover_block_args()] (must have been called with
#'   `verbose = TRUE`)
#'
#' @return Invisibly returns `x`
#'
#' @examples
#' \dontrun{
#' result <- discover_block_args(
#'   prompt = "setosa only",
#'   block = new_filter_block(),
#'   data = iris,
#'   verbose = TRUE
#' )
#' print_conversation(result)
#' }
#'
#' @export
print_conversation <- function(x) {
  if (!is.list(x) || is.null(x$conversation)) {
    stop("Expected result from discover_block_args()")
  }
  for (msg in x$conversation) {
    cat(sprintf("=== %s ===\n%s\n\n", toupper(msg$role), msg$content))
  }
  invisible(x)
}
