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
  last_effect <- NULL

  # Typed path: expose the block's params as a native ellmer schema so the model
  # emits structured arguments (the API escapes them) instead of hand-building a
  # JSON-object string. Falls back to the single `config` JSON string when no
  # params can be inferred.
  types <- tryCatch(block_param_types(block), error = function(e) NULL)
  use_typed <- !is.null(types) && length(types) > 0

  # Shared validation core: takes an already-parsed named list of block params.
  core_run <- function(args) {
    if (!is.list(args)) {
      return(list(ok = FALSE,
                  error = "Config must be a JSON object of block parameters."))
    }

    # Reject unknown keys instead of silently dropping them: a config that the
    # block can't consume would otherwise apply nothing yet report success.
    # `block_name` (the block title) is a universal controllable var, so it is
    # valid even though it isn't a constructor argument.
    valid <- unique(c(block_ctor_inputs(block), "block_name"))
    unknown <- setdiff(names(args), valid)
    if (length(unknown)) {
      return(list(ok = FALSE, error = paste0(
        "Unknown parameter(s): ", paste(unknown, collapse = ", "),
        ". Valid parameter(s): ", paste(setdiff(valid, "block_name"), collapse = ", "),
        ". Pass these as a flat JSON object; do not wrap values in 'state' ",
        "unless 'state' is listed above."
      )))
    }

    res <- tryCatch(validate(args), error = function(e) e)
    if (inherits(res, "error")) {
      return(list(ok = FALSE, error = conditionMessage(res)))
    }

    last_ok <<- args
    last_result <<- res
    preview <- tryCatch(data_schema(res), error = function(e) "(no preview)")
    # Control/viz blocks (drilldown, patient profile) pass their data through, so
    # the data effect is blind/no-op -- prefer a config-described effect when the
    # block provides one.
    effect <- tryCatch(config_effect(block, args, data), error = function(e) NULL)
    if (is.null(effect)) {
      effect <- tryCatch(data_effect(data, res), error = function(e) "")
    }
    last_effect <<- effect
    list(ok = TRUE, effect = effect, preview = preview)
  }

  # JSON-string entry point: used by the standalone/test `$invoke()` interface and
  # by the fallback (untyped) tool path.
  json_run <- function(config) {
    parsed <- tryCatch(jsonlite::fromJSON(config, simplifyVector = FALSE),
                       error = function(e) e)
    if (inherits(parsed, "error")) {
      return(list(ok = FALSE,
                  error = paste0("Could not parse config as JSON: ",
                                 conditionMessage(parsed))))
    }
    core_run(tryCatch(simplify_leaves(parsed), error = function(e) parsed))
  }

  # Typed entry point: a function whose formals ARE the block's param names, so
  # ellmer can pass native structured arguments. Re-parse any JSON-string leaves
  # (the polymorphic-array fallbacks) before validating.
  typed_run <- if (use_typed) {
    build_arg_collector(names(types), function(args) {
      core_run(tryCatch(simplify_leaves(reparse_json_strings(args)),
                        error = function(e) args))
    })
  } else {
    NULL
  }

  call_intro <- if (use_typed) {
    paste0("Validate and apply a configuration for this block. Pass the block's ",
           "parameters directly as the tool arguments (write any R code as a ",
           "plain argument value -- do NOT wrap the parameters in a JSON string). ")
  } else {
    paste0("Validate and apply a configuration for this block. Call with the ",
           "block's parameters as a single JSON object (the `config` argument, ",
           "a JSON string). ")
  }

  tool <- new_llm_tool(
    if (use_typed) typed_run else json_run,
    name = "validate_config",
    description = paste0(
      call_intro,
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
    arguments = if (use_typed) {
      types
    } else {
      list(config = ellmer::type_string(
        paste0("A JSON object string of the block's parameters, e.g. ",
               example %||% "{\"param\": \"value\"}", ".")
      ))
    }
  )

  tool$invoke <- json_run
  tool$last_ok <- function() last_ok
  tool$last_result <- function() last_result
  tool$last_effect <- function() last_effect
  tool
}

#' Does an effect string indicate the config did nothing meaningful?
#'
#' Matches the explicit no-op signals only -- a data.frame that changed no rows
#' or columns, or a composer/gt table still showing format placeholders ("NOT
#' populated"). Deliberately does NOT match a bare "UNCHANGED" row count, since a
#' same-row transform that adds/modifies a column is effective.
#' @noRd
effect_is_noop <- function(effect) {
  if (is.null(effect) || !nzchar(effect)) return(FALSE)
  grepl("not populated|no rows or columns changed", effect, ignore.case = TRUE)
}


#' System prompt for the tool-calling harness
#'
#' Instructs the model to use the `data_tool` / `validate_config` tools.
#'
#' @param var_names Names of the block's controllable variables.
#' @param block Block object, for registry-derived context.
#' @return Character string.
#' @noRd
build_tool_system_prompt <- function(var_names, block,
                                      skills = skills_for_block(block)) {
  block_name <- class(block)[1]
  reg_info <- get_block_registry_info(block_name)

  block_context <- if (!is.null(reg_info$description)) {
    paste0("You are configuring a ", reg_info$name, " (", block_name, ").\n",
           reg_info$description, "\n\n")
  } else {
    paste0("You are configuring a ", block_name, ".\n\n")
  }

  guidance <- get_block_guidance(block_name)
  block_prompt <- if (!is.null(guidance)) paste0(guidance, "\n\n") else ""

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
    skill_catalog_text(skills),
    helper_text,
    "HOW TO WORK:\n",
    "- To change the block you MUST call `validate_config`. Writing the ",
    "configuration in your text reply does NOT apply it -- the user cannot copy ",
    "or paste it and will see no change. There is no 'here is a config you can ",
    "paste'. If you have decided on a config, call `validate_config` with it; do ",
    "not describe it in prose instead.\n",
    "- 'Adjust / populate / configure / set this to the data' is an ACTION, not ",
    "a question: explore with `data_tool` if needed, then call `validate_config`. ",
    "Do not answer it in plain language and stop.\n",
    "- Use `data_tool` to run R against the input data when ",
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


#' Collapse a code probe to a one-line summary for a badge.
#' @noRd
summarize_probe_code <- function(code) {
  code <- paste(code, collapse = " ")
  code <- gsub("\\s+", " ", trimws(code))
  truncate_summary(code, 64L)
}

#' Truncate a summary string with an ellipsis.
#' @noRd
truncate_summary <- function(x, n = 80L) {
  if (is.null(x)) return("")
  x <- gsub("\\s+", " ", trimws(as.character(x)))
  if (length(x) != 1L) x <- paste(x, collapse = " ")
  if (nchar(x) > n) paste0(substr(x, 1L, n - 1L), "\u2026") else x
}

#' Build a reporter `tool_event` payload from an ellmer tool *request*.
#'
#' Fires when the model asks to call a tool, before it runs -- so the badge can
#' appear immediately with a spinner and (for `data_tool`) the code it is about
#' to run.
#' @noRd
tool_request_event <- function(request) {
  name <- request@name
  args <- request@arguments
  if (identical(name, "data_tool")) {
    list(id = request@id, phase = "exploring", label = "Exploring data",
         summary = summarize_probe_code(args$code %||% ""), code = TRUE,
         status = "active")
  } else if (identical(name, "validate_config")) {
    list(id = request@id, phase = "validating", label = "Applying configuration",
         summary = NULL, code = FALSE, status = "active")
  } else if (identical(name, "read_skill")) {
    list(id = request@id, phase = "exploring", label = "Reading skill",
         summary = truncate_summary(args$name %||% ""), code = FALSE,
         status = "active")
  } else if (identical(name, "read_skill_file")) {
    list(id = request@id, phase = "exploring", label = "Reading skill file",
         summary = truncate_summary(skill_file_summary(args)), code = FALSE,
         status = "active")
  } else {
    list(id = request@id, phase = "exploring", label = name, summary = NULL,
         code = FALSE, status = "active")
  }
}

#' One-line "skill/path" summary for a read_skill_file badge.
#' @noRd
skill_file_summary <- function(args) {
  path <- args$path %||% ""
  nm <- args$name %||% ""
  if (nzchar(nm) && nzchar(path)) paste0(nm, "/", path) else paste0(nm, path)
}

#' Build a reporter `tool_event` payload from an ellmer tool *result*.
#'
#' Fires after the tool returns. Surfaces the genuinely useful content: for
#' `validate_config`, the `effect` the config had (e.g. "rows 1200 -> 340") on
#' success, or the validation error on failure. A thrown tool error (e.g. the
#' data-probe budget being exceeded) lands in `@error`.
#' @noRd
tool_result_event <- function(result) {
  request <- result@request
  name <- request@name

  if (!is.null(result@error) && nzchar(result@error %||% "")) {
    return(list(id = request@id, phase = "retrying", label = "Fixing",
                summary = truncate_summary(result@error), code = FALSE,
                status = "error"))
  }

  value <- result@value
  if (identical(name, "data_tool")) {
    return(list(id = request@id, phase = "exploring", label = "Explored data",
                summary = summarize_probe_code(request@arguments$code %||% ""),
                code = TRUE, status = "done"))
  }
  if (identical(name, "validate_config")) {
    ok <- is.list(value) && isTRUE(value$ok)
    if (ok) {
      return(list(id = request@id, phase = "confirming", label = "Applied config",
                  summary = truncate_summary(value$effect %||% ""), code = FALSE,
                  status = "done"))
    }
    err <- if (is.list(value)) value$error else NULL
    return(list(id = request@id, phase = "retrying", label = "Fixing",
                summary = truncate_summary(err %||% "invalid configuration"),
                code = FALSE, status = "error"))
  }
  if (identical(name, "read_skill")) {
    return(list(id = request@id, phase = "exploring", label = "Read skill",
                summary = truncate_summary(request@arguments$name %||% ""),
                code = FALSE, status = "done"))
  }
  if (identical(name, "read_skill_file")) {
    return(list(id = request@id, phase = "exploring", label = "Read skill file",
                summary = truncate_summary(skill_file_summary(request@arguments)),
                code = FALSE, status = "done"))
  }
  list(id = request@id, phase = "exploring", label = name, summary = NULL,
       code = FALSE, status = "done")
}

#' Wire ellmer tool-call callbacks to a reporter.
#'
#' Registers request/result callbacks on the client so every tool call becomes a
#' badge. Returns an unregister function (call it when the turn ends so a reused
#' client does not accumulate callbacks bound to a stale reporter).
#' @noRd
register_tool_reporter <- function(client, reporter) {
  noop <- function() invisible()
  # Test/fake clients may not implement the tool-callback API; degrade quietly.
  if (!is.function(client$on_tool_request) ||
      !is.function(client$on_tool_result)) {
    return(noop)
  }
  emit <- function(ev) {
    if (!is.null(reporter$tool_event)) {
      reporter$tool_event(ev$id, ev$phase, ev$label, ev$summary, ev$code,
                          ev$status)
    }
  }
  unreg_req <- client$on_tool_request(function(request) {
    tryCatch(emit(tool_request_event(request)), error = function(e) NULL)
  })
  unreg_res <- client$on_tool_result(function(result) {
    tryCatch(emit(tool_result_event(result)), error = function(e) NULL)
  })
  function() {
    tryCatch(unreg_req(), error = function(e) NULL)
    tryCatch(unreg_res(), error = function(e) NULL)
  }
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

  # First turn = no prior conversation. On a follow-up turn the system prompt and
  # the data preview are already in the chat history, so only the first turn needs
  # the full schema dump. A caller may pre-create the client (the eval harness,
  # tests, or any embedder), so "client is NULL" alone is not the signal -- a
  # passed-in client with no turns yet is still a first turn.
  first_turn <- is.null(client) || length(client$get_turns()) == 0

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
    system_prompt <- build_tool_system_prompt(var_names, block, tool_set$skills)
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
  if (length(tool_set$skill_tools)) {
    tools <- c(tools, lapply(tool_set$skill_tools, get_tool))
  }
  client$set_tools(tools)

  # Surface every tool call as a reporter badge (the client is reused across
  # turns, so unregister on exit to avoid stacking callbacks on a stale reporter).
  unregister_reporter <- register_tool_reporter(client, reporter)
  on.exit(unregister_reporter(), add = TRUE)

  # Send the full data schema on the first turn, and again whenever the upstream
  # data has CHANGED since we last sent it (the user may rewire the input between
  # turns). On an unchanged follow-up the schema is already in the chat history,
  # so re-dumping it (every table, every column) is the dominant multi-turn token
  # cost on wide ADaM data; send a one-line pointer instead. The model can still
  # pull exact columns/values with `data_tool` (`data_query`). We remember the
  # last schema we sent on the client itself (it is reused across turns).
  schema <- data_preview(data)
  prev_schema <- attr(client, "blockr_ai_last_schema")
  data_unchanged <- !first_turn && !is.null(prev_schema) && identical(prev_schema, schema)
  data_block <- if (!data_unchanged) {
    schema
  } else if (nzchar(schema)) {
    paste0(
      "# Input Data\n\n",
      "(unchanged from earlier in this conversation -- use data_query to inspect ",
      "any table or column)\n\n"
    )
  } else {
    ""
  }
  attr(client, "blockr_ai_last_schema") <- schema

  msg <- paste0(
    data_block,
    format_current_state(current_state),
    "# Task\n\n", prompt
  )
  log_msg("user", msg)
  message("[discover] ", block_name, " | harness: ellmer | prompt: ", prompt)

  do_chat <- function(message_text, with_images = FALSE) {
    tryCatch({
      if (with_images && !is.null(images) && length(images) > 0) {
        img_contents <- lapply(images, function(img) {
          ellmer::ContentImageInline(type = img$type, data = img$data)
        })
        do.call(client$chat, c(list(message_text), img_contents))
      } else {
        client$chat(message_text)
      }
    }, error = function(e) e)
  }

  reporter$start_phase("thinking")
  reply <- do_chat(msg, with_images = TRUE)
  # Models frequently DESCRIBE a config in prose ("here is a config you can
  # paste") instead of calling validate_config, so the change never lands. If no
  # config was applied, nudge once or twice to call the tool. Genuine clarifying
  # questions survive: the model can simply re-ask, and an honest "this block
  # cannot do it" reply ends the same way (success=FALSE) as before.
  nudges <- 0L
  repeat {
    if (inherits(reply, "error")) break
    no_config <- is.null(validate_tool$last_ok())
    noop <- !no_config && effect_is_noop(validate_tool$last_effect())
    # Stop once we have a config that actually did something, or we've nudged
    # enough. Genuine clarifying questions / honest "can't do it" survive: the
    # model just re-replies in text and we exit on the nudge cap.
    if ((!no_config && !noop) || nudges >= 3L) break
    nudges <- nudges + 1L
    reply <- do_chat(if (no_config) {
      paste0(
        "You have not applied any configuration (no successful validate_config ",
        "call yet). Writing the config in your reply does NOT apply it -- the ",
        "user sees no change. If you have a configuration ready, call ",
        "validate_config NOW with it (fix and retry if it errors). Reply in plain ",
        "text ONLY to ask one specific clarifying question, or to say the block ",
        "genuinely cannot do this."
      )
    } else {
      paste0(
        "Your last validate_config was VALID but had NO real effect (effect: ",
        validate_tool$last_effect(), "). Usually that means it is not done: a ",
        "composer table still showing 'xx.x' placeholders needs real data wired ",
        "in (add `data =` to table() and `denominator = make_denom(...)`); a ",
        "filter that removed 0 rows has the wrong condition. Fix it and call ",
        "validate_config again. BUT if a no-op is genuinely what the request ",
        "wants -- e.g. you exposed a selector that defaults to showing everything ",
        "-- keep the config and reply in text saying so. Or say the block ",
        "genuinely cannot do this."
      )
    })
  }
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
    # A non-empty reply with no config is a clarifying question / explanation
    # (the prompt tells the model to ask back on vague requests) -- that is
    # expected behaviour, not an error.
    error = if (!success && !nzchar(reply_text)) {
      "Model did not produce a valid configuration"
    } else {
      NULL
    },
    question = if (!success && nzchar(reply_text)) reply_text else NULL,
    client = client
  )
}
