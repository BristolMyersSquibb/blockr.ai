# Progress Reporter for discover_block_args
#
# Proxy objects that the discovery loop calls at each phase.
# Three implementations: silent (benchmarks), console (interactive),
# shiny (live chat feedback via shinychat).

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
    end_phase    = function(phase, result = NULL) {},
    done         = function(success, message = NULL) {}
  )
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
      label <- switch(phase,
        thinking   = "Analyzing",
        exploring  = "Exploring data",
        validating = "Validating",
        confirming = "Checking result",
        retrying   = "Retrying",
        phase
      )
      if (!is.null(detail)) label <- paste0(label, ": ", detail)
      cat(paste0("\u2192 ", label, "...\n"))
    },
    update = function(text) {
      cat(paste0("  ", text, "\n"))
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
#' Uses shinychat's chunk protocol to show live progress in the chat widget.
#' Opens a single streaming assistant message and shows an ephemeral status
#' badge using `operation = "replace"`. Only the current active phase is
#' visible; completed phases disappear. When done, the entire status message
#' is cleared so only the final answer remains.
#'
#' @param chat_id The shinychat chat widget ID (namespaced)
#' @param session The Shiny session
#' @return A reporter list
#' @export
reporter_shiny <- function(chat_id, session) {
  streaming <- FALSE
  active_label <- NULL

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

  ensure_open <- function() {
    if (!streaming) {
      shinychat::chat_append_message(
        chat_id,
        list(role = "assistant", content = ""),
        chunk = "start",
        session = session
      )
      streaming <<- TRUE
    }
  }

  flush_and_close <- function() {
    if (streaming) {
      shinychat::chat_append_message(
        chat_id,
        list(role = "assistant", content = ""),
        chunk = "end",
        session = session
      )
      streaming <<- FALSE
    }
  }

  render <- function() {
    ensure_open()
    if (is.null(active_label)) {
      # Nothing active — mark as empty so CSS can hide the message bubble
      html <- shiny::tags$div(class = "blockr-ai-status blockr-ai-status-empty")
    } else {
      badge <- shiny::tags$span(
        class = "blockr-ai-status-badge is-active",
        shiny::tags$span(
          class = "blockr-ai-status-icon",
          shiny::tags$span(class = "spinner-border spinner-border-sm")
        ),
        active_label
      )
      html <- shiny::tags$div(class = "blockr-ai-status", badge)
    }
    shinychat::chat_append_message(
      chat_id,
      list(role = "assistant", content = html),
      chunk = TRUE,
      operation = "replace",
      session = session
    )
  }

  list(
    start_phase = function(phase, detail = NULL) {
      active_label <<- phase_label(phase, detail)
      render()
    },
    update = function(text) {},
    end_phase = function(phase, result = NULL) {
      active_label <<- NULL
      render()
    },
    done = function(success, message = NULL) {
      active_label <<- NULL
      if (streaming) render()
      flush_and_close()
    }
  )
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
