# transform_block_server is called from new_llm_transform_block() and its
# environment is tweaked there so it can access the args. We define
# global variables to avoid a note
globalVariables(c("question", "max_retries", "code", "store"))
transform_block_server <- function(id, ...args) {
  moduleServer(
    id,
    function(input, output, session) {
      # capture the datasets into a list
      datasets <- reactive(reactiveValuesToList(...args))

      # Reactive values for state
      stored_response <- reactiveVal(NULL)
      current_code <- reactiveVal(code)
      current_question <- reactiveVal(question)

      # Generate metadata when datasets change
      make_metadata <- getOption("blockr.ai.make_meta_data", make_metadata_default)
      metadata <- reactive({
        req(length(datasets()) > 0)
        m <- make_metadata(datasets())
        m
      })

      # Cache for execution results
      execution_result <- reactiveVal(NULL)

      # Handle ask button click
      observeEvent(input$ask, {
        req(input$question)

        # Show progress
        shinyjs::show(id = "progress_container", anim = TRUE)

        # Query LLM if needed
        if (!input$store || is.null(stored_response())) {
          response <- query_llm(input$question, metadata(), names = create_dataset_aliases(names(datasets()))$names)
          stored_response(response)
        }

        # Use code directly from response
        code <- stored_response()$code
        current_code(code)
        current_question(input$question)

        # Execute code with retry logic and store result
        result <- execute_code(
          code,
          datasets(),
          max_retries,
          current_question(),
          metadata()
        )
        current_code(result$code)
        execution_result(result)

        # Hide progress
        shinyjs::hide(id = "progress_container", anim = TRUE)

        if (!result$success) {
          showNotification(result$error, type = "error")
        }
      })

      # Add code display output
      output$code_display <- renderUI({
        fixed_ace_editor(current_code())
      })

      # Render explanation
      output$explanation <- renderText({
        req(stored_response())
        stored_response()$explanation
      })

      output$result_is_available <- reactive({
        req(execution_result()$success)
      })
      outputOptions(output, "result_is_available", suspendWhenHidden = FALSE)

      list(
        expr = reactive({
          req(execution_result()$success)
          out <- str2lang(sprintf("{%s}", current_code()))
          attr(out, "result") <- execution_result()$result
          out
        }),
        state = list(
          question = reactive(current_question()),
          code = reactive(current_code()),
          store = reactive(input$store),
          max_retries = reactive(max_retries)
        )
      )
    }
  )
}
