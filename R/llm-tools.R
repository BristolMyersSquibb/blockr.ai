#' LLM tools
#'
#' Tools can be made available to LLMs in order to make them more powerful and
#' in turn enabling them to create more accurate results.
#'
#' @param ... Passed to [ellmer::tool()].
#' @param prompt A string with additional prompts that will be added to the
#' system prompt.
#'
#' @return All blocks constructed via `new_llm_tool()` inherit from
#' `llm_tool`.
#'
#' @export
new_llm_tool <- function(..., prompt = character()) {
  structure(
    list(tool = ellmer::tool(...), prompt = prompt),
    class = "llm_tool"
  )
}

#' @param x Object
#' @rdname new_llm_tool
#' @export
is_llm_tool <- function(x) inherits(x, "llm_tool")

#' @rdname new_llm_tool
#' @export
get_tool <- function(x) {
  stopifnot(is_llm_tool(x))
  x[["tool"]]
}

#' @rdname new_llm_tool
#' @export
get_prompt <- function(x) {
  stopifnot(is_llm_tool(x))
  x[["prompt"]]
}

#' @rdname new_llm_tool
#' @export
llm_tools <- function(x, ...) {
  UseMethod("llm_tools", x)
}

#' @rdname new_llm_tool
#' @export
llm_tools.llm_block_proxy <- function(x, ...) {
  blockr_option(
    "llm_tools",
    list(
      new_eval_tool(x, ...),
      new_help_tool(x, ...)
    )
  )
}
