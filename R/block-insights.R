#' @rdname new_llm_block
#' @export
new_llm_insights_block <- function(...) {
  new_llm_block("llm_insights_block", ..., code = "NULL")
}

#' @export
result_ptype.llm_insights_block_proxy <- function(x) {
  NULL
}

#' @export
block_ui.llm_insights_block <- function(id, x, ...) {
  tagList(
    uiOutput(NS(id, "result"))
  )
}

#' @export
block_output.llm_insights_block <- function(x, result, session) {
  renderUI(markdown(result))
}

#' @rdname system_prompt
#' @export
system_prompt.llm_insights_block_proxy <- function(x, datasets, tools, ...) {

  meta_builder <- blockr_option("make_meta_data", describe_inputs)

  if (!is.function(meta_builder)) {
    meta_builder <- get(meta_builder, mode = "function")
  }

  metadata <- meta_builder(datasets)

  if (length(tools)) {
    tool_prompt <- paste0(
      "You have available the following tools ",
      paste_enum(chr_ply(tools, function(x) x$tool@name)), ". ",
      "Make use of these tools as you see fit.\n"
    )
  } else {
    tool_prompt <- ""
  }

  tool_prompts <- filter(has_length, lapply(tools, get_prompt))

  paste0(
    "Your task is to examine datasets and create a report according ",
    "to user instructions.\n",
    tool_prompt,
    "Important: If decide to use a tool that accepts R code as input, make ",
    "sure to always use namespace prefixes whenever you call functions in ",
    "packages. Do not use library calls for attaching package namespaces.",
    "\n\n",
    "You have the following dataset", if (length(datasets) > 1L) "s",
    " at your disposal: ",
    paste(shQuote(names(datasets)), collapse = ", "), ".\n",
    metadata,
    "Be very careful to use only the provided names in your explanations ",
    "and code.\n",
    "This means you should not use generic names of undefined datasets ",
    "like `x` or `data` unless these are explicitly provided.\n",
    "You should not produce code to rebuild the input objects.",
    if (has_length(tool_prompts)) "\n\n",
    paste0(
      filter(has_length, lapply(tools, get_prompt)),
      collapse = "\n"
    ),
    "\n\n",
    "The user is most interested in a clear and concise description of input ",
    "datasets and code you may produce is only relevant for you to better ",
    "understand the data. Report back to the user a nicely written ",
    "description explaining the data and don't forget to cover aspects the ",
    "user specifically asked for.\n"
  )
}

#' @rdname new_llm_block
#' @export
llm_block_ui.llm_insights_block_proxy <- function(x) {

  function(id) {

    msg <- split_messages(x[["messages"]])

    shinychat::chat_ui(
      NS(id, "chat"),
      width = "100%",
      style = "max-height: 400px; overflow-y: auto;",
      messages = msg[["history"]]
    )
  }
}

#' @rdname new_llm_block
#' @export
llm_block_server.llm_insights_block_proxy <- function(x) {

  function(id, data = NULL, ...args = list()) {
    moduleServer(
      id,
      function(input, output, session) {

        client <- chat_dispatch()
        task <- setup_chat_task(session)

        task_ready <- reactive(
          switch(task$status(), error = FALSE, success = TRUE, NULL)
        )

        r_datasets <- reactive(
          c(
            if (is.reactive(data) && !is.null(data())) list(data = data()),
            if (is.reactivevalues(...args)) reactiveValuesToList(...args)
          )
        )

        rv_msgs <- reactiveVal(x[["messages"]])

        rv_cond <- reactiveValues(
          error = character(),
          warning = character(),
          message = character()
        )

        rv_res <- reactiveVal()

        setup_chat_observer(rv_msgs, client, session)
        chat_input_observer(x, client, task, input, r_datasets, rv_msgs,
                            rv_cond)

        observeEvent(
          task_ready(),
          {
            res <- try(task$result(), silent = TRUE)

            if (task_ready() && !inherits(res, "try-error")) {

              rv_cond$error <- character()

              res <- try(last_turn(client), silent = TRUE)

              if (inherits(res, "try-error")) {

                msg <- extract_try_error(res)
                log_error("Error encountered during result extraction: ", msg)
                rv_cond$error <- msg
                rv_res(NULL)

              } else {

                log_debug(
                  "\n------------- response explanation ------------\n\n",
                  res,
                  "\n",
                  "\n-----------------------------------------------\n\n"
                )

                rv_msgs(
                  c(
                    rv_msgs(),
                    list(
                      list(
                        role = "assistant",
                        content = res
                      )
                    )
                  )
                )

                rv_res(res)
              }

            } else {

              if (inherits(res, "try-error")) {

                msg <- extract_try_error(res)
                log_error("Error encountered during chat: ", msg)
                rv_cond$error <- msg
                rv_res(NULL)

              } else {

                rv_cond$error <- character()
              }
            }
          }
        )

        list(
          expr = rv_res,
          state = list(messages = rv_msgs),
          cond = rv_cond
        )
      }
    )
  }
}

#' @rdname new_llm_tool
#' @export
llm_tools.llm_insights_block_proxy <- function(x, ...) {
  blockr_option(
    "llm_tools",
    list(
      new_help_tool(x, ...),
      new_data_tool(x, ...)
    )
  )
}
