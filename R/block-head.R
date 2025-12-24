#' @section Head block:
#' Row-subsetting the first or last `n` rows of a `data.frame` (as provided by
#' [utils::head()] and [utils::tail()]) is implemented as `head_block`. This is
#' an example of a block that takes a single `data.frame` as input and produces
#' a single `data.frame` as output.
#'
#' @param n Number of rows
#' @param direction Either "head" or "tail"
#'
#' @rdname new_transform_block
#' @export
new_head_block <- function(n = 6L, direction = c("head", "tail"), ...) {

  direction <- match.arg(direction)

  new_transform_block(
    function(id, data) {
      moduleServer(
        id,
        function(input, output, session) {

          nrw <- reactiveVal(n)
          dir <- reactiveVal(direction)

          observeEvent(input$n, nrw(input$n))
          observeEvent(input$tail, dir(if (isTRUE(input$tail)) "tail" else "head"))

          # Update UI when AI changes values
          observeEvent(nrw(), updateNumericInput(inputId = "n", value = nrw()))
          observeEvent(dir(), bslib::update_switch(id = "tail", value = dir() == "tail"))

          observeEvent(nrow(data()), {
            updateNumericInput(inputId = "n", min = 1L, max = nrow(data()))
          })

          mod_ai_assist_server(
            "ai",
            data = data,
            args = list(n = nrw, direction = dir),
            block_ctor = new_head_block,
            block_name = "new_head_block"
          )

          list(
            expr = reactive(
              if (dir() == "tail") {
                bbquote(utils::tail(.(data), n = .(n)), list(n = nrw()))
              } else {
                bbquote(utils::head(.(data), n = .(n)), list(n = nrw()))
              }
            ),
            state = list(
              n = nrw,
              direction = dir
            )
          )
        }
      )
    },
    function(id) {
      tagList(
        mod_ai_assist_ui(NS(id, "ai"), placeholder = "e.g., show the last 10 rows"),
        numericInput(
          inputId = NS(id, "n"),
          label = "Number of rows",
          value = n,
          min = 1L
        ),
        bslib::input_switch(
          id = NS(id, "tail"),
          label = "Tail",
          value = isTRUE(direction == "tail")
        )
      )
    },
    dat_val = function(data) {
      stopifnot(is.data.frame(data))
    },
    expr_type = "bquoted",
    class = "head_block",
    ...
  )
}
