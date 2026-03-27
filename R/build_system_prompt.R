#' Build system prompt for block argument discovery (template-based)
#'
#' Produces the same output as [build_system_prompt()] but reads a Markdown
#' template from `inst/prompts/system_prompt.md` and interpolates it with
#' [glue::glue()]. The template uses `{? cond: content}` / `{! cond: content}`
#' for conditional sections; the function only gathers raw data and passes it.
#'
#' @param var_names Names of controllable variables
#' @param block Block object for context
#' @return Character string with system prompt
#' @noRd
build_system_prompt <- function(var_names, block) {
  # FIXME: we shouldn't have something dplyr specific here
  helper_fns <- getOption("blockr.dplyr.summary_functions")
  block_name <- class(block)[1]
  reg_info <- get_block_registry_info(block_name)
  param_docs_raw <- get_block_param_docs_raw(block_name)
  example <- generate_example_json(param_docs_raw)
  block_prompt <- attr(param_docs_raw, "prompt")

  system_prompt <- interpolate_system_prompt_template(
    name = reg_info$name,
    block_name = block_name,
    description = reg_info$description,
    var_names = var_names,
    param_docs_raw = param_docs_raw,
    block_prompt = block_prompt,
    helper_fns = helper_fns,
    example = example
  )
  system_prompt
}

# takes only character (or NULL) arguments and does the formatting and interpolation
interpolate_system_prompt_template <- function(
  name,
  block_name,
  description,
  var_names,
  param_docs_raw,
  block_prompt,
  helper_fns,
  example
) {
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


  # read template and double backticks so glue's parser doesn't treat them as R quoting
  # inside {?...} expressions. Restored to single backticks after glue runs.
  system_prompt_template <- read_template("system_prompt.md")
  system_prompt_template <- gsub("`", "``", system_prompt_template, fixed = TRUE)
  system_prompt <- as.character(glue::glue(
    system_prompt_template,
    .transformer = prompt_transformer,
    .trim = FALSE,
    .envir = list2env(list(
      name = name,
      block_name = block_name,
      description = description,
      collapsed_var_names = paste(var_names, collapse = ", "),
      parameter_descriptions = parameter_descriptions,
      block_prompt = block_prompt,
      helper_descriptions = helper_descriptions,
      example = example,
      var_name = var_names[1]
    ), parent = baseenv())
  ))

  # Clean up:
  # 1. Restore backticks
  system_prompt <- gsub("``", "`", system_prompt, fixed = TRUE)
  # 2. Remove conditional lines marked with \b
  system_prompt <- gsub("\b\n", "", system_prompt, fixed = TRUE)
  # 3. Collapse excess blank lines left by removed sections
  system_prompt <- gsub("\n{3,}", "\n\n", system_prompt)
  gsub("^\n+", "", system_prompt)
}

#' Read a prompt template from inst/prompts
#' @param name Template file name
#' @return Character string with template contents
#' @noRd
read_template <- function(name) {
  path <- system.file("prompts", name, package = "blockr.ai")
  template <- readLines(path, warn = FALSE)
  # remove comments
  template <- gsub("(?s)<!--.*?-->", "", template, perl = TRUE) 
  template <- paste(template, collapse = "\n")
  template
}

#' Custom glue transformer for conditional prompt sections
#'
#' Handles three forms:
#' - `{? condition: content}` — emit content if condition is TRUE, `"\b"` otherwise
#' - `{! condition: content}` — emit content if condition is FALSE, `"\b"` otherwise
#' - `{variable}` — plain interpolation
#'
#' Content is interpolated via [glue::glue()] so it may contain
#' nested `{variable}` references.
#'
#' @param text The expression text inside the braces
#' @param envir The environment to evaluate in
#' @return The evaluated value, or `"\b"` for suppressed conditional lines
#' @noRd
prompt_transformer <- function(text, envir) {
  if (startsWith(text, "? ") || startsWith(text, "! ")) {
    negate <- startsWith(text, "!")
    rest <- substring(text, 3)
    colon_pos <- regexpr(": ", rest, fixed = TRUE)
    cond_name <- substring(rest, 1, colon_pos - 1)
    content <- substring(rest, colon_pos + 2)
    cond_val <- get(cond_name, envir = envir)
    show <- length(cond_val) && all(nzchar(cond_val))
    if (negate) show <- !show
    if (!show) return("\b") # a marker used to remove empty lines
    if (!grepl("{", content, fixed = TRUE)) return(content)
    return(as.character(glue::glue(
      content, .envir = envir, .trim = FALSE
    )))
  }
  glue::identity_transformer(text, envir)
}
