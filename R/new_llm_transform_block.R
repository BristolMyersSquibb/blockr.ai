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

          # Function to execute code with retry logic
          execute_code <- function(code, datasets, max_retries) {
            for(i in 1:max_retries) {
              tryCatch({
                # Create environment with datasets
                env <- list2env(datasets)
                # Execute code
                result <- eval(parse(text = code), envir = env)
                # If we get here, code executed successfully
                warning("Code execution successful:\n", code)
                return(list(success = TRUE, code = code, result = result))
              }, error = function(e) {
                if(i == max_retries) {
                  warning("Code execution failed after ", max_retries, " attempts:\n",
                          "Last code:\n", code, "\nError: ", e$message)
                  return(list(success = FALSE, error = e$message))
                }
                warning("Code execution attempt ", i, " failed:\n",
                        "Code:\n", code, "\nError: ", e$message)
                # Query LLM with error
                response <- query_llm(current_question(), metadata(), e$message)
                code <- response$code
                current_code(code)
              })
            }
            # If we get here, max retries reached
            warning("Maximum retries reached. Last code:\n", code)
            return(list(success = FALSE, error = "Maximum retries reached"))
          }

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
            req(current_code())
            # Format the code nicely
            code <- current_code()
            if (nchar(code) > 0) {
              formatR::tidy_source(text = code, output = FALSE)$text.tidy
            } else {
              "No code generated yet"
            }
          })

          # Render explanation
          output$explanation <- renderText({
            req(stored_response())
            stored_response()$explanation
          })

          list(
            expr = reactive({
              req(current_code())
              result <- execution_result()
              warning("Expression status: ", result$success,
                      "\nFinal code:\n", current_code())
              if (isTRUE(result$success)) {
                result$result  # Return the cached result
              } else {
                data.frame()  # Return empty dataframe on error
              }
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
    function(ns, question = "", code = "", store = FALSE) {
      tagList(
        shinyjs::useShinyjs(),
        # Styling
        tags$style(HTML("
          .llm-block {
            border: 1px solid #e0e0e0;
            border-radius: 8px;
            padding: 15px;
            background: #ffffff;
          }
          .llm-response {
            margin-top: 15px;
          }
          .llm-details {
            border: 1px solid #e0e0e0;
            border-radius: 4px;
            margin-top: 10px;
          }
          .llm-details summary {
            padding: 8px;
            background: #f8f9fa;
            cursor: pointer;
          }
          .llm-details summary:hover {
            background: #e9ecef;
          }
          .llm-code {
            background-color: #f5f5f5;
            padding: 10px;
            border-radius: 4px;
            font-family: monospace;
          }
          .llm-progress {
            margin-top: 10px;
            display: none;
          }
          .llm-progress.active {
            display: block;
          }
        ")),

        div(
          class = "llm-block",
          # Question input section
          textAreaInput(
            ns("expression", "question"),
            "Question",
            value = question,
            rows = 3,
            resize = "vertical"
          ),

          # Controls section
          div(
            style = "display: flex; gap: 10px; align-items: center;",
            actionButton(
              ns("expression", "ask"),
              "Ask",
              class = "btn-primary"
            ),
            checkboxInput(
              ns("expression", "store"),
              "Store Response",
              value = store
            )
          ),

          # Progress indicator
          div(
            class = "llm-progress",
            id = ns("expression", "progress_container"),
            div(
              class = "progress",
              div(
                class = "progress-bar progress-bar-striped active",
                role = "progressbar",
                style = "width: 100%"
              )
            ),
            p("Thinking...", style = "text-align: center; color: #666;")
          ),

          # Response section
          div(
            class = "llm-response",
            # Explanation details
            tags$details(
              class = "llm-details",
              open = TRUE,  # Open by default
              tags$summary("Explanation"),
              div(
                style = "padding: 10px;",
                textOutput(ns("expression", "explanation"))
              )
            ),

            # Code details
            tags$details(
              class = "llm-details",
              open = TRUE,  # Open by default
              tags$summary("Generated Code"),
              tags$pre(
                class = "llm-code",
                textOutput(ns("expression", "code_display"))
              )
            )
          )
        )
      )
    },
    class = "llm_transform_block",
    ...
  )
}
