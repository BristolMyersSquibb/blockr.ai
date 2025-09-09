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

        observeEvent(
          TRUE,
          {
            msg <- split_messages(rv_msgs())

            if (not_null(msg[["current"]])) {
              shinychat::update_chat_user_input(
                "chat",
                value = msg[["current"]][["content"]]
              )
            }

            hist <- msg[["history"]]

            if (not_null(msg[["history"]])) {
              client$set_turns(
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

        observeEvent(input$chat_user_input, {

          dat <- r_datasets()

          cur <- rv_msgs()
          new <- list(
            list(role = "user", content = input$chat_user_input)
          )

          if (last(cur)[["role"]] == "user") {
            rv_msgs(c(cur[-length(cur)], new))
          } else {
            rv_msgs(c(cur, new))
          }

          if (length(dat) == 0 || any(lengths(dat) == 0)) {

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

            query_llm_with_tools(
              client = client,
              task = task,
              user_prompt = input$chat_user_input,
              system_prompt = system_prompt(x, dat),
              tools = llm_tools(x, dat)
            )
          }
        })

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
