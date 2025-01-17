#' LLM Transform block constructor
#'
#' This block allows for transforming data using LLM-generated R code based on natural language questions
#'
#' @param question Initial question (optional)
#' @param code Initial code (optional)
#' @param store Whether to store and reuse previous LLM response
#' @param max_retries Maximum number of retries for code execution
#' @param ... Forwarded to [new_block()]
#'
#' @export
new_llm_transform_block <- function(question = character(),
                                    code = character(),
                                    store = FALSE,
                                    max_retries = 3,
                                    ...) {

  new_transform_block(
    function(...) {
      moduleServer(
        "expression",
        function(input, output, session) {

          # Reactive values for state
          stored_response <- reactiveVal(NULL)
          current_code <- reactiveVal(code)
          current_question <- reactiveVal(question)

          # Get all input datasets
          datasets <- reactive({
            # Convert list of reactives to list of actual data
            actual_data <- lapply(list(...), function(x) {
              if (is.reactive(x)) x() else x
            })
            actual_data <- name_unnamed_datasets(actual_data)
            actual_data
          })

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
            if(!input$store || is.null(stored_response())) {
              response <- query_llm(input$question, metadata())
              stored_response(response)
            }

            # Use code directly from response
            code <- stored_response()$code
            current_code(code)
            current_question(input$question)

            # Execute code with retry logic and store result
            result <- execute_code(code, datasets(), max_retries)
            execution_result(result)

            # Hide progress
            shinyjs::hide(id = "progress_container", anim = TRUE)

            if(!result$success) {
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
    },
    ui = transform_block_ui,
    class = "llm_transform_block",
    ...
  )
}
