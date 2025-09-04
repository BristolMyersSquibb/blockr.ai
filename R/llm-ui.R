#' @rdname new_llm_block
#' @export
llm_block_ui <- function(x) {
  UseMethod("llm_block_ui", x)
}

#' @rdname new_llm_block
#' @export
llm_block_ui.llm_block_proxy <- function(x) {
  function(id) {
    bslib::accordion(
      multiple = TRUE,
      id = NS(id, "accordion"),
      bslib::accordion_panel(
        title = "Chat",
        shinychat::chat_ui(
          NS(id, "chat"),
          width = "100%",
          style = "max-height: 400px; overflow-y: auto;"
        )
      ),
      bslib::accordion_panel(
        title = "Code output",
        shinyAce::aceEditor(
          NS(id, "code_editor"),
          mode = "r",
          value = style_code(x[["code"]]),
          showPrintMargin = FALSE,
          height = "200px"
        )
      )
    )
  }
}
