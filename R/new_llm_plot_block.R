#' LLM plot block constructor
#'
#' This block allows for plotting data using LLM-generated R code based on natural language questions
#'
#' @param question Initial question (optional)
#' @param code Initial code (optional)
#' @param max_retries Maximum number of retries for code execution
#' @param ... Forwarded to [new_block()]
#'
#' @export
#' @examples
#' \dontrun{
#' pkgload::load_all(); serve(new_llm_plot_block(), list(data = mtcars))
#' }
new_llm_plot_block <- function(question = "",
                               code = "",
                               max_retries = 3,
                               ...) {

  # change environment so server and ui have access to arguments
  environment(plot_block_server) <- environment()
  environment(plot_block_ui) <- environment()
  new_transform_block(
    server = plot_block_server,
    ui = plot_block_ui,
    class = "llm_plot_block",
    ...
  )
}
