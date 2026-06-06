# Harness: ellmer tool-calling (Design A)
#
# An alternative to the hand-rolled loop in discover_block_args(). Instead of
# "model returns JSON -> we validate -> ask DONE or fix -> repeat", validation
# is itself a tool. The model explores via `data_tool` and proposes via
# `validate_config`; ellmer drives the tool-call loop natively and stops when
# the model is satisfied. We read the last successful args off the validate tool.
#
# The validate tool wraps whatever `validate` function is supplied. In a live
# board that is the reactiveVal-writing validator (so the last successful call
# IS the apply); in scripting/tests it is the standalone validator.


#' Validate-config tool
#'
#' Wraps a block validator as an LLM tool. The model calls it with a JSON object
#' of block parameters; it parses, validates, and returns `{ok, preview}` or
#' `{ok, error}`. The last successful args and result are recorded for the
#' caller to read after the chat loop finishes.
#'
#' @param validate Validation function taking a named list of args, returning a
#'   result object or throwing on failure.
#' @param block Block object (for registry-derived parameter docs/examples).
#' @param data Input data, used to report the *effect* of the config (rows/cols
#'   changed) so a valid-but-ineffective config is visible to the model.
#' @return An `llm_tool` with extra accessors `$invoke()` (the raw run function,
#'   used in tests), `$last_ok()`, and `$last_result()`.
#' @noRd
new_validate_tool <- function(validate, block, data = NULL) {
  block_name <- class(block)[1]
  param_docs <- get_block_param_docs_raw(block_name)
  example <- generate_example_json(param_docs)

  param_text <- if (!is.null(param_docs)) {
    paste0(
      "\n\nParameters:\n",
      paste0("- ", names(param_docs), ": ", param_docs, collapse = "\n")
    )
  } else {
    ""
  }
  example_text <- if (!is.null(example)) {
    paste0("\n\nExample config: ", example)
  } else {
    ""
  }

  last_ok <- NULL
  last_result <- NULL

  run <- function(config) {
    args <- tryCatch(
      simplify_leaves(jsonlite::fromJSON(config, simplifyVector = FALSE)),
      error = function(e) e
    )
    if (inherits(args, "error")) {
      return(list(ok = FALSE,
                  error = paste0("Could not parse config as JSON: ",
                                 conditionMessage(args))))
    }
    if (!is.list(args)) {
      return(list(ok = FALSE,
                  error = "Config must be a JSON object of block parameters."))
    }

    res <- tryCatch(validate(args), error = function(e) e)
    if (inherits(res, "error")) {
      return(list(ok = FALSE, error = conditionMessage(res)))
    }

    last_ok <<- args
    last_result <<- res
    preview <- tryCatch(data_schema(res), error = function(e) "(no preview)")
    effect <- tryCatch(data_effect(data, res), error = function(e) "")
    list(ok = TRUE, effect = effect, preview = preview)
  }

  tool <- new_llm_tool(
    run,
    name = "validate_config",
    description = paste0(
      "Validate and apply a configuration for this block. Call with the block's ",
      "parameters as a single JSON object (the `config` argument, a JSON string). ",
      "Returns {ok:true, effect, preview} when the configuration is VALID, or ",
      "{ok:false, error} when it fails (read the error, fix, call again). You ",
      "must call this tool to apply any change; the last valid call is what takes ",
      "effect.\n\n",
      "IMPORTANT: ok=true means the config is valid, NOT that it did what the ",
      "user asked. A valid config can do nothing -- a filter that removes 0 rows ",
      "(`rows: 32 -> 32 (UNCHANGED)`), a transform that adds no column. ALWAYS ",
      "read `effect` and check it matches the request before you finish. If the ",
      "effect is UNCHANGED or wrong, your config didn't work (often the wrong ",
      "parameter shape, or this block can't express the request) -- fix it and ",
      "call again, or tell the user this block can't do it. Do not report success ",
      "on an UNCHANGED effect.",
      param_text,
      example_text
    ),
    arguments = list(
      config = ellmer::type_string(
        paste0("A JSON object string of the block's parameters, e.g. ",
               example %||% "{\"param\": \"value\"}", ".")
      )
    )
  )

  tool$invoke <- run
  tool$last_ok <- function() last_ok
  tool$last_result <- function() last_result
  tool
}


#' System prompt for the tool-calling harness
#'
#' Like [build_system_prompt()] but instructs the model to use the
#' `data_tool` / `validate_config` tools rather than emitting JSON + "DONE".
#'
#' @inheritParams build_system_prompt
#' @return Character string.
#' @noRd
build_tool_system_prompt <- function(var_names, block) {
  block_name <- class(block)[1]
  reg_info <- get_block_registry_info(block_name)

  block_context <- if (!is.null(reg_info$description)) {
    paste0("You are configuring a ", reg_info$name, " (", block_name, ").\n",
           reg_info$description, "\n\n")
  } else {
    paste0("You are configuring a ", block_name, ".\n\n")
  }

  param_docs_raw <- get_block_param_docs_raw(block_name)
  block_prompt <- if (!is.null(param_docs_raw)) {
    p <- attr(param_docs_raw, "prompt")
    if (!is.null(p)) paste0(p, "\n\n") else ""
  } else {
    ""
  }

  helper_fns <- getOption("blockr.dplyr.summary_functions")
  helper_text <- if (!is.null(helper_fns) && length(helper_fns) > 0) {
    fn_lines <- paste0("  ", names(helper_fns), ": ", helper_fns, collapse = "\n")
    paste0("Available helper functions:\n", fn_lines, "\n\n")
  } else {
    ""
  }

  paste0(
    block_context,
    "Parameters: ", paste(var_names, collapse = ", "), "\n\n",
    block_prompt,
    helper_text,
    "HOW TO WORK:\n",
    "- You have two tools. Use `data_tool` to run R against the input data when ",
    "you need to inspect columns, types, value ranges or unique levels. Use ",
    "`validate_config` to apply a configuration; it returns ok + the EFFECT on ",
    "the data + a preview, or an error to fix.\n",
    "- ok=true means VALID, not correct. Before finishing, read `effect` and ",
    "confirm it matches the request. A filter that removed 0 rows ",
    "(`UNCHANGED`), or a transform that changed nothing, means your config did ",
    "NOT work -- fix the parameter shape and call again, or tell the user this ",
    "block can't do what they asked. Never tell the user you applied a change ",
    "whose effect was UNCHANGED.\n",
    "- Only once the effect matches the request, stop and give a short, plain ",
    "reply describing what actually changed.\n\n",
    "BEHAVIOUR:\n",
    "- If the user asks a question or wants an explanation, look at the data ",
    "with `data_tool` and answer it in plain language, grounding the answer in ",
    "actual values. Keep the current configuration in place.\n",
    "- If the request is vague or ambiguous (e.g. 'make it better', 'fix it'), do ",
    "NOT guess -- ask one specific clarifying question instead of calling a tool.\n",
    "- If the request asks for something this block cannot do, explain the ",
    "limitation and suggest a more suitable block; do not force an invalid config.\n",
    "- Only set parameters the user asked about; leave the rest at their defaults."
  )
}


#' Discover block args via ellmer tool calling (Design A harness)
#'
#' @inheritParams discover_block_args
#' @param max_turns Backstop on tool-call turns (passed to ellmer if supported).
#' @return Same result shape as [discover_block_args()].
#' @noRd
discover_via_ellmer_tools <- function(prompt, block, data = NULL,
                                      validate = NULL, client = NULL,
                                      current_state = NULL, reporter = NULL,
                                      images = NULL, verbose = FALSE,
                                      max_turns = 12L) {
  if (is.null(reporter)) reporter <- auto_reporter()

  var_names <- block_ctor_inputs(block)
  if (length(var_names) == 0) {
    return(list(success = FALSE, args = NULL, conversation = NULL,
                result = NULL, error = "Block has no configurable parameters",
                client = client))
  }

  tool_set <- build_harness_tools(block, data, validate)
  validate_tool <- tool_set$validate
  data_tool <- tool_set$data

  block_name <- class(block)[1]

  conversation <- if (verbose) list() else NULL
  log_msg <- function(role, content) {
    if (verbose) {
      conversation[[length(conversation) + 1L]] <<-
        list(role = role, content = content)
    }
  }

  if (is.null(client)) {
    client <- llm_client()
    system_prompt <- build_tool_system_prompt(var_names, block)
    if (!is.null(data_tool)) {
      tp <- get_prompt(data_tool)
      if (length(tp) > 0L && any(nzchar(tp))) {
        system_prompt <- paste0(system_prompt, "\n\n", paste(tp, collapse = "\n"))
      }
    }
    client$set_system_prompt(system_prompt)
    log_msg("system", system_prompt)
  }

  tools <- list(get_tool(validate_tool))
  if (!is.null(data_tool)) tools <- c(list(get_tool(data_tool)), tools)
  client$set_tools(tools)

  msg <- paste0(
    data_preview(data),
    format_current_state(current_state),
    "# Task\n\n", prompt
  )
  log_msg("user", msg)
  message("[discover] ", block_name, " | harness: ellmer | prompt: ", prompt)

  reporter$start_phase("thinking")
  reply <- tryCatch({
    if (!is.null(images) && length(images) > 0) {
      img_contents <- lapply(images, function(img) {
        ellmer::ContentImageInline(type = img$type, data = img$data)
      })
      do.call(client$chat, c(list(msg), img_contents))
    } else {
      client$chat(msg)
    }
  }, error = function(e) e)
  reporter$end_phase("thinking")

  if (inherits(reply, "error")) {
    err <- paste0("LLM error: ", conditionMessage(reply))
    message("[discover] ", err)
    reporter$done(FALSE, err)
    return(list(success = FALSE, args = NULL, conversation = conversation,
                result = NULL, error = err, client = client))
  }

  reply_text <- tryCatch(as.character(reply), error = function(e) "")
  log_msg("assistant", reply_text)

  final_args <- validate_tool$last_ok()
  final_result <- validate_tool$last_result()
  success <- !is.null(final_args)

  reporter$done(success, if (success) NULL else "no valid configuration produced")
  message("[discover] done, success: ", success)

  list(
    success = success,
    args = final_args,
    result = final_result,
    message = reply_text,
    conversation = conversation,
    error = if (success) NULL else "Model did not produce a valid configuration",
    question = if (!success && nzchar(reply_text)) reply_text else NULL,
    client = client
  )
}
