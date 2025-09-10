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

#' @param datasets Data sets from which to extract metadata
#' @param tools List of [ellmer::tool()] objects
#' @rdname system_prompt
#' @export
system_prompt.default <- function(x, datasets, tools, ...) {

  if (length(tools)) {
    tool_prompt <- paste0(
      "You have available the following tools ",
      paste_enum(chr_ply(tools, function(x) x$tool@name)), ". ",
      "Make use of these tools as you see fit.\n"
    )
  } else {
    tool_prompt <- ""
  }

  paste0(
    "You are an R programming assistant.\n",
    "Your task is to produce working R code according to user instructions.\n",
    "In addition, you should provide clear explanations to accompany the ",
    "generated R code.\n",
    "Important: If you call functions in packages, always use namespace ",
    "prefixes. Do not use library calls for attaching package namespaces.\n",
    tool_prompt
  )
}

#' @rdname system_prompt
#' @export
system_prompt.llm_block_proxy <- function(x, datasets, tools, ...) {

  if (length(datasets)) {

    meta_builder <- blockr_option("make_meta_data", describe_inputs)

    if (!is.function(meta_builder)) {
      meta_builder <- get(meta_builder, mode = "function")
    }

    meta <- paste0(
      "\n\n",
      "You have the following dataset", if (length(datasets) > 1L) "s",
      " at your disposal: ",
      paste(shQuote(names(datasets)), collapse = ", "), ".\n",
      meta_builder(datasets), "\n",
      "Be very careful to use only the provided names in your explanations ",
      "and code.\n",
      "This means you should not use generic names of undefined datasets ",
      "like `x` or `data` unless these are explicitly provided.\n",
      "You should not produce code to rebuild the input objects.",
    )

  } else {
     meta <- ""
  }

  tool_prompts <- filter(has_length, lapply(tools, get_prompt))

  paste0(
    NextMethod(),
    meta,
    if (has_length(tool_prompts)) "\n\n",
    paste0(
      filter(has_length, lapply(tools, get_prompt)),
      collapse = "\n"
    ),
    "\n\n"
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
