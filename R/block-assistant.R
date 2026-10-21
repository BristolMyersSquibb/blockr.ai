# The per-block assistant, run on blockr.assistant's tools.
#
# blockr.assistant's tools read a board: `board$board`, each block's server
# result, state and conditions, and an eval status per block. A control plugin
# has no board, only its own block, the block's state values, its inputs and a
# reactive that evaluates it. `new_block_scope()` builds the board those tools
# expect out of that: the block (id `this_block`) and one entry per input,
# linked to it. Mutation is limited to the block's own state values.
#
# The tools are blockr.assistant internals, reached through asst(). They are
# not exported, so this ties blockr.ai to the blockr.assistant it was written
# against; the DESCRIPTION floor says which.

BLOCK_ID <- "this_block"

asst <- function(name) {
  utils::getFromNamespace(name, "blockr.assistant")
}

# One condition row in the shape blockr.core's board conditions use.
condition_row <- function(message) {
  data.frame(
    block = BLOCK_ID, phase = "eval", severity = "error",
    message = message, id = "eval", stringsAsFactors = FALSE
  )
}

no_conditions <- function() {
  condition_row("")[0L, , drop = FALSE]
}

#' Build the one-block board the assistant's tools read
#'
#' @param x The block.
#' @param vars Its externally controllable state, as `reactiveVal`s (the
#'   control plugin's `vars`).
#' @param eval The control plugin's `eval` reactive.
#' @return An environment with `board`, `blocks`, `conditions`, `eval`, plus
#'   `set_inputs()`, `refresh()` and `apply()`.
#' @noRd
new_block_scope <- function(x, vars, eval) {

  scope <- new.env(parent = emptyenv())

  inputs <- list()
  result <- NULL
  error <- NULL

  state_vars <- vars[setdiff(names(vars), "block_name")]

  refresh <- function() {
    res <- tryCatch(shiny::isolate(eval()), error = function(e) e)
    if (inherits(res, "error")) {
      result <<- NULL
      error <<- strip_ansi(conditionMessage(res))
    } else {
      result <<- res
      error <<- NULL
    }
    invisible(is.null(error))
  }

  scope$set_inputs <- function(x_inputs) {
    inputs <<- x_inputs
    refresh()
  }

  scope$refresh <- refresh
  scope$result <- function() result
  scope$inputs <- function() inputs

  makeActiveBinding("board", function() {
    ins <- lapply(inputs, blockr.core::new_static_block)
    blks <- do.call(c, c(ins, stats::setNames(list(x), BLOCK_ID)))
    lnks <- if (length(inputs)) {
      blockr.core::links(
        from = names(inputs), to = rep(BLOCK_ID, length(inputs)),
        input = names(inputs)
      )
    } else {
      blockr.core::links()
    }
    blockr.core::new_board(blocks = blks, links = lnks)
  }, scope)

  makeActiveBinding("blocks", function() {
    ins <- lapply(names(inputs), function(nm) {
      list(server = list(result = function() inputs[[nm]], state = list()))
    })
    names(ins) <- names(inputs)
    c(ins, stats::setNames(list(list(server = list(
      result = function() result,
      state = state_vars,
      conditions = function() scope$conditions()
    ))), BLOCK_ID))
  }, scope)

  scope$conditions <- function() {
    if (is.null(error)) no_conditions() else condition_row(error)
  }

  makeActiveBinding("eval", function() {
    stats::setNames(
      list(function() if (is.null(error)) "ready" else "failed"),
      BLOCK_ID
    )
  }, scope)

  # Write a staged delta into the block's state. On an evaluation error the
  # values go back to what they were, as blockr.core's own ctrl plugin does.
  scope$apply <- function(delta) {
    unknown <- setdiff(names(delta), names(vars))
    if (length(unknown)) {
      stop("Not an argument of this block: ", paste(unknown, collapse = ", "),
           call. = FALSE)
    }
    old <- lapply(vars[names(delta)], function(v) shiny::isolate(v()))
    for (nm in names(delta)) vars[[nm]](delta[[nm]])
    ok <- refresh()
    if (!ok) {
      failed <- error
      for (nm in names(old)) vars[[nm]](old[[nm]])
      refresh()
      error <<- failed
    }
    invisible(ok)
  }

  scope
}

block_scope_note <- function() {
  paste(
    "\n\n## Scope",
    "This chat belongs to block `this_block`, and every request is about it.",
    "When the user asks for a result -- show, keep, add, sort, count, plot,",
    "model -- make the block produce it: modify it and commit. A reply in",
    "chat does not change the block, and the user sees the block. Answer in",
    "chat only when the user asks a question about the data or the result,",
    "and then leave the block as it is. You cannot add, remove or link",
    "blocks. If this block cannot produce what is asked, say so and name the",
    "kind of block that would.",
    "The block's inputs are the other blocks on the board. In inspect_results",
    "each is bound by its name (usually `data`), and this block's own result",
    "as `this_block`.",
    sep = "\n"
  )
}

# The effect of a commit on the block, from blockr.ai's own generics: a block's
# config description where it has one, else a diff against its first input.
scope_effect_line <- function(scope, x, vars) {

  input <- if (length(scope$inputs())) scope$inputs()[[1L]] else NULL
  args <- lapply(vars, function(v) shiny::isolate(v()))

  fx <- tryCatch({
    ce <- config_effect(x, args, input)
    if (is.null(ce)) data_effect(input, scope$result()) else ce
  }, error = function(e) "")

  if (!length(fx) || !nzchar(fx)) {
    return(NULL)
  }

  paste0(
    "Effect on `this_block`: ", fx,
    if (effect_is_noop(fx)) {
      paste(
        "\nThis change did nothing to the result. If the user asked for a",
        "change, it has not happened: fix it, or tell the user why it cannot."
      )
    }
  )
}

#' A chat client wired to one block
#'
#' Registers blockr.assistant's read tools, the block's typed modify tool (or
#' `modify_block` when the type has none), commit, discard and read_skill. The
#' staging guard refuses anything but a change to this block.
#'
#' @return The client, with the scope and the pending payload attached as
#'   attributes `blockr_scope` and `blockr_pending`.
#' @noRd
new_block_client <- function(scope, x, vars, client = llm_client()) {

  payload <- asst("empty_pending")()

  in_scope <- function(p) {
    !length(p$blocks$add) && !length(p$blocks$rm) &&
      all(names(p$blocks$mod) %in% BLOCK_ID) &&
      !any(lengths(p$links) > 0L) && !any(lengths(p$stacks) > 0L)
  }

  pending <- function(p) {
    if (missing(p)) {
      return(payload)
    }
    if (!in_scope(p)) {
      stop("This chat can only change this block; other blocks, links and ",
           "stacks are out of reach.", call. = FALSE)
    }
    payload <<- p
    invisible(payload)
  }

  perform <- function() {

    if (!asst("has_any_changes")(payload)) {
      return(paste("Nothing is staged. Stage changes with the mutation",
                   "tools, then commit."))
    }

    delta <- payload$blocks$mod[[BLOCK_ID]]
    payload <<- asst("empty_pending")()

    ok <- tryCatch(scope$apply(delta), error = function(e) e)

    if (inherits(ok, "error")) {
      return(ellmer::ContentToolResult(error = conditionMessage(ok)))
    }

    review <- asst("format_flush_feedback")(
      list(ok = TRUE),
      scope$conditions(),
      asst("collect_touched_results")(BLOCK_ID, scope, character()),
      header = asst("commit_header")()
    )

    if (is.null(review)) {
      review <- asst("commit_clean_note")()
    }

    paste(c(review, scope_effect_line(scope, x, vars)), collapse = "\n\n")
  }

  pool <- asst("new_block_tool_pool")(client, scope, pending, NULL)

  tools <- list(
    asst("tool_list_blocks")(scope, NULL, NULL),
    asst("tool_describe_block")(scope, NULL, NULL, pool),
    asst("tool_get_block_result")(scope, NULL, NULL),
    asst("tool_get_block_state")(scope, NULL, NULL),
    asst("tool_get_block_conditions")(scope, NULL, NULL),
    asst("tool_inspect_results")(scope, NULL, NULL),
    asst("tool_commit")(perform),
    asst("tool_discard")(pending)
  )
  for (tl in tools) client$register_tool(tl)

  type <- blockr.core::registry_id_from_block(x)
  armed <- asst("arm_block_tool")(pool, "modify", type)
  if (!grepl("is now registered", armed %||% "")) {
    client$register_tool(asst("tool_modify_block")(scope, pending, NULL))
  }

  asst("register_skill_tools")(client)

  attr(client, "blockr_pool") <- pool
  attr(client, "blockr_pending") <- pending
  attr(client, "blockr_skills") <- paste(
    asst("skill_lines")(asst("block_skills")(type)), collapse = "\n"
  )

  client
}

block_system_prompt <- function(scope, client) {
  skills <- attr(client, "blockr_skills")
  paste0(
    blockr.assistant::default_system_prompt(scope, client, focus = BLOCK_ID),
    block_scope_note(),
    if (length(skills) && nzchar(skills)) paste0("\n\n", skills) else ""
  )
}

#' One user turn of the per-block assistant
#'
#' @param client From `new_block_client()`.
#' @param scope From `new_block_scope()`.
#' @param inputs List of content: the prompt text, then any images.
#' @param chat_id,session When given, the turn streams into that shinychat
#'   widget with tool cards; otherwise it runs headless.
#' @return The model's last reply, as text.
#' @noRd
block_turn <- function(client, scope, inputs, chat_id = NULL, session = NULL) {

  pool <- attr(client, "blockr_pool")
  pending <- attr(client, "blockr_pending")
  has_changes <- asst("has_any_changes")

  pool$new_turn()
  client$set_system_prompt(block_system_prompt(scope, client))

  send <- function(contents) {
    if (is.null(chat_id)) {
      do.call(client$chat, contents)
    } else {
      chat_with_cards(client, contents, chat_id, session)
    }
  }

  reply <- send(inputs)

  # As in the board assistant: up to three prompts to resolve staged changes,
  # then they are dropped.
  nudges <- 0L
  while (has_changes(pending()) && nudges < 3L) {
    nudges <- nudges + 1L
    reply <- send(list(asst("uncommitted_nudge")()))
  }

  if (has_changes(pending())) {
    pending(asst("empty_pending")())
  }

  paste(as.character(reply), collapse = "\n")
}

strip_ansi <- function(x) {
  gsub("\033\\[[0-9;]*m", "", x)
}

#' Skills that target a block
#'
#' The deployment's skills scoped to the block's type, as blockr.assistant
#' reads them from the `blockr.assistant_skills` option.
#'
#' @param block A block object.
#' @return A list of `list(name, description)`; empty when none target it.
#' @export
block_skills <- function(block) {
  type <- blockr.core::registry_id_from_block(block)
  lapply(asst("block_skills")(type), function(s) s[c("name", "description")])
}
