# transform_block_server is called from new_llm_transform_block() and its
# environment is tweaked there so it can access the args. We define
# global variables to avoid a note
globalVariables(c("question", "max_retries", "code", "store"))
transform_block_server <- function(id, ...args) {
  # globals
  make_metadata <- getOption("blockr.ai.make_meta_data", make_metadata_default)
  moduleServer(
    id,
    function(input, output, session) {
      # reactives --------------------------------------------------------------
      r_datasets <- reactive(reactiveValuesToList(...args))
      r_datasets_renamed <- reactive(rename_datasets(r_datasets()))
      r_code_prefix <- reactive(build_code_prefix(r_datasets())) # the dataset_1 <- `1` part
      r_metadata <- reactive({
        req(length(r_datasets_renamed()) > 0)
        make_metadata(r_datasets_renamed())
      })

      # reactive values --------------------------------------------------------
      rv_result <- reactiveVal(NULL)
      rv_code <- reactiveVal(code)
      rv_explanation <- reactiveVal(NULL)
      rv_error <- reactiveVal(NULL)
      #current_question <- reactiveVal(question)

      # observers --------------------------------------------------------------
      observeEvent(input$ask, {
        req(input$question)

        # Show progress
        shinyjs::show(id = "progress_container", anim = TRUE)

        # Execute code with retry logic and store result
        result_code_explanation_error <- query_llm_and_execute_with_retries(
          datasets = r_datasets_renamed(),
          question = input$question,
          metadata = r_metadata(),
          plot = FALSE,
          max_retries = max_retries
        )
        rv_result(result_code_explanation_error$result)
        rv_code(result_code_explanation_error$code)
        rv_explanation(result_code_explanation_error$explanation)
        rv_error(result_code_explanation_error$error)

        # Hide progress
        shinyjs::hide(id = "progress_container", anim = TRUE)

        if (is.null(rv_result())) {
          showNotification(rv_error(), type = "error")
        }
      })

      # Dynamic UI -------------------------------------------------------------
      # Add code display output
      output$code_display <- renderUI({
        fixed_ace_editor(rv_code())
      })

      # Render explanation
      output$explanation <- renderText({
        rv_explanation()
      })

      output$result_is_available <- reactive({
        !is.null(rv_result())
      })
      outputOptions(output, "result_is_available", suspendWhenHidden = FALSE)

      # Output -----------------------------------------------------------------
      list(
        expr = reactive({
          req(rv_result())
          out <- str2lang(sprintf(
            "{%s\n%s}",
            r_code_prefix(),
            rv_code()
            ))
          attr(out, "result") <- rv_result()
          out
        }),
        state = list(
          question = reactive(input$question),
          code = reactive(rv_code()),
          store = reactive(input$store),
          max_retries = reactive(max_retries)
        )
      )
    }
  )
}
