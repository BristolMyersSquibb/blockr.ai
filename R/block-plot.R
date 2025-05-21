#' @rdname new_llm_block
#' @export
new_llm_plot_block <- function(...) {
  new_llm_block("llm_plot_block", ...)
}

#' @export
block_ui.llm_plot_block <- function(id, x, ...) {
  tagList(
    plotOutput(NS(id, "result"))
  )
}

#' @export
block_output.llm_plot_block <- function(x, result, session) {
  renderPlot(result)
}
