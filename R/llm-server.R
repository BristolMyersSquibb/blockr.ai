#' @rdname new_llm_block
#' @export
llm_block_server <- function(x) {
  UseMethod("llm_block_server", x)
}

#' @rdname new_llm_block
#' @export
llm_block_server.llm_block_proxy <- function(x) {

  result_ptype <- result_ptype(x)
  result_base_class <- last(class(result_ptype))

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

        observeEvent(input$chat_user_input, {

          dat <- r_datasets()

          if (length(dat) == 0 || any(lengths(dat) == 0)) {

            rv_cond$warning <- paste(
              "No (or incomplete data) is currently available. Not continuing",
              "until this is resolved."
            )

          } else {

            rv_cond$warning <- character()

            user_prompt <- input$chat_user_input
            system_prompt <- system_prompt(x, dat)
            tools <- llm_tools(x, dat)

            system_prompt <- paste0(
              system_prompt,
              "\n\n",
              paste0(
                filter(has_length, lapply(tools, get_prompt)),
                collapse = "\n"
              )
            )

            log_wrap(
              "\n----------------- user prompt -----------------\n\n",
              user_prompt,
              "\n",
              "\n---------------- system prompt ----------------\n\n",
              system_prompt,
              "\n",
              level = "debug"
            )

            client$set_system_prompt(system_prompt)
            client$set_tools(lapply(tools, get_tool))

            task$invoke(client, "chat", user_prompt)
          }
        })

        observe(
          {
            res <- try(task$result(), silent = TRUE)

            if (inherits(res, "try-error")) {

              msg <- extract_try_error(res)
              log_error("Error encountered during chat: ", msg)
              rv_cond$error <- msg

            } else {

              rv_cond$error <- character()

              rv_code(style_code(res$code))
              rv_expl(res$explanation)
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
            res <- try_eval_code(input$code_editor, r_datasets())
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

        output$result_is_available <- reactive(
          length(rv_code()) > 0 && any(nzchar(rv_code()))
        )

        outputOptions(
          output,
          "result_is_available",
          suspendWhenHidden = FALSE
        )

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
