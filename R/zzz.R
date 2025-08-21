register_ai_blocks <- function() {
  register_blocks(
    c(
      "new_llm_transform_block",
      "new_llm_plot_block",
      "new_llm_gt_block",
      "new_llm_flxtbl_block", 
      "new_llm_gtsummary_block"
    ),
    name = c(
      "LLM transform block",
      "LLM plot block",
      "LLM gt block",
      "LLM flextable block",
      "LLM gtsummary block"
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
        "Create gt tables using LLM-generated R code based on natural",
        "language questions"
      ),
      paste(
        "Create flextables using LLM-generated R code based on natural",
        "language questions"
      ),
      paste(
        "Create gtsummary tables using LLM-generated R code based on natural",
        "language questions"
      )
    ),
    category = c(
      "transform",
      "plot",
      "table",
      "table",
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
