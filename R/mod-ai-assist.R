#' AI Assist Module for Block Argument Discovery
#'
#' A reusable Shiny module that provides AI-powered argument discovery
#' for blockr blocks. Shows a collapsible text input where users can
#' describe what they want, and an "Apply" button that uses the LLM
#' to figure out the correct block arguments.
#'
#' @param id Module namespace ID
#' @param placeholder Placeholder text for the input field
#' @param collapsed Logical. If TRUE (default), section starts collapsed
#'
#' @return UI: tagList with collapsible section
#'
#' @examples
#' \dontrun{
#' # In block UI:
#' mod_ai_assist_ui(NS(id, "ai"))
#' }
#'
#' @export
mod_ai_assist_ui <- function(
    id,
    placeholder = "Describe what you want... (e.g., keep only rows where Time is greater than 3)",
    collapsed = TRUE
) {
  ns <- NS(id)

  tagList(
    # CSS for collapsible section
    css_ai_assist(),

    # Inject shinyjs for show/hide functionality
    shinyjs::useShinyjs(),

    div(
      class = "ai-assist-section",

      # Toggle header (clickable)
      div(
        class = "ai-assist-toggle",
        id = ns("toggle"),
        onclick = sprintf(
          "var content = document.getElementById('%s');
           var chevron = this.querySelector('.ai-chevron');
           if (content.classList.contains('ai-collapsed')) {
             content.classList.remove('ai-collapsed');
             chevron.classList.add('rotated');
           } else {
             content.classList.add('ai-collapsed');
             chevron.classList.remove('rotated');
           }",
          ns("content")
        ),
        span(
          class = if (collapsed) "ai-chevron" else "ai-chevron rotated",
          HTML("&#9654;")
        ),
        icon("wand-magic-sparkles", class = "ai-icon"),
        span("Ask AI to configure this block")
      ),

      # Collapsible content
      div(
        id = ns("content"),
        class = if (collapsed) "ai-assist-content-wrapper ai-collapsed" else "ai-assist-content-wrapper",

        div(
          class = "ai-assist-content",

          # Text input for prompt
          textAreaInput(
            ns("prompt"),
            label = NULL,
            placeholder = placeholder,
            rows = 2,
            width = "100%"
          ),

          # Apply button + loading indicator
          div(
            class = "ai-assist-actions",
            actionButton(
              ns("apply"),
              label = "Apply",
              class = "btn btn-primary btn-sm ai-apply-btn"
            ),

            # Loading spinner (hidden by default)
            shinyjs::hidden(
              span(
                id = ns("loading"),
                class = "ai-assist-loading",
                icon("spinner", class = "fa-spin"),
                " Thinking..."
              )
            )
          ),

          # Error message area (hidden by default)
          shinyjs::hidden(
            div(
              id = ns("error"),
              class = "ai-assist-error",
              uiOutput(ns("error_msg"))
            )
          )
        )
      )
    )
  )
}


#' AI Assist Module Server
#'
#' Server logic for the AI assist module. Handles the "Apply" button click,
#' calls `discover_block_args()` to get the correct arguments, and invokes
#' the `on_apply` callback with the discovered arguments.
#'
#' @param id Module namespace ID
#' @param get_data Reactive function that returns the input data.frame
#' @param block_ctor Block constructor function (e.g., new_filter_block)
#' @param block_name Character string name of the block (for LLM prompt)
#' @param on_apply Callback function that receives discovered args.
#'   Should map args to the block's reactive values.
#' @param model LLM model to use (default: "gpt-4o-mini")
#' @param max_iterations Maximum LLM iterations (default: 5)
#'
#' @return NULL (uses callback for communication)
#'
#' @examples
#' \dontrun{
#' # In block server:
#' mod_ai_assist_server(
#'   "ai",
#'   get_data = data,
#'   block_ctor = new_filter_block,
#'   block_name = "new_filter_block",
#'   on_apply = function(args) {
#'     r_conditions(args$conditions)
#'   }
#' )
#' }
#'
#' @export
mod_ai_assist_server <- function(
    id,
    get_data,
    block_ctor,
    block_name,
    on_apply,
    model = "gpt-4o-mini",
    max_iterations = 5
) {
  moduleServer(id, function(input, output, session) {
    ns <- session$ns

    # State
    r_loading <- reactiveVal(FALSE)
    r_error <- reactiveVal(NULL)

    # Update UI based on loading state
    observe({
      if (r_loading()) {
        shinyjs::disable("apply")
        shinyjs::show("loading")
      } else {
        shinyjs::enable("apply")
        shinyjs::hide("loading")
      }
    })

    # Update UI based on error state
    observe({
      err <- r_error()
      if (is.null(err)) {
        shinyjs::hide("error")
      } else {
        shinyjs::show("error")
      }
    })

    # Render error message
    output$error_msg <- renderUI({
      err <- r_error()
      if (!is.null(err)) {
        div(
          class = "alert alert-warning",
          role = "alert",
          err
        )
      } else {
        NULL
      }
    })

    # Handle Apply button
    observeEvent(input$apply, {
      # Validate prompt
      prompt <- input$prompt
      if (is.null(prompt) || nchar(trimws(prompt)) == 0) {
        r_error("Please enter a description of what you want.")
        return()
      }

      # Clear previous error
      r_error(NULL)

      # Set loading state
      r_loading(TRUE)

      # Get current data
      data <- tryCatch(
        get_data(),
        error = function(e) NULL
      )

      if (is.null(data) || !is.data.frame(data) || nrow(data) == 0) {
        r_loading(FALSE)
        r_error("No data available. Please ensure data is connected to this block.")
        return()
      }

      message("AI Assist: Got data with ", nrow(data), " rows and ", ncol(data), " columns")
      message("AI Assist: Columns: ", paste(colnames(data), collapse = ", "))

      # Run discovery
      result <- tryCatch(
        {
          discover_block_args(
            prompt = prompt,
            data = data,
            block_ctor = block_ctor,
            block_name = block_name,
            max_iterations = max_iterations,
            model = model,
            verbose = TRUE
          )
        },
        error = function(e) {
          message("AI Assist error: ", conditionMessage(e))
          list(success = FALSE, error = conditionMessage(e))
        }
      )

      # Clear loading state
      r_loading(FALSE)

      message("AI Assist: Result success = ", result$success)
      if (!is.null(result$error)) message("AI Assist: Error = ", result$error)
      if (!is.null(result$args)) message("AI Assist: Args = ", paste(names(result$args), collapse = ", "))

      # Handle result
      if (isTRUE(result$success) && !is.null(result$args)) {
        # Success - invoke callback to wire args to block
        tryCatch(
          {
            on_apply(result$args)
            # Clear the prompt on success
            updateTextAreaInput(session, "prompt", value = "")
          },
          error = function(e) {
            r_error(paste("Failed to apply arguments:", conditionMessage(e)))
          }
        )
      } else {
        # Error - show message
        error_msg <- result$error %||% "Failed to discover block arguments. Please try rephrasing your request."
        r_error(error_msg)
      }
    })

    # Return nothing - communication is via callback
    invisible(NULL)
  })
}


#' CSS for AI Assist collapsible section
#'
#' Provides styling for the AI assistant module with collapsible toggle.
#'
#' @return HTML style tag
#' @noRd
css_ai_assist <- function() {
  tags$style(HTML(
    "
    .ai-assist-section {
      margin-bottom: 15px;
      border-bottom: 1px solid #dee2e6;
      padding-bottom: 5px;
    }

    .ai-assist-toggle {
      cursor: pointer;
      user-select: none;
      padding: 8px 0;
      display: flex;
      align-items: center;
      gap: 8px;
      font-size: 0.875rem;
      color: #5ab4ac;
      font-weight: 500;
    }

    .ai-assist-toggle:hover {
      color: #3d8b84;
    }

    .ai-icon {
      font-size: 0.875rem;
    }

    .ai-chevron {
      transition: transform 0.2s;
      display: inline-block;
      font-size: 10px;
      color: #6c757d;
    }

    .ai-chevron.rotated {
      transform: rotate(90deg);
    }

    .ai-assist-content-wrapper {
      max-height: 300px;
      overflow: hidden;
      transition: max-height 0.3s ease-in-out, opacity 0.2s ease-in-out;
      opacity: 1;
    }

    .ai-assist-content-wrapper.ai-collapsed {
      max-height: 0;
      opacity: 0;
    }

    .ai-assist-content {
      padding: 10px 0;
    }

    .ai-assist-content textarea {
      font-size: 0.875rem;
      resize: vertical;
      min-height: 60px;
    }

    .ai-assist-content .form-group {
      margin-bottom: 8px;
    }

    .ai-assist-actions {
      display: flex;
      align-items: center;
      gap: 12px;
    }

    .ai-apply-btn {
      background-color: #5ab4ac;
      border-color: #5ab4ac;
    }

    .ai-apply-btn:hover {
      background-color: #4a9e97;
      border-color: #4a9e97;
    }

    .ai-apply-btn:disabled {
      background-color: #8fccc6;
      border-color: #8fccc6;
    }

    .ai-assist-loading {
      color: #6c757d;
      font-size: 0.875rem;
    }

    .ai-assist-error {
      margin-top: 10px;
    }

    .ai-assist-error .alert {
      padding: 8px 12px;
      font-size: 0.875rem;
      margin-bottom: 0;
    }
    "
  ))
}
