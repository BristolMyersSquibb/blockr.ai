#' @rdname new_llm_block
#' @export
llm_block_ui <- function(x) {
  UseMethod("llm_block_ui", x)
}

#' @rdname new_llm_block
#' @export
llm_block_ui.llm_block_proxy <- function(x) {

  function(id) {

    messages <- NULL

    expl <- x[["explanation"]]
    qest <- x[["question"]]

    if (length(expl) && nchar(expl)) {

      messages <- list(
        list(content = expl, role = "assistant")
      )

      if (length(qest) && nchar(qest)) {

        messages <- c(
          list(
            list(content = qest, role = "user")
          ),
          messages
        )
      }
    }

    chat <- shinychat::chat_ui(
      NS(id, "chat"),
      width = "100%",
      style = "max-height: 400px; overflow-y: auto;",
      messages = messages
    )

    code <- shinyAce::aceEditor(
      NS(id, "code_editor"),
      mode = "r",
      value = style_code(x[["code"]]),
      showPrintMargin = FALSE,
      height = "200px"
    )

    bslib::accordion(
      multiple = TRUE,
      id = NS(id, "accordion"),
      bslib::accordion_panel(title = "Chat", chat),
      bslib::accordion_panel(title = "Code output", code)
    )
  }
}
