#' @rdname new_llm_block
#' @export
new_llm_data_block <- function(...) {
  new_llm_block(c("llm_data_block", "data_block"), ...)
}

#' @export
result_ptype.llm_data_block_proxy <- function(x) {
  data.frame()
}

#' @rdname system_prompt
#' @export
system_prompt.llm_data_block_proxy <- function(x, datasets, ...) {

  paste0(
    NextMethod(),
    "\n\n",
    "Your task is to create a dataset according to user instruction.\n",
    "The dataset is to be created using R code. If you make use of",
    "random number generation, make sure to set a seed beforehand in order",
    "to make your results reproducible.\n\n",
    "Example of good code you might write:\n",
    "set.seed(11)\n",
    "data.frame(\n",
    "  a = sample(letters, 100, replace = TRUE),\n",
    "  b = runif(100),\n",
    "  c = seq.int(length.out = 100)\n",
    ")\n\n",
    "Important: make sure that your code always returns a data.frame.\n"
  )
}

#' @rdname new_llm_block
#' @export
llm_block_server.llm_data_block_proxy <- function(x) {

  function(id) {
    moduleServer(
      id,
      function(input, output, session) {

        task <- setup_chat_task(session)

        task_ready <- reactive(
          switch(task$status(), error = FALSE, success = TRUE, NULL)
        )

        client <- reactiveVal()

        setup_client_observer(client, session)

        observeEvent(
          get_board_option_or_default("dark_mode"),
          shinyAce::updateAceEditor(
            session,
            "code_editor",
            theme = switch(
              get_board_option_or_default("dark_mode"),
              light = "katzenmilch",
              dark = "dracula"
            )
          )
        )

        rv_code <- reactiveVal()
        rv_msgs <- reactiveVal(x[["messages"]])

        rv_cond <- reactiveValues(
          error = character(),
          warning = character(),
          message = character()
        )

        setup_chat_observer(rv_msgs, client, session)
        chat_input_observer(x, client, task, input, rv_msgs, rv_cond)

        observeEvent(
          task_ready(),
          {
            res <- try_extract_result(x, client(), task, task_ready())

            if (inherits(res, "try-error")) {

              rv_cond$error <- extract_try_error(res)

            } else {

              rv_cond$error <- character()

              new_turn <- list(
                list(role = "assistant", content = res$explanation)
              )

              rv_msgs(c(rv_msgs(), new_turn))
              rv_code(res$code)
            }
          }
        )

        observeEvent(
          rv_code(),
          shinyAce::updateAceEditor(
            session,
            "code_editor",
            value = rv_code()
          )
        )

        observeEvent(
          input$code_editor,
          {
            req(input$code_editor)
            res <- try_eval_code(x, input$code_editor)
            if (inherits(res, "try-error")) {
              rv_cond$error <- paste0(
                "Encountered an error evaluating code: ", res
              )
            } else {
              rv_code(style_code(input$code_editor))
              rv_cond$error <- character()
            }
          }
        )

        list(
          expr = reactive(str2expression(rv_code())),
          state = list(
            messages = rv_msgs,
            code = rv_code
          ),
          cond = rv_cond
        )
      }
    )
  }
}

#' @rdname new_llm_tool
#' @export
llm_tools.llm_block_proxy <- function(x, ...) {
  blockr_option(
    "llm_tools",
    list(
      new_eval_tool(x, ...),
      new_help_tool(x, ...)
    )
  )
}
