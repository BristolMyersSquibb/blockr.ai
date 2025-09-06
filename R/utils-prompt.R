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

  meta_builder <- blockr_option("make_meta_data", describe_inputs)

  if (!is.function(meta_builder)) {
    meta_builder <- get(meta_builder, mode = "function")
  }

  metadata <- meta_builder(datasets)

  res <- paste0(
    NextMethod(),
    "\n\n",
    "You have the following dataset at your disposal: ",
    paste(shQuote(names(datasets)), collapse = ", "), ".\n",
    metadata,
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
describe_inputs <- function(x) {

  if (length(x) == 1L) {

    res <- paste0(
      "This dataset can be described in the following way:\n\n",
      paste0(describe_input(x[[1L]]), collapse = "\n"),
      "\n\n"
    )

    return(res)
  }

  res <- lapply(x, describe_input)

  paste0(
    "The input dataset are summarized in the following sections.\n\n",
    paste0(
      "### ", names(res), "\n\n",
      chr_ply(res, paste0, collapse = "\n"),
      collapse = "\n\n"
    ),
    "\n\n"
  )
}

#' @rdname system_prompt
#' @export
describe_input <- function(x, ...) {
  UseMethod("describe_input")
}

#' @rdname system_prompt
#' @export
describe_input.flextable <- function(x, ...) {
  paste0(
    "This object is a flextable with columns ",
    paste(shQuote(x$col_keys), collapse = ", ")
  )
}

#' @rdname system_prompt
#' @export
describe_input.default <- function(x, ...) {
  btw::btw_this(x, ...)
}
