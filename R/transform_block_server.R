# transform_block_server is called from new_llm_transform_block() and its
# environment is tweaked there so it can access the args. We define
# global variables to avoid a note
globalVariables(c("question", "max_retries", "code"))
transform_block_server <- function(id, ...args) {
  moduleServer(
    id,
    function(input, output, session) {
      # reactives --------------------------------------------------------------
      r_datasets <- reactive(reactiveValuesToList(...args))
      r_datasets_renamed <- reactive(rename_datasets(r_datasets()))
      r_code_prefix <- reactive(build_code_prefix(r_datasets())) # the dataset_1 <- `1` part
      r_system_prompt <- reactive({
        req(length(r_datasets_renamed()) > 0)
        transform_system_prompt(r_datasets_renamed())
      })

      # reactive values --------------------------------------------------------
      rv_result <- reactiveVal(NULL)

      # observers --------------------------------------------------------------
      observeEvent(input$ask, {
        req(input$question)

        # Show progress
        shinyjs::show(id = "progress_container", anim = TRUE)

        # Execute code with retry logic and store result
        result <- query_llm_and_run_with_retries(
          datasets = r_datasets_renamed(),
          user_prompt = input$question,
          system_prompt = r_system_prompt(),
          max_retries = max_retries
        )
        rv_result(result)

        # Hide progress
        shinyjs::hide(id = "progress_container", anim = TRUE)

        if (!is.null(rv_result()$error)) {
          showNotification(rv_result()$error, type = "error")
        }
      })

      # Dynamic UI -------------------------------------------------------------
      # Add code display output
      output$code_display <- renderUI({
        fixed_ace_editor(rv_result()$code)
      })

      # Render explanation
      output$explanation <- renderUI({
        markdown(rv_result()$explanation)
      })

      output$result_is_available <- reactive({
        !is.null(rv_result()$value)
      })
      outputOptions(output, "result_is_available", suspendWhenHidden = FALSE)

      # Output -----------------------------------------------------------------
      list(
        expr = reactive({
          req(rv_result()$value)
          out <- str2lang(sprintf(
            "{%s\n%s}",
            r_code_prefix(),
            rv_result()$code
            ))
          attr(out, "result") <- rv_result()$value
          out
        }),
        state = list(
          question = reactive(input$question),
          code = reactive(rv_result()$code),
          max_retries = reactive(max_retries)
        )
      )
    }
  )
}
