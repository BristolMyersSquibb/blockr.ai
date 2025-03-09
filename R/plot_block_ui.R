plot_block_ui <- function(id) {
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
            border: none;
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
          .llm-plot {
            border: 1px solid #e0e0e0;
            border-radius: 4px;
            margin-top: 10px;
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
        NS(id, "question"),
        "Question",
        value = question,
        rows = 3,
        width = "100%",
        resize = "vertical"
      ),

      # Controls section
      div(
        style = "display: flex; gap: 10px; align-items: center;",
        actionButton(
          NS(id, "ask"),
          "Ask",
          class = "btn-primary"
        )
      ),

      # Progress indicator
      div(
        class = "llm-progress",
        id = NS(id, "progress_container"),
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

      conditionalPanel(
        condition = sprintf("output['%s'] == true", NS(id, "result_is_available")),
        # Response section
        div(
          class = "llm-response",
          # Explanation details
          tags$details(
            class = "llm-details",
            tags$summary("Explanation"),
            div(
              style = "padding: 10px;",
              htmlOutput(NS(id, "explanation"))
            )
          ),

          # Code details
          tags$details(
            class = "llm-details",
            tags$summary("Generated Code"),
            uiOutput(NS(id, "code_display"))
          ),

          div(
            class = "llm-plot",
            plotOutput(NS(id, "plot"))
          )
        )
      )
    )
  )
}
