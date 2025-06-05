register_ai_blocks <- function() {
  register_blocks(
    c(
      "new_llm_transform_block",
      "new_llm_plot_block",
      "new_llm_gt_block"
    ),
    name = c(
      "LLM transform block",
      "LLM plot block",
      "LLM table block"
    ),
    description = c(
      paste(
        "Transform data using LLM-generated R code based on natural language",
        "questions"
      ),
      paste(
        "Create plots using LLM-generated R code based on natural language",
        "questions"
      ),
      paste(
        "Create tables using LLM-generated R code based on natural language",
        "questions"
      )
    ),
    category = c(
      "transform",
      "plot",
      "table"
    ),
    package = utils::packageName(),
    overwrite = TRUE
  )
}

.onLoad <- function(libname, pkgname) { # nocov start

  register_ai_blocks()

  invisible(NULL)
} # nocov end
