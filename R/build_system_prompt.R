#' Build system prompt for block argument discovery (template-based)
#'
#' Reads a Markdown template from `inst/prompts/system_prompt.md` and interpolates it with
#' [glue::glue()]. The template uses `{? cond: content}` / `{! cond: content}`
#'
#' @param var_names Names of controllable variables
#' @param block Block object for context
#' @param backend_prompt_addition Additional prompt from backend
#' @return Character string with system prompt
#' @noRd
build_system_prompt <- function(var_names, block, backend_prompt_addition) {
  # FIXME: we shouldn't have something dplyr specific here
  helper_fns <- getOption("blockr.dplyr.summary_functions")
  block_name <- class(block)[1]
  reg_info <- get_block_registry_info(block_name)
  param_docs_raw <- get_block_param_docs_raw(block_name)
  example <- generate_example_json(param_docs_raw)
  block_prompt <- attr(param_docs_raw, "prompt")

  # format multiline strings from vector, so use only strings in the interpolation
  if (length(param_docs_raw)) {
    parameter_descriptions <-
      paste0(names(param_docs_raw), ": ", param_docs_raw, collapse = "\n")
  } else {
    parameter_descriptions <- NULL
  }
  if (length(helper_fns)) {
    helper_descriptions <-
      paste0("  ", names(helper_fns), ": ", helper_fns, collapse = "\n")
  } else {
    helper_descriptions <- NULL
  }

  system_prompt <- interpolate_template(
    template = read_template("system_prompt.md"),
    name = reg_info$name,
    block_name = block_name,
    description = reg_info$description,
    collapsed_var_names = paste(var_names, collapse = ", "),
    parameter_descriptions = parameter_descriptions,
    block_prompt = block_prompt,
    helper_descriptions = helper_descriptions,
    example = example,
    var_name = var_names[1],
    backend_prompt_addition = backend_prompt_addition
  )

  system_prompt
}
