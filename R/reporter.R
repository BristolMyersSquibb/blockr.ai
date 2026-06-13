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
      cat(paste0("→ ", phase_label(phase, detail), "...\n"))
    },
    update = function(text) {
      cat(paste0("  ", text, "\n"))
    },
    tool_event = function(id, phase, label, summary = NULL, code = FALSE,
                          status = "active") {
      # Only the resolved event is worth printing on the console (the request is
      # immediately followed by its result in the synchronous loop).
      if (identical(status, "active")) return(invisible())
      mark <- if (identical(status, "error")) "✗" else "✓"
      line <- paste0("  ", mark, " ", label)
      if (!is.null(summary) && nzchar(summary)) line <- paste0(line, " · ", summary)
      cat(line, "\n")
    },
    end_phase = function(phase, result = NULL) {
      if (!is.null(result)) cat(paste0("  ", result, "\n"))
    },
    done = function(success, message = NULL) {
      if (success) {
        cat("✓ Done\n")
      } else {
        cat(paste0(
          "✗ Failed",
          if (!is.null(message)) paste0(": ", message),
          "\n"
        ))
      }
    }
  )
}


#' Bootstrap check icon (done state).
#' @noRd
blockr_ai_icon_check <- function() {
  paste0(
    '<svg width="11" height="11" viewBox="0 0 16 16" fill="currentColor" ',
    'xmlns="http://www.w3.org/2000/svg" aria-hidden="true">',
    '<path d="M12.736 3.97a.733.733 0 0 1 1.047 0c.286.289.29.756.01 ',
    '1.05L7.88 12.01a.733.733 0 0 1-1.065.02L3.217 8.384a.757.757 0 0 1 ',
    '0-1.06.733.733 0 0 1 1.047 0l3.052 3.093 5.4-6.425a.247.247 0 0 1 ',
    '.013-.014z"/></svg>'
  )
}

#' Bootstrap exclamation-triangle icon (error/retry state).
#' @noRd
blockr_ai_icon_warn <- function() {
  paste0(
    '<svg width="11" height="11" viewBox="0 0 16 16" fill="currentColor" ',
    'xmlns="http://www.w3.org/2000/svg" aria-hidden="true">',
    '<path d="M7.938 2.016A.13.13 0 0 1 8.002 2a.13.13 0 0 1 .063.016.146.146 ',
    '0 0 1 .054.057l6.857 11.667c.036.06.035.124.002.183a.163.163 0 0 1-.054.06',
    '.116.116 0 0 1-.066.017H1.146a.115.115 0 0 1-.066-.017.163.163 0 0 1-.054',
    '-.06.176.176 0 0 1 .002-.183L7.884 2.073a.147.147 0 0 1 .054-.057zm1.044',
    '-.45a1.13 1.13 0 0 0-1.96 0L.165 13.233c-.457.778.091 1.767.98 1.767h13.713',
    'c.889 0 1.438-.99.98-1.767z"/><path d="M7.002 12a1 1 0 1 1 2 0 1 1 0 0 1-2 ',
    '0M7.1 5.995a.905.905 0 1 1 1.8 0l-.35 3.507a.552.552 0 0 1-1.1 0z"/></svg>'
  )
}


#' Progress reporter: Shiny
#'
#' Uses shinychat's chunk protocol to show live progress in the chat widget.
#' Opens a single streaming assistant message and maintains an ordered *stack*
#' of badges: a transient "Analyzing" badge while the model reasons, plus one
#' content-rich badge per tool call (appended as each call fires -- option A).
#' Each tool badge shows the tool's action and a one-line summary (the R snippet
#' it ran, or the effect a config had). When the turn finishes the transient
#' phase badges are dropped and the tool-call trace is left persisted in the
#' transcript as a record of what the AI did.
#'
#' To switch to a single rolling badge (option B) instead of a stack, keep only
#' the most recent tool item in `upsert()` -- the event plumbing is identical.
#'
#' @param chat_id The shinychat chat widget ID (namespaced)
#' @param session The Shiny session
#' @return A reporter list
#' @export
reporter_shiny <- function(chat_id, session) {
  streaming <- FALSE
  items <- list()  # ordered badge specs: list(id, phase, label, summary, code, status)

  find_idx <- function(id) {
    which(vapply(items, function(x) identical(x$id, id), logical(1)))
  }
  upsert <- function(spec) {
    idx <- find_idx(spec$id)
    if (length(idx)) items[[idx[1]]] <<- spec else items[[length(items) + 1L]] <<- spec
  }
  remove_item <- function(id) {
    idx <- find_idx(id)
    if (length(idx)) items[[idx[1]]] <<- NULL
  }

  status_icon <- function(status) {
    inner <- switch(status,
      active = shiny::tags$span(class = "spinner-border spinner-border-sm"),
      error  = shiny::HTML(blockr_ai_icon_warn()),
      shiny::HTML(blockr_ai_icon_check())
    )
    shiny::tags$span(class = "blockr-ai-status-icon", inner)
  }

  badge_tag <- function(spec) {
    state_class <- switch(spec$status,
      active = "is-active",
      error  = "is-done is-error",
      "is-done"
    )
    children <- list(status_icon(spec$status), spec$label)
    if (!is.null(spec$summary) && nzchar(spec$summary)) {
      summ <- if (isTRUE(spec$code)) shiny::tags$code(spec$summary) else spec$summary
      children <- c(children, list(
        shiny::tags$span(class = "blockr-ai-status-sep", "·"),
        shiny::tags$span(class = "blockr-ai-status-summary", summ)
      ))
    }
    do.call(shiny::tags$span, c(
      list(class = paste("blockr-ai-status-badge", state_class,
                         paste0("phase-", spec$phase))),
      children
    ))
  }

  render_html <- function() {
    if (length(items) == 0L) {
      shiny::tags$div(class = "blockr-ai-status blockr-ai-status-empty")
    } else {
      do.call(shiny::tags$div, c(
        list(class = "blockr-ai-status blockr-ai-status-stack"),
        lapply(items, badge_tag)
      ))
    }
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

  push <- function(final = FALSE) {
    ensure_open()
    shinychat::chat_append_message(
      chat_id,
      list(role = "assistant", content = render_html()),
      chunk = if (final) "end" else TRUE,
      operation = "replace",
      session = session
    )
    if (final) streaming <<- FALSE
  }

  scroll_to_bottom <- function() {
    session$sendCustomMessage("blockr-scroll-chat", list(
      chatId = session$ns(chat_id)
    ))
  }

  list(
    start_phase = function(phase, detail = NULL) {
      upsert(list(id = paste0("__phase_", phase), phase = phase,
                  label = phase_label(phase, detail), summary = NULL,
                  code = FALSE, status = "active"))
      push()
      scroll_to_bottom()
    },
    update = function(text) {},
    tool_event = function(id, phase, label, summary = NULL, code = FALSE,
                          status = "active") {
      upsert(list(id = id, phase = phase, label = label, summary = summary,
                  code = code, status = status))
      push()
      scroll_to_bottom()
    },
    end_phase = function(phase, result = NULL) {
      remove_item(paste0("__phase_", phase))
      push()
    },
    done = function(success, message = NULL) {
      # Drop transient phase spinners; keep the tool-call trace persisted. Any
      # tool still flagged active (shouldn't happen in the synchronous loop) is
      # settled to done so nothing spins forever.
      for (it in items) {
        if (startsWith(it$id, "__phase_")) remove_item(it$id)
      }
      items <<- lapply(items, function(x) {
        if (identical(x$status, "active")) x$status <- "done"
        x
      })
      push(final = TRUE)
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
