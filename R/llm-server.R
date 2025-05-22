#' @param x Proxy LLM block object
#' @rdname new_llm_block
#' @export
llm_block_server <- function(x) {
	UseMethod("llm_block_server", x)
}

#' @rdname new_llm_block
#' @export
llm_block_server.llm_block_proxy <- function(x) {

	function(id, ...args) {
	  moduleServer(
	    id,
	    function(input, output, session) {

	      r_datasets <- reactive(reactiveValuesToList(...args))
	      r_datasets_renamed <- reactive(rename_datasets(r_datasets()))
	      # the dataset_1 <- `1` part
	      r_code_prefix <- reactive(build_code_prefix(r_datasets()))
	      r_system_prompt <- reactive({
	        req(length(r_datasets_renamed()) > 0)
	        system_prompt(x, r_datasets_renamed())
	      })

	      rv_code <- reactiveVal()
	      rv_expl <- reactiveVal(x[["explanation"]])

	      observeEvent(
	      	input$ask,
	      	{
		        req(input$question)

		        # Show progress
		        shinyjs::show(id = "progress_container", anim = TRUE)

		        # Execute code with retry logic and store result
		        result <- query_llm_and_run_with_retries(
		          datasets = r_datasets_renamed(),
		          user_prompt = input$question,
		          system_prompt = r_system_prompt(),
		          max_retries = x[["max_retries"]]
		        )

		        # Hide progress
		        shinyjs::hide(id = "progress_container", anim = TRUE)

		        if (!is.null(result$error)) {
		          showNotification(result$error, type = "error")
		        }

		        rv_code(paste(result$code, collapse = "\n"))
		        rv_expl(result$explanation)
		      }
		    )

	      observeEvent(
	      	rv_code(),
      		shinyAce::updateAceEditor(
	      		session,
	      		"code_editor",
	      		value = style_code(rv_code())
	      	)
	      )

	      observeEvent(
	      	input$code_editor,
	      	{
	      		res <- try_eval_code(input$code_editor, r_datasets_renamed())
	      		if (inherits(res, "try-error")) {
	      			warning("Encountered an error evaluating code: ", res)
	      		} else {
	      			rv_code(input$code_editor)
	      		}
	      	}
	      )

	      output$explanation <- renderUI(markdown(rv_expl()))

	      output$result_is_available <- reactive(
	        length(rv_code()) > 0 && any(nzchar(rv_code()))
	      )

	      outputOptions(
	      	output,
	      	"result_is_available",
	      	suspendWhenHidden = FALSE
	      )

	      list(
	        expr = reactive(
	          str2lang(sprintf("{%s\n%s}", r_code_prefix(), rv_code()))
	        ),
	        state = list(
	          question = reactive(input$question),
	          code = rv_code,
	          explanation = rv_expl,
	          max_retries = x[["max_retries"]]
	        )
	      )
	    }
	  )
	}
}

