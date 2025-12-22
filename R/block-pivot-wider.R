#' Pivot Wider block constructor with AI assistance
#'
#' This block reshapes data from long to wide format by pivoting column values
#' into new columns (see [tidyr::pivot_wider()]).
#'
#' This version includes an integrated AI assistant that can configure the
#' pivoting based on natural language descriptions.
#'
#' @param names_from Character vector specifying which column(s) to use for new
#'   column names.
#' @param values_from Character vector specifying which column(s) to use for cell
#'   values.
#' @param id_cols Character vector of columns that uniquely identify each row.
#' @param values_fill Optional value to use for missing combinations.
#' @param names_sep Separator to use when names_from specifies multiple columns.
#' @param names_prefix Optional prefix to add to all new column names.
#' @param ... Additional arguments forwarded to [new_transform_block()]
#'
#' @return A block object for pivot_wider operations with AI assistance
#' @importFrom shiny req showNotification NS moduleServer reactive observeEvent textInput selectInput tagList tags HTML div
#' @importFrom glue glue
#' @seealso [blockr.core::new_transform_block()], [tidyr::pivot_wider()]
#' @examples
#' # Create a pivot wider block
#' new_pivot_wider_block()
#'
#' if (interactive()) {
#'   library(blockr.core)
#'   long_data <- data.frame(
#'     id = rep(1:3, each = 3),
#'     measurement_type = rep(c("a", "b", "c"), 3),
#'     value = c(10, 15, 12, 20, 25, 22, 30, 35, 32)
#'   )
#'   serve(
#'     new_pivot_wider_block(
#'       names_from = "measurement_type",
#'       values_from = "value"
#'     ),
#'     data = list(data = long_data)
#'   )
#' }
#' @export
new_pivot_wider_block <- function(
    names_from = character(),
    values_from = character(),
    id_cols = character(),
    values_fill = "",
    names_sep = "_",
    names_prefix = "",
    ...
) {
  blockr.core::new_transform_block(
    server = function(id, data) {
      moduleServer(
        id,
        function(input, output, session) {
          # Column selectors
          r_names_from <- mod_column_selector_server(
            id = "names_from_selector",
            get_cols = \() colnames(data()),
            initial_value = names_from
          )

          r_values_from <- mod_column_selector_server(
            id = "values_from_selector",
            get_cols = \() colnames(data()),
            initial_value = values_from
          )

          r_id_cols <- mod_column_selector_server(
            id = "id_cols_selector",
            get_cols = \() colnames(data()),
            initial_value = id_cols
          )

          # Text inputs
          r_values_fill <- reactiveVal(values_fill)
          r_names_sep <- reactiveVal(names_sep)
          r_names_prefix <- reactiveVal(names_prefix)

          observeEvent(input$values_fill, {
            r_values_fill(input$values_fill)
          })

          observeEvent(input$names_sep, {
            r_names_sep(input$names_sep)
          })

          observeEvent(input$names_prefix, {
            r_names_prefix(input$names_prefix)
          })

          # AI Assist integration
          mod_ai_assist_server(
            "ai",
            get_data = data,
            block_ctor = new_pivot_wider_block,
            block_name = "new_pivot_wider_block",
            on_apply = function(args) {
              # Update column selectors
              if (!is.null(args$names_from)) {
                updateSelectInput(
                  session,
                  inputId = "names_from_selector-columns",
                  selected = args$names_from
                )
              }
              if (!is.null(args$values_from)) {
                updateSelectInput(
                  session,
                  inputId = "values_from_selector-columns",
                  selected = args$values_from
                )
              }
              if (!is.null(args$id_cols)) {
                updateSelectInput(
                  session,
                  inputId = "id_cols_selector-columns",
                  selected = args$id_cols
                )
              }
              # Update text inputs
              if (!is.null(args$values_fill)) {
                r_values_fill(args$values_fill)
                shiny::updateTextInput(session, "values_fill", value = args$values_fill)
              }
              if (!is.null(args$names_sep)) {
                r_names_sep(args$names_sep)
                shiny::updateTextInput(session, "names_sep", value = args$names_sep)
              }
              if (!is.null(args$names_prefix)) {
                r_names_prefix(args$names_prefix)
                shiny::updateTextInput(session, "names_prefix", value = args$names_prefix)
              }
            },
            get_current_args = function() {
              list(
                names_from = r_names_from(),
                values_from = r_values_from(),
                id_cols = r_id_cols(),
                values_fill = r_values_fill(),
                names_sep = r_names_sep(),
                names_prefix = r_names_prefix()
              )
            }
          )

          list(
            expr = reactive({
              names_from_cols <- r_names_from()
              values_from_cols <- r_values_from()

              if (length(names_from_cols) == 0 || length(values_from_cols) == 0) {
                return(parse(text = "identity(data)")[[1]])
              }

              # Build column selection with backticks if needed
              names_from_str <- if (length(names_from_cols) == 1) {
                backtick_if_needed(names_from_cols)
              } else {
                paste0("c(", paste(backtick_if_needed(names_from_cols), collapse = ", "), ")")
              }

              values_from_str <- if (length(values_from_cols) == 1) {
                backtick_if_needed(values_from_cols)
              } else {
                paste0("c(", paste(backtick_if_needed(values_from_cols), collapse = ", "), ")")
              }

              args <- list()
              args$names_from <- names_from_str
              args$values_from <- values_from_str

              id_cols_selected <- r_id_cols()
              if (length(id_cols_selected) > 0) {
                id_cols_str <- paste0("c(", paste(backtick_if_needed(id_cols_selected), collapse = ", "), ")")
                args$id_cols <- id_cols_str
              }

              if (nzchar(r_values_fill())) {
                fill_val <- r_values_fill()
                if (fill_val == "NA") {
                  args$values_fill <- "NA"
                } else if (fill_val == "NULL") {
                  args$values_fill <- "NULL"
                } else if (!is.na(suppressWarnings(as.numeric(fill_val)))) {
                  args$values_fill <- fill_val
                } else {
                  args$values_fill <- glue('"{fill_val}"')
                }
              }

              if (nzchar(r_names_sep()) && r_names_sep() != "_") {
                args$names_sep <- glue('"{r_names_sep()}"')
              }

              if (nzchar(r_names_prefix())) {
                args$names_prefix <- glue('"{r_names_prefix()}"')
              }

              args_str <- paste(names(args), "=", unlist(args), collapse = ", ")
              text <- glue("tidyr::pivot_wider(data, {args_str})")
              parse(text = as.character(text))[[1]]
            }),
            state = list(
              names_from = r_names_from,
              values_from = r_values_from,
              id_cols = r_id_cols,
              values_fill = r_values_fill,
              names_sep = r_names_sep,
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
          .pivot_wider-block-container .block-advanced-toggle {
            grid-column: 1 / -1;
          }
        ")),

        div(
          class = "block-container pivot_wider-block-container",

          # AI Assist Section
          mod_ai_assist_ui(
            NS(id, "ai"),
            placeholder = "e.g., spread measurement_type values into columns"
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
                    NS(id, "names_from_selector"),
                    label = "Get new column names from",
                    initial_choices = names_from,
                    initial_selected = names_from,
                    width = "100%"
                  )
                ),

                div(
                  class = "block-input-wrapper",
                  mod_column_selector_ui(
                    NS(id, "values_from_selector"),
                    label = "Get values from",
                    initial_choices = values_from,
                    initial_selected = values_from,
                    width = "100%"
                  )
                ),

                div(
                  class = "block-input-wrapper",
                  mod_column_selector_ui(
                    NS(id, "id_cols_selector"),
                    label = "ID columns (optional)",
                    initial_choices = id_cols,
                    initial_selected = id_cols,
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
                      NS(id, "values_fill"),
                      label = "Fill missing values with",
                      value = values_fill,
                      placeholder = "e.g., 0 or NA",
                      width = "100%"
                    )
                  ),

                  div(
                    class = "block-input-wrapper",
                    textInput(
                      NS(id, "names_prefix"),
                      label = "Add prefix to column names",
                      value = names_prefix,
                      placeholder = "e.g., 'col_'",
                      width = "100%"
                    )
                  ),

                  div(
                    class = "block-input-wrapper",
                    textInput(
                      NS(id, "names_sep"),
                      label = "Separator for multiple names",
                      value = names_sep,
                      placeholder = "_",
                      width = "100%"
                    )
                  )
                )
              )
            )
          )
        )
      )
    },
    class = "pivot_wider_block",
    allow_empty_state = c("names_from", "values_from", "id_cols", "values_fill", "names_prefix"),
    ...
  )
}
