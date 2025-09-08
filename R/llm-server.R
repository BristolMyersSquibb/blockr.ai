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
        rv_expl <- reactiveVal(x[["explanation"]])
        rv_cond <- reactiveValues(
          error = character(),
          warning = character(),
          message = character()
        )

        client <- chat_dispatch()
        task <- setup_chat_task(session)

        task_ready <- reactive(
          switch(task$status(), error = FALSE, success = TRUE, NULL)
        )

        expl <- x[["explanation"]]
        qest <- x[["question"]]

        if (length(qest) && nchar(qest) && !(length(expl) && nchar(expl))) {
          shinychat::update_chat_user_input(
            "chat",
            value = qest
          )
        }

        observeEvent(input$chat_user_input, {

          dat <- r_datasets()

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

            log_warning(msg)
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

              res <- client$last_turn()@text |>
                client$chat_structured(type = type_response())

              code <- style_code(res$code)

              log_wrap(
                "\n------------- response explanation ------------\n\n",
                res$explanation,
                "\n",
                level = "debug"
              )

              log_asis(
                "\n---------------- response code ----------------\n\n",
                code,
                "\n\n",
                level = "debug"
              )

              rv_code(code)
              rv_expl(res$explanation)

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

        output$explanation <- renderUI(markdown(rv_expl()))

        list(
          expr = reactive(str2expression(rv_code())),
          state = list(
            question = reactive(input$chat_user_input),
            code = rv_code,
            explanation = rv_expl
          ),
          cond = rv_cond
        )
      }
    )
  }
}
