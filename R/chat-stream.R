# Native shinychat rendering for the discovery tool loop.
#
# The discovery harness is synchronous by design: the nudge loop inspects the
# completed reply before deciding whether to re-prompt, and the block server
# consumes the result right after the call. That rules out both of shinychat's
# streaming entry points inside a Shiny observer:
#
# * shinychat::chat_append() consumes an ellmer stream asynchronously and
#   returns a promise -- the result is not available synchronously.
# * A synchronous client$stream(stream = "content") generator DEADLOCKS inside
#   an observer: ellmer's streaming waits on curl socket activity via
#   later::later_fd(), but the observer already occupies the event loop, so
#   the generator never yields (verified: the same generator works headless).
#
# client$chat() does not have this problem, and ellmer's on_tool_request() /
# on_tool_result() callbacks fire DURING it -- from inside the observer.
# Shiny transmits custom messages immediately (only outputs wait for the
# flush), so a card appended from a callback paints in the browser while the
# model is still working. chat_with_cards() therefore keeps client$chat() and
# forwards each tool request/result through shinychat::contents_shinychat()
# -- the exact rendering path chat_append() uses -- as it happens: the user
# watches native tool cards arrive live, exactly like the old badge stack,
# and the reply text lands when the turn completes.

#' Run one chat exchange, rendering tool cards live into a shinychat widget.
#'
#' Opens a streaming assistant message, registers ellmer tool callbacks that
#' append a native pending card per tool request (hidden again when its
#' result card lands, as in shinychat's own stream consumer), runs
#' `client$chat()`, appends the final reply text, and closes the message.
#' The message is closed and the callbacks unregistered even when the chat
#' errors (the error propagates to the caller).
#'
#' @param client An ellmer chat client.
#' @param inputs List of inputs for `client$chat()` (message text, images).
#' @param chat_id The (unnamespaced) chat widget ID.
#' @param session The Shiny session.
#' @return The reply text, invisibly like `client$chat()` returns it.
#' @noRd
chat_with_cards <- function(client, inputs, chat_id, session) {

  append_chunk <- function(content, chunk = TRUE) {
    shinychat::chat_append_message(
      chat_id,
      list(role = "assistant", content = content),
      chunk = chunk,
      operation = "append",
      session = session
    )
  }

  # shinychat hides a tool's pending request card once its result arrives
  # (send_chat_action() is not exported; the envelope is the stable custom
  # message contract used by the shinychat front-end).
  hide_request <- function(request_id) {
    session$sendCustomMessage("shinyChatMessage", list(
      id = session$ns(chat_id),
      action = list(type = "hide_tool_request", requestId = request_id)
    ))
  }

  render <- function(content) {
    tryCatch(shinychat::contents_shinychat(content), error = function(e) NULL)
  }

  # Test/fake clients may not implement the tool-callback API; then only the
  # final text is rendered.
  unreg_req <- unreg_res <- function() invisible()
  if (is.function(client$on_tool_request) &&
      is.function(client$on_tool_result)) {
    unreg_req <- client$on_tool_request(function(request) {
      out <- render(request)
      if (!is.null(out)) append_chunk(out)
    })
    unreg_res <- client$on_tool_result(function(result) {
      req <- tryCatch(result@request, error = function(e) NULL)
      if (!is.null(req)) hide_request(req@id)
      out <- render(result)
      if (!is.null(out)) append_chunk(out)
    })
  }

  append_chunk("", chunk = "start")
  on.exit({
    tryCatch(unreg_req(), error = function(e) NULL)
    tryCatch(unreg_res(), error = function(e) NULL)
    append_chunk("", chunk = "end")
  }, add = TRUE)

  out <- do.call(client$chat, inputs)

  if (length(out) && any(nzchar(out))) {
    append_chunk(paste(out, collapse = ""))
  }

  out
}
