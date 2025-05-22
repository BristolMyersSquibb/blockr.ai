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

  build_metadata <- blockr_option("make_meta_data", build_metadata_default)

  if (!is.function(build_metadata)) {
    build_metadata <- get(build_metadata, mode = "function")
  }

  metadata <- build_metadata(datasets)

  res <- paste0(
    NextMethod(),
    "\n\n",
    "You have the following dataset at your disposal: ",
    paste(shQuote(names(datasets)), collapse = ", "), ".\n",
    "These come with summaries or metadata given below along with a ",
    "description: ", shQuote(metadata$description, type = "cmd"), ".\n\n",
    "```{r}\n",
    paste(
      constructive::construct_multi(metadata$summaries)$code,
      collapse = "\n"
    ),
    "\n```\n\n",
    "Be very careful to use only the provided names in your explanations ",
    "and code.\n",
    "This means you should not use generic names of undefined datasets ",
    "like `x` or `data` unless these are explicitly provided.\n",
    "You should not produce code to rebuild the input objects.\n"
  )
}

#' @param verbose Logical flag which enables printing of the system prompt
#' @rdname system_prompt
#' @export
system_prompt.llm_transform_block_proxy <- function(
  x,
  datasets,
  verbose = blockr_option("verbose", TRUE),
  ...) {

  prompt <- paste0(
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

  if (isTRUE(verbose)) {
    cat(
      "\n-------------------- system prompt --------------------\n",
      prompt,
      "\n",
      sep = ""
    )
  }

  prompt
}

#' @rdname system_prompt
#' @export
system_prompt.llm_plot_block_proxy <- function(
  x,
  datasets,
  verbose = blockr_option("verbose", TRUE),
  ...) {

  if (is.null(verbose)) {
    verbose <- getOption("blockr.ai.verbose", TRUE)
  }

  prompt <- paste0(
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

  if (isTRUE(verbose)) {
    cat(
      "\n-------------------- system prompt --------------------\n",
      prompt,
      "\n"
    )
  }

  prompt
}

build_metadata_default <- function(x) {
  list(
    description = paste0(
      "We provide below the ptypes (i.e. the output of `vctrs::vec_ptype()`) ",
      "of the actual datasets that you have at your disposal:"
    ),
    summaries = lapply(x, vctrs::vec_ptype)
  )
}
