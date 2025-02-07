#' LLM Transform block constructor
#'
#' This block allows for transforming data using LLM-generated R code based on natural language questions
#'
#' @param question Initial question (optional)
#' @param code Initial code (optional)
#' @param store Whether to store and reuse previous LLM response
#' @param max_retries Maximum number of retries for code execution
#' @param ... Forwarded to [new_block()]
#'
#' @export
new_llm_transform_block <- function(question = character(),
                                    code = character(),
                                    store = FALSE,
                                    max_retries = 3,
                                    ...) {

  # change environment so server and ui have access to arguments
  environment(transform_block_server) <- environment()
  environment(transform_block_ui) <- environment()
  new_transform_block(
    server = transform_block_server,
    ui = transform_block_ui,
    class = "llm_transform_block",
    ...
  )
}
