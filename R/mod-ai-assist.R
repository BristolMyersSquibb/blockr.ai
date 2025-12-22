#' AI Assist Module for Block Argument Discovery
#'
#' A reusable Shiny module that provides AI-powered argument discovery
#' for blockr blocks. Uses shinychat for a conversational interface where
#' users can describe what they want in natural language.
#'
#' @param id Module namespace ID
#' @param placeholder Placeholder text for the chat input
#' @param collapsed Logical. If TRUE (default), section starts collapsed
#'
#' @return UI: tagList with collapsible chat section
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
    placeholder = "e.g., keep only setosa species",
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
        tags$span(
          class = if (collapsed) "ai-chevron" else "ai-chevron rotated",
          "\u203A"
        ),
        bsicons::bs_icon("stars", class = "ai-icon"),
        span("Ask AI to configure this block")
      ),

      # Collapsible content
      div(
        id = ns("content"),
        class = if (collapsed) "ai-assist-content-wrapper ai-collapsed" else "ai-assist-content-wrapper",

        div(
          class = "ai-assist-content",

          # Shinychat interface
          shinychat::chat_ui(
            ns("chat"),
            width = "100%",
            height = "auto",
            placeholder = placeholder
          )
        )
      )
    )
  )
}


#' AI Assist Module Server
#'
#' Server logic for the AI assist module. Handles chat messages,
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
    get_current_args = NULL,
    model = blockr.core::blockr_option("ai_model", "gpt-4o-mini"),
    max_iterations = 5
) {

  moduleServer(id, function(input, output, session) {
    ns <- session$ns

    # Handle chat input
    observeEvent(input$chat_user_input, {
      prompt <- input$chat_user_input

      if (is.null(prompt) || nchar(trimws(prompt)) == 0) {
        return()
      }

      # Get current data
      data <- tryCatch(
        get_data(),
        error = function(e) NULL
      )

      if (is.null(data) || !is.data.frame(data) || nrow(data) == 0) {
        shinychat::chat_append(
          "chat",
          "No data available. Please ensure data is connected to this block.",
          session = session
        )
        return()
      }

      # Build context-aware prompt with current configuration
      context_prompt <- prompt

      if (!is.null(get_current_args)) {
        current_args <- tryCatch(get_current_args(), error = function(e) NULL)
        if (!is.null(current_args) && length(current_args) > 0) {
          args_text <- paste(capture.output(str(current_args, max.level = 2)), collapse = "\n")
          context_prompt <- paste0(
            prompt, "\n\n",
            "Current block configuration:\n```r\n", args_text, "\n```\n",
            "Modify the configuration based on the user's request."
          )
        }
      }

      # Run discovery (non-streaming)
      result <- tryCatch(
        {
          discover_block_args(
            prompt = context_prompt,
            data = data,
            block_ctor = block_ctor,
            block_name = block_name,
            max_iterations = max_iterations,
            model = model,
            verbose = FALSE
          )
        },
        error = function(e) {
          list(success = FALSE, error = conditionMessage(e))
        }
      )

      # Handle result
      if (isTRUE(result$success) && !is.null(result$args)) {
        # Success - invoke callback to wire args to block
        tryCatch(
          {
            on_apply(result$args)
            shinychat::chat_append(
              "chat",
              "Done! I've updated the configuration.",
              session = session
            )
          },
          error = function(e) {
            shinychat::chat_append(
              "chat",
              paste("Failed to apply:", conditionMessage(e)),
              session = session
            )
          }
        )
      } else {
        # Error - show message
        error_msg <- result$error %||% "I couldn't figure out the right configuration. Could you try rephrasing?"
        shinychat::chat_append(
          "chat",
          error_msg,
          session = session
        )
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
      margin-left: -16px;
      margin-right: -16px;
      padding-left: 16px;
      padding-right: 16px;
      border-bottom: 1px solid #dee2e6;
      padding-bottom: 12px;
    }

    .ai-assist-toggle {
      cursor: pointer;
      user-select: none;
      padding: 4px 0;
      display: flex;
      align-items: center;
      gap: 6px;
      font-size: 0.8rem;
      color: #6c757d;
    }

    .ai-assist-toggle:hover {
      color: #495057;
    }

    .ai-icon {
      font-size: 0.75rem;
    }

    .ai-chevron {
      transition: transform 0.2s;
      display: inline-block;
      font-size: 14px;
      font-weight: bold;
      color: #6c757d;
    }

    .ai-chevron.rotated {
      transform: rotate(90deg);
    }

    .ai-assist-content-wrapper {
      max-height: 400px;
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

    /* Make chat start compact and grow with content */
    .ai-assist-content .chat-container {
      height: auto !important;
      min-height: 0 !important;
      max-height: 300px;
      display: flex;
      flex-direction: column;
    }

    .ai-assist-content .chat-messages {
      flex: 1 1 auto;
      min-height: 0;
      max-height: 240px;
      overflow-y: auto;
    }

    .ai-assist-content .chat-input-container {
      flex: 0 0 auto;
    }
    "
  ))
}
