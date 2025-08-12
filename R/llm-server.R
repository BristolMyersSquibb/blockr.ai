#' @rdname new_llm_block
#' @export
llm_block_server <- function(x) {
  UseMethod("llm_block_server", x)
}

#' @rdname new_llm_block
#' @export
llm_block_server.llm_block_proxy <- function(x) {

  result_ptype <- result_ptype(x)
  result_base_class <- class(result_ptype)[1]  # Get first class, not last

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
        rv_image_content <- reactiveVal(NULL)
        rv_cond <- reactiveValues(
          error = character(),
          warning = character(),
          message = character()
        )

        # Handle image upload if enabled
        if (x[["enable_image_upload"]]) {
          observeEvent(input$image_upload, {
            if (!is.null(input$image_upload)) {
              file_path <- input$image_upload$datapath
              if (file.exists(file_path)) {
                tryCatch({
                  # Use ellmer to process the image
                  image_content <- ellmer::content_image_file(file_path)
                  rv_image_content(image_content)
                  log_debug("Image uploaded successfully: ", input$image_upload$name)
                }, error = function(e) {
                  rv_cond$warning <- paste("Error processing image:", conditionMessage(e))
                  log_error("Image processing error: ", conditionMessage(e))
                })
              }
            } else {
              rv_image_content(NULL)
            }
          })
          
          observeEvent(input$remove_image, {
            rv_image_content(NULL)
          })
        }

        observeEvent(
          input$ask,
          {
            dat <- r_datasets()

            req(
              input$question,
              dat,
              length(dat) > 0,
              all(lengths(dat) > 0)
            )

            result <- query_llm_with_retry(
              datasets = dat,
              user_prompt = input$question,
              system_prompt = system_prompt(x, dat, has_image = !is.null(rv_image_content())),
              block_proxy = x,
              image_content = rv_image_content(),
              max_retries = x[["max_retries"]],
              progress = TRUE
            )

            if ("error" %in% names(result)) {
              rv_cond$error <- result$error
              rv_cond$warning <- character()
            } else {
              # Validation already happened in retry loop
              rv_cond$error <- character()
              rv_cond$warning <- character()
            }

            rv_code(result$code)
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
              rv_cond$error <- paste0(
                "Encountered an error evaluating code: ", res
              )
            } else {
              rv_code(input$code_editor)
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
