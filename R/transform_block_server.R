# transform_block_server is called from new_llm_transform_block() and its
# environment is tweaked there so it can access the args. We define
# global variables to avoid a note
globalVariables(c("question", "max_retries"))
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
      metadata <- reactive({
        req(length(datasets()) > 0)
        m <- make_metadata(datasets())
        print(m)
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
          response <- query_llm(input$question, metadata())
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
      output$code_display <- renderText({
        # Format the code nicely
        format_generated_code(req(current_code()))
      })

      # Render explanation
      output$explanation <- renderText({
        req(stored_response())
        stored_response()$explanation
      })

      list(
        expr = reactive({
          return_result_if_success(
            result = execution_result(),
            code = req(current_code())
          )
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
