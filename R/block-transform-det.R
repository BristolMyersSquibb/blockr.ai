#' Deterministic LLM Transform Block
#'
#' Like [new_llm_transform_block()] but uses a deterministic loop instead of
#' tool-based communication. The system controls the flow:
#' 1. Show data preview upfront
#' 2. LLM writes code as plain text
#' 3. System runs code automatically
#' 4. Iterate until DONE or max iterations
#'
#' This approach is ~4x faster than the tool-based version while maintaining
#' the same reliability for well-defined transformation tasks.
#'
#' @inheritParams new_llm_transform_block
#' @return A block of class `llm_transform_block_det`
#'
#' @examples
#' \dontrun{
#' # Create a deterministic transform block
#' block <- new_llm_transform_block_det()
#'
#' # Use in a blockr board
#' board <- new_board(
#'   new_dataset_block(mtcars),
#'   block
#' )
#' }
#'
#' @export
new_llm_transform_block_det <- function(...) {
  new_llm_block_det(c("llm_transform_block_det", "transform_block"), ...)
}


#' @export
result_ptype.llm_transform_block_det_proxy <- function(x) {
  data.frame()
}


#' System prompt for deterministic transform blocks
#'
#' @param x Block proxy
#' @param datasets Named list of datasets
#' @return Character string with system prompt
#' @keywords internal
#' @export
system_prompt_det.llm_transform_block_det_proxy <- function(x, datasets) {
  paste0(
    "You are an R code assistant that transforms data using dplyr.\n\n",

    "IMPORTANT SYNTAX RULES:\n",
    "1. Always prefix dplyr functions: dplyr::filter(), dplyr::mutate(), ",
    "dplyr::group_by(), dplyr::summarize(), dplyr::select(), dplyr::arrange(), ",
    "dplyr::n(), etc.\n",
    "2. Always prefix tidyr functions: tidyr::pivot_wider(), tidyr::pivot_longer(), etc.\n",
    "3. Use the native pipe |> (NEVER use %>%, it is not available)\n",
    "4. For row-wise operations, use dplyr::across() instead of select(., ...)\n",
    "5. Use base::mean(), base::sum(), etc. inside dplyr verbs\n",
    "6. Your code must produce a data.frame or tibble as output\n",
    "7. Wrap your R code in ```r ... ``` markdown blocks\n\n",

    "When you see the result of your code:\n",
    "- If it looks correct, respond with just: DONE\n",
    "- If it needs fixing, provide corrected code in ```r ... ``` blocks\n\n",

    "Example of correct code:\n",
    "```r\n",
    "data |>\n",
    "  dplyr::group_by(category) |>\n",
    "  dplyr::summarize(\n",
    "    mean_value = base::mean(value, na.rm = TRUE),\n",
    "    count = dplyr::n(),\n",
    "    .groups = \"drop\"\n",
    "  ) |>\n",
    "  dplyr::arrange(category)\n",
    "```\n"
  )
}
