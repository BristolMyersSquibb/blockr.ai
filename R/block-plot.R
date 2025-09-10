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

#' @export
result_ptype.llm_plot_block_proxy <- function(x) {
  ggplot2::ggplot()
}

#' @rdname system_prompt
#' @export
system_prompt.llm_plot_block_proxy <- function(x, datasets, ...) {

  paste0(
    NextMethod(),
    "\n\n",
    "Your task is to produce code to generate a data visualization using ",
    "the ggplot package.\n",
    "Example of good code you might write:\n",
    "ggplot2::ggplot(data) +\n",
    "  ggplot2::geom_point(ggplot2::aes(x = displ, y = hwy)) +\n",
    "  ggplot2::facet_wrap(~ class, nrow = 2)\n\n",
    "Important: Your code must always return a ggplot2 plot object as the ",
    "last expression.\n"
  )
}
