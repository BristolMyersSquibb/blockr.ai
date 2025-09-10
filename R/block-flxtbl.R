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

#' @rdname system_prompt
#' @export
system_prompt.llm_flxtbl_block_proxy <- function(x, datasets, ...) {

  paste0(
    NextMethod(),
    "\n\n",
    "Your task is to produce code to generate a table using the flextable ",
    "package.\n",
    "Example of good code you might write:\n",
    "head(airquality) |>\n",
    "  flextable::flextable() |>\n",
    "  flextable::add_header_row(\n",
    "    values = c(\"air quality\", \"time\"),\n",
    "    colwidths = c(4, 2)\n",
    "  ) |>\n",
    "  flextable::add_footer_lines(\n",
    "    \"Some footer note.\"\n",
    "  )\n\n",
    "Important: Your code must always return a flextable object as the last ",
    "expression.\n"
  )
}
