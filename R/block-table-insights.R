#' @rdname new_llm_block
#' @export
new_llm_table_insights_block <- function(
  question = "Analyze key findings, treatment effects, and statistical significance.",
  ...
) {
  initial_question <- question
  
  ui <- function(id) {
    tagList(
      textInput(NS(id, "question"), "Question", value = initial_question),
      actionButton(NS(id, "ask"), "Ask"),
      htmlOutput(NS(id, "report"))
    )
  }

  server <- function(id, data = NULL) {
    moduleServer(id, function(input, output, session) {
      text_result <- reactiveVal("")
      
      observeEvent(input$ask, {
        dat <- list(data = if (is.reactive(data)) data() else data)
        req(dat$data, input$question)
        
        proxy <- structure(list(), class = "llm_table_insights_block_proxy")
        chat <- chat_dispatch(system_prompt(proxy, dat))
        result <- chat$chat(input$question)
        result_text <- if (is.character(result)) result else result$text
        text_result(result_text)
        
        output$report <- renderUI({
          HTML(markdown::markdownToHTML(
            text = result_text,
            fragment.only = TRUE
          ))
        })
      })

      list(expr = reactive(text_result()), state = list(question = reactive(input$question)))
    })
  }
  
  new_block(
    server = server,
    ui = ui, 
    class = "llm_table_insights_block",
    ctor = sys.parent(),
    ctor_pkg = "blockr.ai",
    ...
  )
}

#' @export
result_ptype.llm_table_insights_block <- function(x) {
  character()
}
