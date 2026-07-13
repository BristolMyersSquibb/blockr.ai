# Progress Reporter for discover_block_args
#
# Proxy objects that the discovery loop calls at each phase.
# Three implementations: silent (benchmarks), console (interactive),
# shiny (live chat feedback via shinychat).
#
# In addition to the coarse phase callbacks (start_phase/end_phase/done), the
# reporter receives a `tool_event()` for every individual tool call the model
# makes (one per `data_tool` probe, one per `validate_config`). The Shiny
# reporter turns these into a stack of content-rich badges -- the tool's name
# plus a one-line summary of what it did (the R snippet it ran, or the effect
# the config had) -- so the user is notified of each step without the raw
# tool-call dump the default shinychat UI shows.


#' Progress reporter: silent
#'
#' No-op reporter for benchmarks and non-interactive use.
#' All callbacks are empty functions.
#'
#' @return A reporter list
#' @export
reporter_silent <- function() {
  list(
    start_phase  = function(phase, detail = NULL) {},
    update       = function(text) {},
    tool_event   = function(id, phase, label, summary = NULL, code = FALSE,
                            status = "active") {},
    end_phase    = function(phase, result = NULL) {},
    done         = function(success, message = NULL) {}
  )
}


#' Map a discovery phase to a human label.
#' @noRd
phase_label <- function(phase, detail = NULL) {
  label <- switch(phase,
    thinking   = "Analyzing",
    exploring  = "Exploring data",
    validating = "Applying configuration",
    confirming = "Checking result",
    retrying   = "Fixing",
    phase
  )
  if (!is.null(detail)) paste0(label, ": ", detail) else label
}


#' Progress reporter: console
#'
#' Prints formatted progress to stdout. Useful for interactive standalone
#' discovery and debugging.
#'
#' @return A reporter list
#' @export
reporter_console <- function() {
  list(
    start_phase = function(phase, detail = NULL) {
      cat(paste0("\u2192 ", phase_label(phase, detail), "...\n"))
    },
    update = function(text) {
      cat(paste0("  ", text, "\n"))
    },
    tool_event = function(id, phase, label, summary = NULL, code = FALSE,
                          status = "active") {
      # Only the resolved event is worth printing on the console (the request is
      # immediately followed by its result in the synchronous loop).
      if (identical(status, "active")) return(invisible())
      mark <- if (identical(status, "error")) "\u2717" else "\u2713"
      line <- paste0("  ", mark, " ", label)
      if (!is.null(summary) && nzchar(summary)) line <- paste0(line, " \u00b7 ", summary)
      cat(line, "\n")
    },
    end_phase = function(phase, result = NULL) {
      if (!is.null(result)) cat(paste0("  ", result, "\n"))
    },
    done = function(success, message = NULL) {
      if (success) {
        cat("\u2713 Done\n")
      } else {
        cat(paste0(
          "\u2717 Failed",
          if (!is.null(message)) paste0(": ", message),
          "\n"
        ))
      }
    }
  )
}


#' Progress reporter: Shiny
#'
#' Marker reporter for the live-board path. It carries the shinychat widget
#' identity (`$chat_sink`) so the harness renders the turn natively: the
#' tool cards and reply text of each exchange are rendered live into the
#' widget by `chat_with_cards()`, using shinychat's own tool-card UI. All
#' phase/tool callbacks are
#' therefore no-ops; per-tool display is defined where the tools are built
#' (see `extra$display` in `new_data_tool()` / `new_validate_tool()`).
#'
#' @param chat_id The shinychat chat widget ID (unnamespaced)
#' @param session The Shiny session
#' @return A reporter list with a `chat_sink` entry
#' @export
reporter_shiny <- function(chat_id, session) {
  rep <- reporter_silent()
  rep$chat_sink <- list(id = chat_id, session = session)
  rep
}


#' Auto-detect appropriate reporter
#'
#' Returns [reporter_console()] for interactive sessions,
#' [reporter_silent()] otherwise.
#'
#' @return A reporter list
#' @noRd
auto_reporter <- function() {
  if (interactive()) reporter_console() else reporter_silent()
}
