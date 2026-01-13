# AI Control Block Plugin
#
# Provides AI-powered control for blocks with external_ctrl enabled.

#' AI-powered control block plugin
#'
#' Replaces the default ctrl_block with an AI chat interface. Users can
#' describe what they want in natural language and the LLM will configure
#' the block parameters.
#'
#' @return A ctrl_block plugin object
#'
#' @examples
#' \dontrun{
#' serve(
#'   new_board(new_dataset_block("iris")),
#'   plugins = custom_plugins(ai_ctrl_block())
#' )
#' }
#'
#' @export
ai_ctrl_block <- function() {
  blockr.core::ctrl_block(
    server = ai_ctrl_server,
    ui = ai_ctrl_ui
  )
}


#' @param id Namespace ID
#' @param x Block object
#' @rdname ai_ctrl_block
#' @export
ai_ctrl_ui <- function(id, x) {
  ns <- NS(id)

  tagList(
    tags$style(HTML("
      .ai-ctrl-section { margin-bottom: 12px; }
      .ai-ctrl-toggle {
        cursor: pointer; user-select: none; display: flex;
        align-items: center; gap: 6px; font-size: 0.8rem; color: #6c757d;
      }
      .ai-ctrl-toggle:hover { color: #495057; }
      .ai-ctrl-content { display: none; padding-top: 8px; }
      .ai-ctrl-content.expanded { display: block; }

      /* Squared chat input */
      .ai-ctrl-content shiny-chat-input textarea {
        border-radius: 6px !important;
      }
      .ai-ctrl-content shiny-chat-input textarea:focus {
        border-color: #7c3aed !important;
        box-shadow: none !important;
      }
      .ai-ctrl-content shiny-chat-input .shiny-chat-btn-send {
        bottom: 7px !important;
      }

      /* Squared message bubbles */
      .ai-ctrl-content shiny-chat-message {
        border-radius: 6px !important;
      }
      .ai-ctrl-content shiny-chat-message[data-role=user] {
        background-color: rgba(124, 58, 237, 0.1) !important;
      }

      /* Remove container padding */
      .ai-ctrl-content shiny-chat-container {
        --_chat-container-padding: 0;
      }
    ")),

    div(
      class = "ai-ctrl-section",
      div(
        class = "ai-ctrl-toggle",
        id = ns("toggle"),
        onclick = sprintf(
          "var c = document.getElementById('%s');
           c.classList.toggle('expanded');
           this.querySelector('.chevron').textContent =
             c.classList.contains('expanded') ? '\\u25BC' : '\\u25B6';",
          ns("content")
        ),
        tags$span(class = "chevron", "\u25B6"),
        "AI Assist"
      ),
      div(
        id = ns("content"),
        class = "ai-ctrl-content",
        shinychat::chat_ui(ns("chat"), height = "auto", width = "100%")
      )
    )
  )
}


#' @param vars Reactive state values
#' @param dat Reactive input data
#' @param expr Reactive block expression
#' @rdname ai_ctrl_block
#' @export
ai_ctrl_server <- function(id, x, vars, dat, expr) {
  moduleServer(id, function(input, output, session) {

    # Gate controls downstream evaluation
    gate <- reactiveVal(TRUE)

    observeEvent(input$chat_user_input, {
      prompt <- input$chat_user_input
      if (is.null(prompt) || nchar(trimws(prompt)) == 0) return()

      # Block downstream eval while working
      gate(FALSE)

      # Shiny validator: updates vars, then validates
      shiny_validator <- function(args) {
        for (nm in names(args)) {
          if (nm %in% names(vars) && inherits(vars[[nm]], "reactiveVal")) {
            vars[[nm]](args[[nm]])
          }
        }
        shiny::isolate(blockr.core:::eval_impl(x, expr(), dat()))
      }

      # Run LLM discovery loop
      result <- discover_block_args(
        prompt = prompt,
        block = x,
        data = shiny::isolate(dat()),
        validate = shiny_validator
      )

      # Update gate and notify user
      gate(result$success)
      shinychat::chat_append(
        "chat",
        if (result$success) "Done!" else paste("Failed:", result$error),
        session = session
      )
    })

    reactive(gate())
  })
}
