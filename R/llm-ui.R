#' @rdname new_llm_block
#' @export
llm_block_ui <- function(x) {
  UseMethod("llm_block_ui", x)
}

#' @rdname new_llm_block
#' @export
llm_block_ui.llm_block_proxy <- function(x) {
  function(id) {
    tagList(
      shinychat::chat_ui(NS(id, "chat"), width = "100%"),
      shinyAce::aceEditor(
        NS(id, "code_editor"),
        mode = "r",
        value = style_code(x[["code"]]),
        showPrintMargin = FALSE,
        height = "200px"
      )
    )
  }
}
