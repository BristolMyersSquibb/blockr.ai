#' @rdname new_llm_block
#' @export
new_llm_transform_block <- function(...) {
  new_llm_block(c("llm_transform_block", "transform_block"), ...)
}

#' @export
result_ptype.llm_transform_block_proxy <- function(x) {
  data.frame()
}

#' @rdname system_prompt
#' @export
system_prompt.llm_transform_block_proxy <- function(x, datasets, ...) {

  paste0(
    NextMethod(),
    "\n\n",
    "Your task is to transform input datasets into a single output dataset.\n",
    "If possible, use dplyr for data transformations.\n\n",
    "IMPORTANT SYNTAX RULES:\n",
    "- Use the base R pipe |> and NEVER use %>% (magrittr pipe is not available)\n",
    "- Always use namespace prefixes like dplyr::n(), dplyr::filter(), dplyr::mutate(), etc.\n\n",
    "Example of good code:\n",
    "data |>\n",
    "  dplyr::group_by(category) |>\n",
    "  dplyr::summarize(\n",
    "    count = dplyr::n(),\n",
    "    mean_value = mean(value)\n",
    "  )\n\n",
    "Important: make sure that your code always returns a transformed ",
    "data.frame or tibble.\n"
  )
}
