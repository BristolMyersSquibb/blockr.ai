# Run Blocks Headlessly
#
# Utilities for running blockr blocks without a Shiny UI.


#' Run a block headlessly with given arguments
#'
#' Executes a blockr block using shiny::testServer, allowing you to test
#' blocks without launching a Shiny app.
#'
#' @param block_ctor Block constructor function (e.g., new_summarize_block)
#' @param data Input data (data.frame)
#' @param ... Arguments to pass to block constructor
#' @return List with:
#'   - result: The output data.frame (or NULL on error)
#'   - error: Error message if execution failed (or NULL on success)
#'   - block: The block object that was created
#'
#' @examples
#' \dontrun{
#' # Summarize iris by Species
#' result <- run_block_headless(
#'   block_ctor = blockr.dplyr::new_summarize_block,
#'   data = iris,
#'   summaries = list(count = list(func = "dplyr::n", col = "")),
#'   by = "Species"
#' )
#' print(result$result)
#' }
#'
#' @export
run_block_headless <- function(block_ctor, data, ...) {
  # Capture result from testServer
  result <- NULL
  error <- NULL
  block <- NULL
  conditions <- NULL

  tryCatch({
    # Create block with provided arguments
    block <- block_ctor(...)

    # Get the block_server method for this block
    server_fn <- blockr.core:::get_s3_method("block_server", block)

    # Run via testServer
    shiny::testServer(
      server_fn,
      {
        session$flushReact()

        # Get the result
        result <<- tryCatch(
          session$returned$result(),
          error = function(e) {
            error <<- conditionMessage(e)
            NULL
          }
        )

        # Also capture conditions from the block if available
        if (!is.null(session$returned$cond)) {
          conditions <<- tryCatch(
            list(
              error = session$returned$cond$error,
              warning = session$returned$cond$warning,
              message = session$returned$cond$message
            ),
            error = function(e) NULL
          )

          # If there's an error condition, capture it
          if (!is.null(conditions$error) && length(conditions$error) > 0) {
            error <<- paste(conditions$error, collapse = "\n")
          }
        }
      },
      args = list(
        x = block,
        data = list(data = function() data)
      )
    )
  }, error = function(e) {
    error <<- conditionMessage(e)
  })

  # Derive success status
  success <- !is.null(result) && is.data.frame(result)

  list(
    result = result,
    success = success,
    error = error,
    block = block,
    conditions = conditions
  )
}
