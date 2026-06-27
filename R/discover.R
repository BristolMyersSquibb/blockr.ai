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
#' @param verbose If TRUE, print conversation to console
#' @param client An existing ellmer chat client to reuse. When NULL (default),
#'   a new client is created. Pass a persistent client to retain conversation
#'   memory across multiple calls.
#' @param current_state Optional plain list of current block parameter values.
#'   When non-NULL, a "Current Configuration" section is included in the user
#'   message so the LLM can see what's already configured.
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
    verbose = FALSE,
    client = NULL,
    current_state = NULL,
    reporter = NULL,
    images = NULL
) {
  if (is.null(reporter)) reporter <- auto_reporter()
  discover_via_ellmer_tools(
    prompt = prompt, block = block, data = data, validate = validate,
    client = client, current_state = current_state, reporter = reporter,
    images = images, verbose = verbose
  )
}


# Recursively simplify leaf lists to atomic vectors.
# A "leaf list" is a list where every element is a scalar (length-1 atomic).
# Named lists (JSON objects) always recurse -- only unnamed lists (JSON arrays)
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
    block_errs <- character()

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
        # A block that errors evaluating its expr returns a NULL result and
        # stashes the real condition in `cond` -- capture it so the model gets
        # the actual error ("column X doesn't exist") instead of a blank NULL.
        block_errs <<- collect_block_errors(session$returned$cond)
      },
      args = server_args
    )

    if (is.null(result)) {
      if (length(block_errs)) {
        stop("Block evaluation failed: ",
             paste(unique(block_errs), collapse = " | "))
      }
      # No condition was raised -- the code ran but produced NULL. Tell the model
      # what to check instead of a content-free "returned NULL".
      stop("Block evaluation produced no result: the code ran without error but ",
           "returned NULL. Make sure the function returns its result object (the ",
           "data frame, table, or plot as the last expression), and that ",
           "parameter defaults do not reduce the output to nothing.")
    }

    result
  }
}

#' Pull error messages out of a block's `cond`.
#'
#' `session$returned$cond` is a REACTIVE, so it must be called to get a value;
#' the current blockr.core shape is a data frame of conditions with `phase`,
#' `severity` and `message` columns (one row per condition). An older shape -- a
#' list / reactiveValues of stages each with an `$error` list -- is still
#' handled as a fallback. Returns the messages of the error/fatal conditions.
#' @noRd
collect_block_errors <- function(cond) {
  # `cond` may be the reactive itself (call it) or an already-resolved value.
  if (is.function(cond)) {
    cond <- tryCatch(cond(), error = function(e) NULL)
  }
  if (is.null(cond)) return(character())

  trim <- function(x) unique(gsub("\\s+", " ", substr(x[nzchar(x)], 1, 400)))

  # Current shape: a data frame of conditions.
  if (is.data.frame(cond)) {
    if (!nrow(cond) || !all(c("severity", "message") %in% names(cond))) {
      return(character())
    }
    return(trim(as.character(cond$message[cond$severity %in% c("error", "fatal")])))
  }

  # Legacy shape: stages, each with an `$error` list. blockr `block_cnd` errors
  # are classed character vectors, so conditionMessage() may have no method --
  # fall back to the raw character content.
  msgs <- character()
  for (st in tryCatch(names(cond), error = function(e) character())) {
    errs <- tryCatch(cond[[st]]$error, error = function(e) NULL)
    for (e in errs) {
      m <- tryCatch(conditionMessage(e),
                    error = function(x) paste(as.character(e), collapse = " "))
      if (length(m) && any(nzchar(m))) msgs <- c(msgs, trim(paste(m, collapse = " ")))
    }
  }
  unique(msgs)
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
