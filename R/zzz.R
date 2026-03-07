utils::globalVariables("session")

register_ai_blocks <- function() {
  register_blocks(
    "new_llm_insights_block",
    name = "LLM insights block",
    description = paste(
      "Generate markdown insights about data using LLM based on natural",
      "language questions"
    ),
    category = "transform",
    package = utils::packageName(),
    overwrite = TRUE
  )
}

.onLoad <- function(libname, pkgname) { # nocov start

  register_ai_blocks()

  styler::cache_clear(ask = FALSE)

  invisible(NULL)
} # nocov end
