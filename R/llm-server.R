#' @rdname new_llm_block
#' @export
llm_block_server <- function(x) {
  UseMethod("llm_block_server", x)
}

#' @rdname new_llm_block
#' @export
llm_block_server.llm_block_proxy <- function(x) {

  function(id, data = NULL, ...args = list()) {
    moduleServer(
      id,
      function(input, output, session) {

        client <- chat_dispatch()
        task <- setup_chat_task(session)

        task_ready <- reactive(
          switch(task$status(), error = FALSE, success = TRUE, NULL)
        )

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

        r_datasets <- reactive(
          c(
            if (is.reactive(data) && !is.null(data())) list(data = data()),
            if (is.reactivevalues(...args)) reactiveValuesToList(...args)
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
        chat_input_observer(x, client, task, input, r_datasets, rv_msgs,
                            rv_cond)

        observeEvent(
          task_ready(),
          {
            res <- try(task$result(), silent = TRUE)

            if (task_ready() && !inherits(res, "try-error")) {

              rv_cond$error <- character()

              res <- try(extract_result(client), silent = TRUE)

              if (inherits(res, "try-error")) {

                msg <- extract_try_error(res)
                log_error("Error encountered during result extraction: ", msg)
                rv_cond$error <- msg

              } else {

                log_debug(
                  "\n---------------- response code ----------------\n\n",
                  res$code,
                  "\n",
                  asis = TRUE
                )

                log_trace(
                  "\n------------- response explanation ------------\n\n",
                  res$explanation,
                  "\n"
                )

                log_debug(
                  "\n-----------------------------------------------\n\n"
                )

                rv_msgs(
                  c(
                    rv_msgs(),
                    list(
                      list(
                        role = "assistant",
                        content = res$explanation
                      )
                    )
                  )
                )

                rv_code(res$code)
              }

            } else {

              if (inherits(res, "try-error")) {

                msg <- extract_try_error(res)
                log_error("Error encountered during chat: ", msg)
                rv_cond$error <- msg

              } else {

                rv_cond$error <- character()
              }
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
            res <- try_eval_code(x, input$code_editor, r_datasets())
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
