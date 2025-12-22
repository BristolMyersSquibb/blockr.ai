#' Pivot Longer block constructor with AI assistance
#'
#' This block reshapes data from wide to long format by pivoting multiple columns
#' into two columns: one containing the original column names and another containing
#' the values (see [tidyr::pivot_longer()]).
#'
#' This version includes an integrated AI assistant that can configure the
#' pivoting based on natural language descriptions.
#'
#' @param cols Character vector of column names to pivot into longer format.
#' @param names_to Name of the new column to create from the column names.
#' @param values_to Name of the new column to create from the values.
#' @param values_drop_na If TRUE, rows with NA values will be dropped.
#' @param names_prefix Optional prefix to remove from column names.
#' @param ... Additional arguments forwarded to [new_transform_block()]
#'
#' @return A block object for pivot_longer operations with AI assistance
#' @importFrom shiny req showNotification NS moduleServer reactive observeEvent textInput checkboxInput tagList tags HTML div
#' @importFrom glue glue
#' @seealso [blockr.core::new_transform_block()], [tidyr::pivot_longer()]
#' @examples
#' # Create a pivot longer block
#' new_pivot_longer_block()
#'
#' if (interactive()) {
#'   library(blockr.core)
#'   wide_data <- data.frame(
#'     id = 1:3,
#'     measurement_a = c(10, 20, 30),
#'     measurement_b = c(15, 25, 35),
#'     measurement_c = c(12, 22, 32)
#'   )
#'   serve(
#'     new_pivot_longer_block(
#'       cols = c("measurement_a", "measurement_b", "measurement_c"),
#'       names_to = "measurement_type",
#'       values_to = "value"
#'     ),
#'     data = list(data = wide_data)
#'   )
#' }
#' @export
new_pivot_longer_block <- function(
    cols = character(),
    names_to = "name",
    values_to = "value",
    values_drop_na = FALSE,
    names_prefix = "",
    ...
) {
  blockr.core::new_transform_block(
    server = function(id, data) {
      moduleServer(
        id,
        function(input, output, session) {
          # Column selector
          r_cols_selection <- mod_column_selector_server(
            id = "cols_selector",
            get_cols = \() colnames(data()),
            initial_value = cols
          )

          # Text inputs
          r_names_to <- reactiveVal(names_to)
          r_values_to <- reactiveVal(values_to)
          r_values_drop_na <- reactiveVal(values_drop_na)
          r_names_prefix <- reactiveVal(names_prefix)

          observeEvent(input$names_to, {
            r_names_to(input$names_to)
          })

          observeEvent(input$values_to, {
            r_values_to(input$values_to)
          })

          observeEvent(input$values_drop_na, {
            r_values_drop_na(input$values_drop_na)
          })

          observeEvent(input$names_prefix, {
            r_names_prefix(input$names_prefix)
          })

          # AI Assist integration
          mod_ai_assist_server(
            "ai",
            get_data = data,
            block_ctor = new_pivot_longer_block,
            block_name = "new_pivot_longer_block",
            on_apply = function(args) {
              # Update column selector
              if (!is.null(args$cols)) {
                updateSelectInput(
                  session,
                  inputId = "cols_selector-columns",
                  selected = args$cols
                )
              }
              # Update text inputs
              if (!is.null(args$names_to)) {
                r_names_to(args$names_to)
                shiny::updateTextInput(session, "names_to", value = args$names_to)
              }
              if (!is.null(args$values_to)) {
                r_values_to(args$values_to)
                shiny::updateTextInput(session, "values_to", value = args$values_to)
              }
              if (!is.null(args$values_drop_na)) {
                r_values_drop_na(args$values_drop_na)
                shiny::updateCheckboxInput(session, "values_drop_na", value = args$values_drop_na)
              }
              if (!is.null(args$names_prefix)) {
                r_names_prefix(args$names_prefix)
                shiny::updateTextInput(session, "names_prefix", value = args$names_prefix)
              }
            },
            get_current_args = function() {
              list(
                cols = r_cols_selection(),
                names_to = r_names_to(),
                values_to = r_values_to(),
                values_drop_na = r_values_drop_na(),
                names_prefix = r_names_prefix()
              )
            }
          )

          list(
            expr = reactive({
              selected_cols <- r_cols_selection()

              if (length(selected_cols) == 0) {
                return(parse(text = "identity(data)")[[1]])
              }

              cols_str <- paste(backtick_if_needed(selected_cols), collapse = ", ")

              args <- list()
              args$cols <- glue("c({cols_str})")
              args$names_to <- glue('"{r_names_to()}"')
              args$values_to <- glue('"{r_values_to()}"')

              if (isTRUE(r_values_drop_na())) {
                args$values_drop_na <- "TRUE"
              }

              if (nzchar(r_names_prefix())) {
                args$names_prefix <- glue('"{r_names_prefix()}"')
              }

              args_str <- paste(names(args), "=", unlist(args), collapse = ", ")
              text <- glue("tidyr::pivot_longer(data, {args_str})")
              parse(text = as.character(text))[[1]]
            }),
            state = list(
              cols = r_cols_selection,
              names_to = r_names_to,
              values_to = r_values_to,
              values_drop_na = r_values_drop_na,
              names_prefix = r_names_prefix
            )
          )
        }
      )
    },
    ui = function(id) {
      tagList(
        shinyjs::useShinyjs(),

        css_responsive_grid(),
        css_advanced_toggle(NS(id, "advanced-options"), use_subgrid = TRUE),

        tags$style(HTML("
          .pivot_longer-block-container .block-advanced-toggle {
            grid-column: 1 / -1;
          }
        ")),

        div(
          class = "block-container pivot_longer-block-container",

          # AI Assist Section
          mod_ai_assist_ui(
            NS(id, "ai"),
            placeholder = "e.g., gather measurement columns into name/value pairs"
          ),

          div(
            class = "block-form-grid",

            # Main Section
            div(
              class = "block-section",
              div(
                class = "block-section-grid",

                div(
                  class = "block-input-wrapper",
                  mod_column_selector_ui(
                    NS(id, "cols_selector"),
                    label = "Columns to pivot",
                    initial_choices = cols,
                    initial_selected = cols,
                    width = "100%"
                  )
                ),

                div(
                  class = "block-input-wrapper",
                  textInput(
                    NS(id, "names_to"),
                    label = "New column for names",
                    value = names_to,
                    placeholder = "name",
                    width = "100%"
                  )
                ),

                div(
                  class = "block-input-wrapper",
                  textInput(
                    NS(id, "values_to"),
                    label = "New column for values",
                    value = values_to,
                    placeholder = "value",
                    width = "100%"
                  )
                )
              )
            ),

            # Toggle button for advanced options
            div(
              class = "block-advanced-toggle text-muted",
              id = NS(id, "advanced-toggle"),
              onclick = sprintf(
                "
                const section = document.getElementById('%s');
                const chevron = document.querySelector('#%s .block-chevron');
                section.classList.toggle('expanded');
                chevron.classList.toggle('rotated');
                ",
                NS(id, "advanced-options"),
                NS(id, "advanced-toggle")
              ),
              tags$span(class = "block-chevron", "\u203A"),
              "Show advanced options"
            ),

            # Advanced options section
            div(
              id = NS(id, "advanced-options"),
              div(
                class = "block-section",
                div(
                  class = "block-section-grid",

                  div(
                    class = "block-input-wrapper",
                    textInput(
                      NS(id, "names_prefix"),
                      label = "Remove prefix from names",
                      value = names_prefix,
                      placeholder = "e.g., 'col_'",
                      width = "100%"
                    )
                  ),

                  div(
                    class = "block-input-wrapper",
                    checkboxInput(
                      NS(id, "values_drop_na"),
                      label = "Drop rows with NA values",
                      value = values_drop_na
                    )
                  )
                )
              )
            )
          )
        )
      )
    },
    class = "pivot_longer_block",
    allow_empty_state = c("cols", "names_prefix"),
    ...
  )
}
