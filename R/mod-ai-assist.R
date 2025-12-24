#' AI Assist Module UI
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
    placeholder = "Describe what you want...",
    collapsed = TRUE
) {
  ns <- NS(id)

  tagList(
    css_ai_assist(),
    shinyjs::useShinyjs(),

    div(
      class = "ai-assist-section",

      # Toggle header (clickable)
      div(
        class = "ai-assist-toggle",
        id = ns("toggle"),
        onclick = sprintf(
          "var content = document.getElementById('%s');
           var icon = this.querySelector('.ai-icon');
           var chevron = this.querySelector('.ai-chevron');
           if (content.classList.contains('ai-collapsed')) {
             content.classList.remove('ai-collapsed');
             icon.classList.add('ai-active');
             chevron.classList.add('rotated');
           } else {
             content.classList.add('ai-collapsed');
             icon.classList.remove('ai-active');
             chevron.classList.remove('rotated');
           }",
          ns("content")
        ),
        bsicons::bs_icon("stars", class = if (collapsed) "ai-icon" else "ai-icon ai-active"),
        span("AI Assist"),
        tags$span(
          class = if (collapsed) "ai-chevron" else "ai-chevron rotated",
          "\u203A"
        )
      ),

      # Collapsible content
      div(
        id = ns("content"),
        class = if (collapsed) "ai-assist-content-wrapper ai-collapsed" else "ai-assist-content-wrapper",

        div(
          class = "ai-assist-content",

          shinychat::chat_ui(
            ns("chat"),
            width = "100%",
            height = "auto",
            placeholder = placeholder,
            icon_assistant = bsicons::bs_icon("stars", class = "chat-ai-icon")
          )
        )
      )
    )
  )
}


#' AI Assist Module Server
#'
#' Server logic for the AI assist module. Accepts reactiveVals directly
#' and updates them when the AI discovers new arguments.
#'
#' @param id Module namespace ID
#' @param data Reactive function that returns the input data.frame
#' @param args Named list of reactiveVal objects representing block arguments.
#'   The module reads current values and updates them after discovery.
#' @param block_ctor Block constructor function (e.g., new_head_block)
#' @param block_name Character string name of the block (for LLM prompt)
#' @param model LLM model to use (default from blockr.ai_model option)
#' @param max_iterations Maximum LLM iterations (default: 5)
#'
#' @return NULL (updates reactiveVals directly)
#'
#' @examples
#' \dontrun{
#' # In block server:
#' nrw <- reactiveVal(6L)
#' direction_val <- reactiveVal("head")
#'
#' mod_ai_assist_server(
#'   "ai",
#'   data = data,
#'   args = list(
#'     n = nrw,
#'     direction = direction_val
#'   ),
#'   block_ctor = new_head_block,
#'   block_name = "new_head_block"
#' )
#' }
#'
#' @export
mod_ai_assist_server <- function(
    id,
    data,
    args,
    block_ctor,
    block_name,
    model = blockr.core::blockr_option("ai_model", "gpt-4o-mini"),
    max_iterations = 5
) {

  moduleServer(id, function(input, output, session) {
    ns <- session$ns

    observeEvent(input$chat_user_input, {
      prompt <- input$chat_user_input

      if (is.null(prompt) || nchar(trimws(prompt)) == 0) {
        return()
      }

      # Get current data
      current_data <- tryCatch(
        data(),
        error = function(e) NULL
      )

      if (is.null(current_data) || !is.data.frame(current_data) || nrow(current_data) == 0) {
        shinychat::chat_append(
          "chat",
          "No data available. Please ensure data is connected to this block.",
          session = session
        )
        return()
      }

      # Read current values from reactiveVals
      current_args <- lapply(args, function(rv) rv())

      # Build context-aware prompt
      context_prompt <- prompt
      if (length(current_args) > 0) {
        args_text <- paste(capture.output(str(current_args, max.level = 2)), collapse = "\n")
        context_prompt <- paste0(
          prompt, "\n\n",
          "Current block configuration:\n```r\n", args_text, "\n```\n",
          "Modify the configuration based on the user's request."
        )
      }

      # Get model at runtime
      current_model <- blockr.core::blockr_option("ai_model", "gpt-4o-mini")

      # Run discovery
      result <- tryCatch(
        {
          discover_block_args(
            prompt = context_prompt,
            data = current_data,
            block_ctor = block_ctor,
            block_name = block_name,
            max_iterations = max_iterations,
            model = current_model,
            verbose = FALSE
          )
        },
        error = function(e) {
          list(success = FALSE, error = conditionMessage(e))
        }
      )

      # Handle result
      if (isTRUE(result$success) && !is.null(result$args)) {
        tryCatch(
          {
            for (name in names(result$args)) {
              if (name %in% names(args)) {
                args[[name]](result$args[[name]])
              }
            }
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
        error_msg <- result$error %||% "I couldn't figure out the right configuration. Could you try rephrasing?"
        shinychat::chat_append(
          "chat",
          error_msg,
          session = session
        )
      }
    })

    invisible(NULL)
  })
}


#' CSS for AI Assist collapsible section
#' @noRd
css_ai_assist <- function() {
  tags$style(HTML("
    .ai-assist-section {
      margin-top: -4px;
      margin-bottom: 15px;
      margin-left: -16px;
      margin-right: -16px;
      padding-top: 0;
      padding-left: 16px;
      padding-right: 16px;
      border-bottom: 1px solid #dee2e6;
      padding-bottom: 12px;
    }

    .ai-assist-toggle {
      cursor: pointer;
      user-select: none;
      padding: 0;
      display: flex;
      align-items: center;
      gap: 6px;
      font-size: 0.8rem;
      color: #6c757d;
      width: 100%;
    }

    .ai-assist-toggle:hover {
      color: #495057;
    }

    .ai-icon {
      font-size: 0.85rem;
      transition: color 0.3s, transform 0.3s;
    }

    .ai-icon.ai-active {
      color: #7c3aed;
      animation: sparkle 0.5s ease-out forwards;
    }

    .ai-chevron {
      margin-left: auto;
      transition: transform 0.2s;
      font-size: 14px;
      font-weight: bold;
      color: #6c757d;
    }

    .ai-chevron.rotated {
      transform: rotate(90deg);
    }

    @keyframes sparkle {
      0% { transform: scale(1) rotate(0deg); filter: brightness(1); }
      50% { transform: scale(1.3) rotate(-8deg); filter: brightness(1.5); }
      100% { transform: scale(1) rotate(0deg); filter: brightness(1); }
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

    .chat-ai-icon {
      color: #6c757d;
      font-size: 0.9rem;
    }

    .ai-assist-content shiny-chat-container {
      --_chat-container-padding: 0;
    }

    .ai-assist-content shiny-chat-input textarea {
      --bs-border-radius: 6px !important;
      border-radius: 6px !important;
      min-height: 38px !important;
    }

    .ai-assist-content shiny-chat-input textarea:focus {
      border-color: #7c3aed !important;
      box-shadow: none !important;
      outline: none !important;
    }

    .ai-assist-content shiny-chat-input .shiny-chat-btn-send {
      bottom: 7px !important;
    }

    .ai-assist-content shiny-chat-message[data-role=user] {
      border-radius: 6px !important;
      background-color: rgba(124, 58, 237, 0.1) !important;
    }

    .ai-assist-content shiny-chat-message[data-role=assistant] {
      border-radius: 6px !important;
    }
  "))
}
