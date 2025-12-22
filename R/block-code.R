#' Code block constructor with AI assistance
#'
#' A simple block that executes arbitrary R code. The code can be written
#' manually in the editor or generated using the AI assistant.
#'
#' This block provides a flexible way to transform data using any R code.
#' The AI assistant can help write the code based on natural language
#' descriptions.
#'
#' @param code R code as a string. The code should transform `data` and
#'   return a data.frame or tibble.
#' @param ... Additional arguments forwarded to [new_transform_block()]
#'
#' @return A block object for code transformation with AI assistance
#' @importFrom shiny moduleServer reactiveVal observeEvent reactive NS tagList div
#' @seealso [blockr.core::new_transform_block()]
#' @examples
#' # Create a code block
#' new_code_block()
#'
#' if (interactive()) {
#'   library(blockr.core)
#'
#'   # Basic usage - just passes data through
#'   serve(new_code_block(), data = list(data = mtcars))
#'
#'   # With predefined code
#'   serve(
#'     new_code_block(
#'       code = "data |> dplyr::filter(cyl == 6) |> dplyr::select(mpg, hp)"
#'     ),
#'     data = list(data = mtcars)
#'   )
#' }
#' @export
new_code_block <- function(code = "data", ...) {
  blockr.core::new_transform_block(
    server = function(id, data) {
      moduleServer(id, function(input, output, session) {

        # Reactive for code
        r_code <- reactiveVal(code)

        # Update from editor changes
        observeEvent(input$code_editor, {
          r_code(input$code_editor)
        })

        # AI Assist - uses existing module
        mod_ai_assist_server(
          "ai",
          get_data = data,
          block_ctor = new_code_block,
          block_name = "new_code_block",
          on_apply = function(args) {
            if (!is.null(args$code)) {
              r_code(args$code)
              # Update the shinyAce editor
              shinyAce::updateAceEditor(session, "code_editor", value = args$code)
            }
          },
          get_current_args = function() {
            list(code = r_code())
          }
        )

        # Return expression
        list(
          expr = reactive({
            parse(text = r_code())[[1]]
          }),
          state = list(code = r_code)
        )
      })
    },
    ui = function(id) {
      tagList(
        shinyjs::useShinyjs(),

        css_code_block(),

        div(
          class = "block-container code-block-container",

          # AI Assist at top (existing module)
          mod_ai_assist_ui(
            NS(id, "ai"),
            placeholder = "e.g., filter for cars with 6 cylinders and calculate mean mpg"
          ),

          # Code editor
          div(
            class = "code-block-editor",
            shinyAce::aceEditor(
              NS(id, "code_editor"),
              value = code,
              mode = "r",
              theme = "tomorrow",
              height = "120px",
              fontSize = 13,
              showLineNumbers = TRUE,
              highlightActiveLine = TRUE
            )
          )
        )
      )
    },
    class = "code_block",
    ...
  )
}


#' CSS for code block
#' @noRd
css_code_block <- function() {
  tags$style(HTML(
    "
    .code-block-container {
      padding: 0;
    }

    .code-block-editor {
      margin-top: 10px;
    }

    .code-block-editor .shiny-ace {
      border: 1px solid #dee2e6;
      border-radius: 4px;
    }
    "
  ))
}
