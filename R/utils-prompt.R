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
#' @param has_image Whether an image has been uploaded (optional)
#' @rdname system_prompt
#' @export
system_prompt.llm_block_proxy <- function(x, datasets, has_image = FALSE, ...) {

  meta_builder <- blockr_option("make_meta_data", build_metadata_default)

  if (!is.function(meta_builder)) {
    meta_builder <- get(meta_builder, mode = "function")
  }

  metadata <- meta_builder(datasets)

  res <- paste0(
    NextMethod(),
    "\n\n",
    "You have the following dataset(s) at your disposal: ",
    paste(shQuote(names(datasets)), collapse = ", "), ".\n",
    "These can be summarized in the following way:\n\n",
    paste0("* ", names(metadata), ": ", metadata, collapse = "\n"),
    "\n\n",
    "IMPORTANT: Be very careful to use only the provided dataset names in your code.\n",
    "This means you should not use generic names of undefined datasets ",
    "like `x`, `df`, or `my_data` unless these are explicitly provided.\n",
    "You should not produce code to rebuild the input objects.\n",
    "Use the exact dataset names shown above: ", 
    paste(shQuote(names(datasets)), collapse = ", "), ".\n"
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

build_metadata_default <- function(x) {
  lapply(x, build_metadata)
}

#' @rdname system_prompt
#' @export
build_metadata <- function(x, ...) {
  UseMethod("build_metadata")
}

#' @rdname system_prompt
#' @export
build_metadata.data.frame <- function(x, ...) {
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

#' @rdname system_prompt
#' @export
build_metadata.flextable <- function(x, ...) {
  paste0(
    "This object is a flextable with columns ",
    paste(shQuote(x$col_keys), collapse = ", ")
  )
}

#' @rdname system_prompt
#' @export
build_metadata.default <- function(x, ...) {
  paste0(
    "This object has class attributes ",
    paste(shQuote(class(x)), collapse = ", ")
  )
}
