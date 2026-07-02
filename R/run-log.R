# Persistent, structured record of discover runs. Every ad-hoc debugging
# session so far has reconstructed this dataset by hand (report files, console
# scrollback); logging it at the source makes recurring error signatures
# minable and turns any interesting live failure into an eval case.

#' Append one JSON line describing a discover run to the configured log
#'
#' Gated on `blockr_option("ai_run_log", "")` (option `blockr.ai_run_log` /
#' env `BLOCKR_AI_RUN_LOG`): the path of a JSONL file to append to. Off by
#' default; never throws -- telemetry must not be able to break discovery.
#'
#' @param block Block class name (character).
#' @param prompt The user prompt.
#' @param result The discover result list (`success`, `noop`, `effect`,
#'   `error`, `question`).
#' @param nudges Number of apply-nudges the harness issued.
#' @param probes Number of data-tool probes used (NULL when no data tool).
#' @return TRUE if a line was written, FALSE otherwise (invisibly).
#' @noRd
log_discover_run <- function(block, prompt, result, nudges = 0L, probes = NULL) {
  path <- tryCatch(
    blockr.core::blockr_option("ai_run_log", ""),
    error = function(e) ""
  )
  if (!is.character(path) || length(path) != 1L || !nzchar(path)) {
    return(invisible(FALSE))
  }
  tryCatch({
    entry <- list(
      ts = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"),
      block = block,
      prompt = prompt,
      success = isTRUE(result$success),
      noop = isTRUE(result$noop),
      effect = result$effect,
      error = result$error,
      question = !is.null(result$question),
      nudges = nudges,
      probes = probes
    )
    dir.create(dirname(path), showWarnings = FALSE, recursive = TRUE)
    con <- file(path, open = "a", encoding = "UTF-8")
    on.exit(close(con), add = TRUE)
    writeLines(jsonlite::toJSON(entry, auto_unbox = TRUE, null = "null"), con)
    invisible(TRUE)
  }, error = function(e) invisible(FALSE))
}
