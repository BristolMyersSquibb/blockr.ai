#' Discover Block Arguments via LLM
#'
#' Uses an LLM to discover block arguments from a natural language prompt.
#' The function iteratively queries the LLM, validates responses, and
#' refines until successful or max iterations reached.
#'
#' @param prompt User prompt describing what they want (e.g., "setosa only")
#' @param block A block object (e.g., `new_filter_block()`).
#' @param data Input data (data.frame, dm, or NULL for source blocks)
#' @param validate Validation function. If NULL, uses standalone validator
#'   with testServer (for testing outside of Shiny).
#' @param max_iter Maximum LLM iterations (default 5)
#' @param verbose If TRUE, print conversation to console
#' @param client An existing ellmer chat client to reuse. When NULL (default),
#'   a new client is created. Pass a persistent client to retain conversation
#'   memory across multiple calls.
#' @param current_state Optional plain list of current block parameter values.
#'   When non-NULL, a "Current Configuration" section is included in the user
#'   message so the LLM can see what's already configured.
#' @param data_exploration Data exploration strategy passed to
#'   [data_exploration_backend()]. Defaults to
#'   `blockr.core::blockr_option("data_exploration", "manual")`.
#' @param reporter A progress reporter list (see [reporter_silent],
#'   [reporter_console], [reporter_shiny]). When NULL (default), auto-detects:
#'   console if interactive, silent otherwise.
#' @param images Optional list of base64-encoded images to include with the
#'   first prompt.
#'
#' @return List with:
#'   \item{success}{TRUE if args were discovered successfully}
#'   \item{args}{List of discovered arguments}
#'   \item{result}{The resulting object: data.frame, dm, ggplot, etc. (if successful)}
#'   \item{error}{Error message (if failed)}
#'   \item{conversation}{List of message exchanges (if verbose)}
#'   \item{client}{The ellmer chat client (R6). Pass to subsequent calls to
#'     retain conversation memory.}
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
#' # Conversation memory: pass result$client to follow-up calls
#' r1 <- discover_block_args("use iris", new_dataset_block())
#' r2 <- discover_block_args("now mtcars", new_dataset_block(),
#'   client = r1$client)
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
    verbose = FALSE,
    client = NULL,
    current_state = NULL,
    data_exploration = blockr.core::blockr_option("data_exploration", "manual"),
    reporter = NULL,
    images = NULL
) {
  if (is.null(reporter)) reporter <- auto_reporter()

  # Get all constructor input names for the LLM prompt
  var_names <- block_ctor_inputs(block)

  if (length(var_names) == 0) {
    return(list(
      success = FALSE,
      args = NULL,
      conversation = NULL,
      result = NULL,
      error = "Block has no configurable parameters"
    ))
  }

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

  block_name <- class(block)[1]

  backend <- data_exploration_backend(data_exploration)

  # Create new client only if none provided; reuse existing for conversation memory
  if (is.null(client)) {
    client <- llm_client()
    # Let backend modify client (register tools) and append to system prompt
    prompt_addition <- if (!is.null(data)) backend$setup(client, data)
    system_prompt <- build_system_prompt(var_names, block, prompt_addition)
    client$set_system_prompt(system_prompt)
    log_msg("system", system_prompt)
  }

  state_json <- if (!is.null(current_state) && length(current_state) > 0) {
    jsonlite::toJSON(current_state, auto_unbox = TRUE)
  }
  message("[discover] ", block_name,
          " | prompt: ", prompt,
          if (!is.null(state_json)) paste0(" | state: ", state_json) else "")

  # Build initial message
  msg <- build_user_prompt(prompt, data, current_state)

  last_error <- NULL
  final_args <- NULL
  final_result <- NULL
  prev_args <- NULL
  last_message <- NULL

  for (i in seq_len(max_iter)) {
    log_msg("user", msg)
    message("[discover] \u2192 ", truncate_for_log(msg))

    # 1st turn, thinking phase
    if (i == 1L) {
      reporter$start_phase("thinking")
      # empty if images has length 0
      img_contents <- lapply(images, function(img) {
          ellmer::ContentImageInline(type = img$type, data = img$data)
      })
      response <- try(client$chat(msg, !!!img_contents))
      reporter$end_phase("thinking")
    } else {
      # any other round
      response <- try(client$chat(msg))
    }

    response_type <- categorize_response(response)

    if (response_type == "llm_error") {
      e <- attr(response, "condition")
      message("[discover] LLM error: ", conditionMessage(e))
      last_error <- paste0("LLM error: ", conditionMessage(e))
      break
    }

    log_msg("assistant", response)
    message("[discover] \u2190 ", truncate_for_log(response))

    if (response_type == "done") {
      reporter$end_phase("confirming", result = "\u2713")
      break
    }

    # Let backend handle data exploration requests
    reporter$start_phase("exploring")
    if (response_type == "data_query") {
      # extract R code, run it, format the output
      msg <- backend$process(response, data)
      next
    }
    reporter$end_phase("exploring")

    if (response_type == "clarifying_question") {
      # LLM is asking a clarifying question — return it to the caller
      return(list(
        success = FALSE,
        args = final_args,
        conversation = conversation,
        result = final_result,
        error = NULL,
        question = response,
        client = client
      ))
    }

    # All other response types have been handled
    # We have a result candidate that still needs to be parsed and validated
    stopifnot(response_type == "result_candidate")
    json_str <- extract_json(response)
    # Simplify leaf lists (all-scalar) to vectors so they work as
    # column subscripts and other places expecting atomic vectors.
    new_args <- try(jsonlite::fromJSON(json_str, simplifyVector = FALSE))
    if (inherits(new_args, "try-error")) {
      last_error <- conditionMessage(attr(new_args, "condition"))
      msg <- paste0("Error: ", last_error)
      next
    }
    new_args <- simplify_leaves(new_args)
    if (!is.list(new_args)) {
      last_error <- "Invalid JSON"
      msg <- "Error: Invalid JSON"
      next
    }


    message("[discover] args: ", jsonlite::toJSON(new_args, auto_unbox = TRUE))

    # Detect identical args sent twice — LLM is stuck, accept current result
    if (!is.null(prev_args) && identical(new_args, prev_args) &&
        !is.null(final_result)) {
      message("[discover] identical args repeated, accepting result")
      last_error <- NULL
      break
    }
    prev_args <- new_args

    # Validate using provided function
    reporter$start_phase("validating")
    result <- try({validate(new_args)})
    if (inherits(result, "try-error")) {
      last_error <- conditionMessage(attr(result, "condition"))
      reporter$end_phase("validating")
      reporter$start_phase("retrying", detail = last_error)
      message("[discover] validation failed: ", last_error)
      msg <- paste0("Validation failed: ", last_error, "\nPlease fix.")
      next
    }
    reporter$end_phase("validating", result = "\u2713")

    # Success - ask for confirmation
    final_args <- new_args
    final_result <- result
    last_message <- strip_json_block(response)
    preview <- data_schema(result)
    message("[discover] validated: ", truncate_for_log(preview))
    reporter$start_phase("confirming")
    msg <- paste0("Result:\n```\n", preview, "\n```\nCorrect? Say DONE or fix.")
    last_error <- NULL
    }

  message("[discover] done, success: ", is.null(last_error))
  reporter$done(is.null(last_error), last_error)

  list(
    success = is.null(last_error),
    args = final_args,
    conversation = conversation,
    result = final_result,
    error = last_error,
    message = last_message,
    client = client
  )
}

categorize_response <- function(response, exploration_format) {
  llm_chat_query_failed <- inherits(response, "try-error")
  if (llm_chat_query_failed) {
    return("llm_error")
  }

  if (is_done_response(response)) {
    return("done")
  }

  response_has_data_query_code_block <-
    grepl("```data_query\\s*\\n([\\s\\S]*?)\\n```", response)
  if (response_has_data_query_code_block) {
    return("data_query")
  }

  # not used at time of writing because no way to set `structured = TRUE`
  if (response_is_structured_exploration_query(response)) {
    return("json_query")
  }

  response_has_json_or_curly_braces <- 
    grepl("```(?:json)?\\s*\\n([\\s\\S]*?)\\n```", response, perl = TRUE) ||
    grepl("^\\s*\\{", response)
  if (response_has_json_or_curly_braces) {
    return("result_candidate")
  }
  
  # if not any of the above, we assume it's a clarification question
  "clarifying_question"
}

response_is_structured_exploration_query <- function(response) {
  # A structured exploration query is a response that contains parsable json with an
  # "action" : "explore" element and non empty code
  json_str <- extract_json(response)
  if (is.null(json_str)) return(FALSE)
  parsed <- try(jsonlite::fromJSON(json_str, simplifyVector = FALSE))
  if (inherits(parsed, "try-error")) return(FALSE)

  # Only handle exploration requests; answer JSON (no action field) falls
  # through to the main loop's extract_json() + validation.
  if (!identical(parsed$action, "explore")) return(FALSE)

  code <- parsed$code
  if (is.null(code) || !nzchar(trimws(code))) return(FALSE)
  TRUE
}


# Recursively simplify leaf lists to atomic vectors.
# A "leaf list" is a list where every element is a scalar (length-1 atomic).
# Named lists (JSON objects) always recurse — only unnamed lists (JSON arrays)
# are collapsed to vectors. This preserves the top-level dict structure for
# single-parameter blocks like function_block ({"fn": "..."}).
simplify_leaves <- function(x) {
  if (!is.list(x)) return(x)
  # Named lists: always recurse into children (never collapse the dict itself)
  if (!is.null(names(x))) {
    return(lapply(x, simplify_leaves))
  }
  # Unnamed lists where every element is scalar atomic: collapse to vector
  if (length(x) > 0 && all(vapply(x, function(el) {
    is.atomic(el) && length(el) == 1L
  }, logical(1)))) {
    return(unlist(x, use.names = FALSE))
  }
  x
}


# Get constructor input names from a block (excluding ...)
block_ctor_inputs <- function(x) {
  ctor <- attr(x, "ctor")
  if (is.null(ctor)) return(character())
  setdiff(names(formals(ctor)), "...")
}


# Internal validator factory - takes constructor function
standalone_validator_internal <- function(ctor, data) {
  # Build a package-qualified call (do.call breaks blockr.core's resolve_ctor
  # which walks the call stack to detect `::`).
  ctor_fun_name <- attr(ctor, "fun")
  ctor_pkg_name <- attr(ctor, "pkg")

  function(args) {
    if (!is.null(ctor_pkg_name)) {
      # Build pkg::fun(...) call so resolve_ctor can detect the package
      fn_call <- call("::", as.symbol(ctor_pkg_name), as.symbol(ctor_fun_name))
      call_expr <- as.call(c(list(fn_call), args))
    } else {
      call_expr <- as.call(c(list(as.symbol(ctor_fun_name)), args))
    }
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
      blockr.core::get_s3_method("block_server", test_block),
      {
        session$flushReact()
        result <<- session$returned$result()
      },
      args = server_args
    )

    if (is.null(result)) {
      stop("Block evaluation returned NULL")
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
