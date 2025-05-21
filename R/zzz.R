register_ai_blocks <- function() {
  register_blocks(
    c(
      "new_llm_transform_block",
      "new_llm_plot_block"
    ),
    name = c(
      "LLM transform block",
      "LLM plot block"
    ),
    description = c(
      "Transform data using LLM-generated R code based on natural language questions",
      "Create plots using LLM-generated R code based on natural language questions"
    ),
    category = c(
      "transform",
      "plot"
    ),
    package = utils::packageName(),
    overwrite = TRUE
  )
}

.onLoad <- function(libname, pkgname) { # nocov start

  register_ai_blocks()

  invisible(NULL)
} # nocov end
