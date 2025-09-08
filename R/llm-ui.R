#' @rdname new_llm_block
#' @export
llm_block_ui <- function(x) {
  UseMethod("llm_block_ui", x)
}

#' @rdname new_llm_block
#' @export
llm_block_ui.llm_block_proxy <- function(x) {

  function(id) {

    msg <- x[["messages"]]

    if (is_question(msg)) {
      msg <- NULL
    }

    chat <- shinychat::chat_ui(
      NS(id, "chat"),
      width = "100%",
      style = "max-height: 400px; overflow-y: auto;",
      messages = msg
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

is_question <- function(x) {
  is.character(x) ||
    inherits(x, "shiny.tag.list") || inherits(x, "shiny.tag") ||
    (
      is.list(x) && (
        (
          setequal(names(x), c("content", "role")) &&
            x[["role"]] == "user"
        ) || (
          length(x) == 1L && setequal(names(x[[1L]]), c("content", "role")) &&
            x[[1L]][["role"]] == "user"
        )
      )
    )
}
