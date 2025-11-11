register_ai_blocks <- function() {
  register_blocks(
    c(
      "new_llm_transform_block",
      "new_llm_plot_block",
      "new_llm_gt_block",
      "new_llm_flxtbl_block",
      "new_llm_insights_block",
      "new_llm_data_block"
    ),
    name = c(
      "LLM transform block",
      "LLM plot block",
      "LLM gt block",
      "LLM flextable block",
      "LLM insights block",
      "LLM data block"
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
      )
    ),
    category = c(
      "transform",
      "plot",
      "table",
      "table",
      "transform",
      "input"
    ),
    package = utils::packageName(),
    overwrite = TRUE
  )
}

.onLoad <- function(libname, pkgname) { # nocov start

  register_ai_blocks()
  need_llm_cfg_opts(TRUE)

  styler::cache_clear(ask = FALSE)

  invisible(NULL)
} # nocov end
