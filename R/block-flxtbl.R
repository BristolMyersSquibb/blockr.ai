#' @rdname new_llm_block
#' @export
new_llm_flxtbl_block <- function(...) {
  new_llm_block("llm_flxtbl_block", ...)
}

#' @export
block_ui.llm_flxtbl_block <- function(id, x, ...) {
  tagList(
    uiOutput(NS(id, "result"))
  )
}

#' @export
block_output.llm_flxtbl_block <- function(x, result, session) {
  renderUI(flextable::htmltools_value(result))
}

#' @export
result_ptype.llm_flxtbl_block_proxy <- function(x) {
  flextable::flextable(data.frame(a = 1))
}
