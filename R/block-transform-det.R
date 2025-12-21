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
  # Same prompt as harness experiment
  paste0(
    "You are an R code assistant. You write dplyr code to transform data.\n\n",
    "CRITICAL RULES:\n",
    "1. NEVER use library()\n",
    "2. ALWAYS prefix: dplyr::filter(), dplyr::mutate(), dplyr::n(), dplyr::case_when(), dplyr::dense_rank(), dplyr::lag(), etc.\n",
    "3. ALWAYS prefix: tidyr::pivot_wider(), tidyr::pivot_longer(), etc.\n",
    "4. Use |> not %>%\n",
    "5. Code must END with the data expression (no print(), no extra text)\n",
    "6. Wrap code in ```r ... ``` blocks\n\n",
    "After seeing results:\n",
    "- If correct: reply with ONLY the word DONE (outside code block, no code)\n",
    "- If wrong: provide fixed code in ```r ... ``` block\n"
  )
}
