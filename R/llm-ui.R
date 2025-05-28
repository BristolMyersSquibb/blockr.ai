#' @rdname new_llm_block
#' @export
llm_block_ui <- function(x) {
	UseMethod("llm_block_ui", x)
}

#' @rdname new_llm_block
#' @export
llm_block_ui.llm_block_proxy <- function(x) {
	function(id) {
	  tagList(
	    shinyjs::useShinyjs(),
	    # Styling
	    tags$style(HTML(llm_block_css(x))),
	    div(
	      class = "llm-block",
	      # Question input section
	      textAreaInput(
	        NS(id, "question"),
	        "Question",
	        value = x[["question"]],
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
	        condition = sprintf(
	        	"output['%s'] == true",
	        	NS(id, "result_is_available")
	        ),
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
	            shinyAce::aceEditor(
						    NS(id, "code_editor"),
						    mode = "r",
						    value = style_code(x[["code"]]),
						    showPrintMargin = FALSE,
						    height = "200px"
						  ),
	            uiOutput(NS(id, "code_display"))
	          )
	        )
	      )
	    )
	  )
	}
}
