#' LLM system prompts
#'
#' System prompts for instructing the LLM to return code using certain packages,
#' adhering to certain styles, etc. are created per LLM block class and a
#' corresponding S3 generic is available as `system_prompt()`, which is
#' dispatched on LLM block proxy objects.
#'
#' @param x LLM block proxy object
#' @param ... Generic consistency
#'
#' @return A string.
#'
#' @export
system_prompt <- function(x, ...) {
  UseMethod("system_prompt")
}

#' @rdname system_prompt
#' @export
system_prompt.default <- function(x, ...) {
  paste0(
    "You are an R programming assistant.\n",
    "Your task is to produce working R code according to user instructions.\n",
    "In addition, you should provide clear explanations to accompany the ",
    "generated R code.\n",
    "Important: If you call functions in packages, always use namespace ",
    "prefixes. Do not use library calls for attaching package namespaces.\n"
  )
}

#' @param datasets Data sets from which to extract metadata
#' @rdname system_prompt
#' @export
system_prompt.llm_block_proxy <- function(x, datasets, ...) {

  meta_builder <- blockr_option("make_meta_data", build_metadata_default)

  if (!is.function(meta_builder)) {
    meta_builder <- get(meta_builder, mode = "function")
  }

  metadata <- meta_builder(datasets)

  res <- paste0(
    NextMethod(),
    "\n\n",
    "You have the following dataset at your disposal: ",
    paste(shQuote(names(datasets)), collapse = ", "), ".\n",
    "These can be summarize in the following way:\n\n",
    paste0("* ", names(metadata), ": ", metadata),
    "\n\n",
    "Be very careful to use only the provided names in your explanations ",
    "and code.\n",
    "This means you should not use generic names of undefined datasets ",
    "like `x` or `data` unless these are explicitly provided.\n",
    "You should not produce code to rebuild the input objects.\n"
  )
}

#' @rdname system_prompt
#' @export
system_prompt.llm_transform_block_proxy <- function(x, datasets, ...) {

  paste0(
    NextMethod(),
    "\n\n",
    "Your task is to transform input datasets into a single output dataset.\n",
    "If possible, use dplyr for data transformations.\n",
    "Use the base R pipe and not the magrittr pipe to make nested function ",
    "calls more readable.\n\n",
    "Example of good code you might write:\n",
    "data |>\n",
    "  dplyr::group_by(category) |>\n",
    "  dplyr::summarize(mean_value = mean(value))\n\n",
    "Important: make sure that your code always returns a transformed ",
    "data.frame.\n"
  )
}

#' @rdname system_prompt
#' @export
system_prompt.llm_plot_block_proxy <- function(x, datasets, ...) {

  paste0(
    NextMethod(),
    "\n\n",
    "Your task is to produce code to generate a data visualization using ",
    "the ggplot package.\n",
    "Example of good code you might write:\n",
    "ggplot2::ggplot(data) +\n",
    "  ggplot2::geom_point(ggplot2::aes(x = displ, y = hwy)) +\n",
    "  ggplot2::facet_wrap(~ class, nrow = 2)\n\n",
    "Important: Your code must always return a ggplot2 plot object as the ",
    "last expression.\n"
  )
}

#' @rdname system_prompt
#' @export
system_prompt.llm_gt_block_proxy <- function(x, datasets, ...) {

  paste0(
    NextMethod(),
    "\n\n",
    "Your task is to produce code to generate a table using the gt package.\n",
    "Example of good code you might write:\n",
    "gt::gt(data) |>\n",
    "  gt::tab_header(\"",
    "    title = \"Some title\",",
    "    subtitle = \"Some subtitle\"",
    "  )\n\n",
    "Important: Your code must always return a gt object as the last ",
    "expression.\n"
  )
}

#' @rdname system_prompt
#' @export
system_prompt.llm_flxtbl_block_proxy <- function(x, datasets, ...) {

  paste0(
    NextMethod(),
    "\n\n",
    "Your task is to produce code to generate a table using the flextable ",
    "package.\n",
    "Example of good code you might write:\n",
    "head(airquality) |>\n",
    "  flextable::flextable() |>\n",
    "  flextable::add_header_row(\n",
    "    values = c(\"air quality\", \"time\"),\n",
    "    colwidths = c(4, 2)\n",
    "  ) |>\n",
    "  flextable::add_footer_lines(\n",
    "    \"Some footer note.\"\n",
    "  )\n\n",
    "Important: Your code must always return a flextable object as the last ",
    "expression.\n"
  )
}

#' @rdname system_prompt
#' @export
system_prompt.llm_gtsummary_block_proxy <- function(x, datasets, ...) {

  paste0(
    NextMethod(),
    "\n\n",
    "Your task is to create summary tables using the gtsummary package.\n",
    "Example of good code you might write:\n",
    "gtsummary::tbl_summary(data, by = group_var) |>\n",
    "  gtsummary::add_p() |>\n",
    "  gtsummary::add_overall()\n\n",
    "For regression tables:\n",
    "gtsummary::tbl_regression(model) |>\n",
    "  gtsummary::add_global_p()\n\n",
    "Important: Your code must always return a gtsummary object.\n"
  )
}

#' @rdname system_prompt
#' @export
system_prompt.llm_table_insights_block_proxy <- function(x, datasets, ...) {

  ascii_table <- if (length(datasets) > 0 && inherits(datasets[[1]], "gtsummary")) {
    huxtable::to_screen(gtsummary::as_hux_table(datasets[[1]]))
  } else if (length(datasets) > 0) {
    capture.output(print(datasets[[1]]))
  } else {
    "No table data provided"
  }

  paste0(
    "You are an expert clinical data analyst and statistician.\n",
    "Your task is to analyze and interpret the following table, providing:\n",
    "- Key clinical findings and statistical insights\n",
    "- Treatment effects and group comparisons\n",
    "- Statistical significance interpretation\n",
    "- Safety signals or notable patterns\n",
    "- Clinical implications\n\n",
    "**Table to analyze:**\n\n",
    ascii_table,
    "\n\n",
    "Provide your analysis in markdown format with clear sections and bullet points.\n",
    "Focus on clinically relevant insights rather than technical details.\n"
  )
}

build_metadata_default <- function(x) {
  lapply(x, build_metadata)
}

#' @export
build_metadata <- function(x, ...) {
  UseMethod("build_metadata")
}

#' @export
build_metadata.data.frame <- function(x) {
  paste0(
    "This data.frame contains columns with that can be created as:\n\n",
    "    ```r\n",
    paste0(
      "    ",
      format(constructive::construct_multi(lapply(x, vctrs::vec_ptype))$code),
      collapse = "\n"
    ),
    "\n    ```\n\n"
  )
}

#' @export
build_metadata.flextable <- function(x) {
  paste0(
    "This object is a flextable with columns ",
    paste(shQuote(x$col_keys), collapse = ", ")
  )
}

#' @export
build_metadata.default <- function(x) {
  paste0(
    "This object has class attributes ",
    paste(shQuote(class(x)), collapse = ", ")
  )
}
