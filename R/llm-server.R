#' @param x Proxy LLM block object
#' @rdname new_llm_block
#' @export
llm_block_server <- function(x) {
  UseMethod("llm_block_server", x)
}

#' @rdname new_llm_block
#' @export
llm_block_server.llm_block_proxy <- function(x) {

  function(id, data, ...args) {
    moduleServer(
      id,
      function(input, output, session) {

        r_datasets <- reactive(
        	c(list(data = data()), reactiveValuesToList(...args))
        )

        rv_code <- reactiveVal()
        rv_expl <- reactiveVal(x[["explanation"]])
        rv_cond <- reactiveValues(
      		error = character(),
      		warning = character(),
      		message = character()
        )

        observeEvent(
          input$ask,
          {
          	dat <- r_datasets()
            req(input$question)
            req(dat[["data"]])

            # Show progress
            shinyjs::show(id = "progress_container", anim = TRUE)

            # Execute code with retry logic and store result
            result <- query_llm_with_retry(
              datasets = dat,
              user_prompt = input$question,
              system_prompt = system_prompt(x, dat),
              max_retries = x[["max_retries"]]
            )

            # Hide progress
            shinyjs::hide(id = "progress_container", anim = TRUE)

            if (!is.null(result$error)) {
              showNotification(result$error, type = "error")
            }

            rv_code(paste(result$code, collapse = "\n"))
            rv_expl(result$explanation)
          }
        )

        observeEvent(
          rv_code(),
          shinyAce::updateAceEditor(
            session,
            "code_editor",
            value = style_code(rv_code())
          )
        )

        observeEvent(
          input$code_editor,
          {
            res <- try_eval_code(input$code_editor, r_datasets())
            if (inherits(res, "try-error")) {
            	rv_cond$warning <- paste0(
            		"Encountered an error evaluating code: ", res
            	)
            } else {
              rv_code(input$code_editor)
              rv_cond$warning <- character()
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
            question = reactive(input$question),
            code = rv_code,
            explanation = rv_expl,
            max_retries = x[["max_retries"]]
          ),
          cond = rv_cond
        )
      }
    )
  }
}

