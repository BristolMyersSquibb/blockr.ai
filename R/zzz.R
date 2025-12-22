register_ai_blocks <- function() {
  register_blocks(
    c(
      "new_llm_transform_block",
      "new_llm_plot_block",
      "new_llm_gt_block",
      "new_llm_flxtbl_block",
      "new_llm_insights_block",
      "new_llm_data_block",
      "new_filter_block"
    ),
    name = c(
      "LLM transform block",
      "LLM plot block",
      "LLM gt block",
      "LLM flextable block",
      "LLM insights block",
      "LLM data block",
      "Filter block (AI)"
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
        "Generate markdown insights about data using LLM based on natural",
        "language questions"
      ),
      paste(
        "Generate data using LLM-generated R code based on natural language",
        "questions"
      ),
      paste(
        "Filter rows by selecting values from columns with AI assistance",
        "for natural language configuration"
      )
    ),
    category = c(
      "transform",
      "plot",
      "table",
      "table",
      "transform",
      "input",
      "transform"
    ),
    package = utils::packageName(),
    overwrite = TRUE
  )
}

.onLoad <- function(libname, pkgname) { # nocov start

  register_ai_blocks()

  styler::cache_clear(ask = FALSE)

  invisible(NULL)
} # nocov end
