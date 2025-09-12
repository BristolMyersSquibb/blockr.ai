query_llm_with_tools <- function(client, task, user_prompt, system_prompt,
                                 tools) {

  log_debug(
    "\n----------------- user prompt -----------------\n\n",
    user_prompt,
    "\n"
  )

  log_trace(
    "\n---------------- system prompt ----------------\n\n",
    system_prompt,
    "\n"
  )

  log_debug(
    "\n-----------------------------------------------\n\n"
  )

  client$set_system_prompt(system_prompt)
  client$set_tools(lapply(tools, get_tool))

  task$invoke(client, "chat", user_prompt)

  invisible()
}

type_response <- function() {
  type_object(
    explanation = type_string("Explanation of the analysis approach"),
    code = type_string("R code to perform the analysis")
  )
}

setup_chat_task <- function(session) {

  ExtendedTask$new(
    function(client, ui_id, user_input) {

      stream <- client$stream_async(
        user_input,
        stream = "content"
      )

      promises::promise_resolve(stream) |>
        promises::then(
          function(stream) {
            shinychat::chat_append(ui_id, stream)
          }
        )
    }
  )
}

last_turn <- function(client) {
  client$last_turn()@text
}

last_turn_structured <- function(client) {
  client$chat_structured(
    last_turn(client),
    type = type_response()
  )
}

eval_tool_code <- function(client) {

  tool <- client$get_tools()[["eval_tool"]]
  code <- get0("current_code", envir = environment(tool), inherits = FALSE)

  if (is.null(code)) {
    stop(
      "Code not validated successfully using the `eval_tool`. Please try ",
      "again."
    )
  }

  list(code = code, explanation = client$last_turn()@text)
}

#' Retrieve result
#'
#' From the `ellmer::chat()` object, passed as `client`, retrieve what is
#' considered the result of a conversation (given a block of type `x`).
#'
#' @param x An `llm_block_proxy` object used for dispatch
#' @param client A `ellmer::chat()` object
#'
#' @keywords internal
#' @export
extract_result <- function(x, client) {
  UseMethod("extract_result")
}

#' @export
extract_result.llm_block_proxy <- function(x, client) {

  extractor <- blockr_option(
    "result_callback",
    if ("eval_tool" %in% names(client$get_tools())) {
      eval_tool_code
    } else {
      last_turn_structured
    }
  )

  res <- extractor(client)

  stopifnot(
    is.list(res),
    setequal(names(res), c("code", "explanation")),
    is.character(res[["code"]]),
    is.character(res[["explanation"]])
  )

  res[["code"]] <- style_code(res[["code"]])

  log_debug(
    "\n---------------- response code ----------------\n\n",
    res[["code"]],
    "\n",
    asis = TRUE
  )

  log_trace(
    "\n------------- response explanation ------------\n\n",
    res[["explanation"]],
    "\n"
  )

  log_debug(
    "\n-----------------------------------------------\n\n"
  )

  res
}

#' @export
extract_result.llm_insights_block_proxy <- function(x, client) {

  res <- last_turn(client)

  log_debug(
    "\n------------- response explanation ------------\n\n",
    res,
    "\n",
    "\n-----------------------------------------------\n\n"
  )

  res
}

setup_client_observer <- function(client, session) {
  observeEvent(
    get_board_option_or_null("llm_model", session),
    {
      chat <- get_board_option_value("llm_model", session)
      shinychat::chat_clear("chat", session)
      client(chat())
    }
  )
}

setup_chat_observer <- function(rv_msgs, client, session) {

  observeEvent(
    TRUE,
    {
      msg <- split_messages(rv_msgs())

      if (not_null(msg[["current"]])) {
        shinychat::update_chat_user_input(
          "chat",
          value = msg[["current"]][["content"]],
          session = session
        )
      }

      hist <- msg[["history"]]

      if (not_null(msg[["history"]])) {
        client()$set_turns(
          map(
            ellmer::Turn,
            lst_xtr(hist, "role"),
            lst_xtr(hist, "content")
          )
        )
      }
    },
    once = TRUE
  )
}

chat_input_observer <- function(x, client, task, input, rv_msgs, rv_cond,
                                r_datasets = NULL) {

  observeEvent(input$chat_user_input, {

    if (not_null(r_datasets)) {
      dat <- r_datasets()
    } else {
      dat <- list()
    }

    cur <- rv_msgs()
    new <- list(
      list(role = "user", content = input$chat_user_input)
    )

    if (length(cur) && last(cur)[["role"]] == "user") {
      rv_msgs(c(cur[-length(cur)], new))
    } else {
      rv_msgs(c(cur, new))
    }

    if (not_null(r_datasets) && (length(dat) == 0 || any(lengths(dat) == 0))) {

      if (length(dat)) {
        msg <- paste(
          "Incomplete data:",
          paste0(names(dat), " (", lengths(dat), ")", collapse = ", "),
          "."
        )
      } else {
        msg <- "No data available."
      }

      log_warn(msg)
      rv_cond$warning <- msg

    } else {

      rv_cond$warning <- character()

      tools <- llm_tools(x, dat)

      query_llm_with_tools(
        client = client(),
        task = task,
        user_prompt = input$chat_user_input,
        system_prompt = system_prompt(x, dat, tools),
        tools = tools
      )
    }
  })
}

try_extract_result <- function(x, client, task, success) {

  res <- try(task$result(), silent = TRUE)

  if (success && !inherits(res, "try-error")) {

    res <- try(extract_result(x, client), silent = TRUE)

    if (inherits(res, "try-error")) {

      msg <- extract_try_error(res)
      log_error("Error encountered during result extraction: ", msg)

      res <- structure(msg, class = "try-error")
    }

  } else if (inherits(res, "try-error")) {

    msg <- extract_try_error(res)
    log_error("Error encountered during chat: ", msg)

    res <- structure(msg, class = "try-error")

  } else {

    res <- structure(
      "Result extraction error (unknown reason).",
      class = "try-error"
    )
  }

  res
}
