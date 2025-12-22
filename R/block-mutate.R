#' Mutate block constructor with AI assistance
#'
#' This block allows creating or modifying columns using R expressions
#' (see [dplyr::mutate()]).
#'
#' This version includes an integrated AI assistant that can configure the
#' mutations based on natural language descriptions.
#'
#' @param exprs Named list of expressions. Names are column names, values are
#'   R expression strings.
#' @param ... Additional arguments forwarded to [new_block()]
#'
#' @return A block object for mutate operations with AI assistance
#' @importFrom shiny req showNotification NS moduleServer reactive actionButton observeEvent icon tagList tags HTML div textInput
#' @importFrom glue glue
#' @seealso [blockr.core::new_transform_block()]
#' @examples
#' # Create a mutate block
#' new_mutate_block()
#'
#' if (interactive()) {
#'   library(blockr.core)
#'   serve(new_mutate_block(), data = list(data = mtcars))
#'
#'   # With predefined expression
#'   serve(
#'     new_mutate_block(exprs = list(mpg_squared = "mpg^2")),
#'     data = list(data = mtcars)
#'   )
#' }
#' @export
new_mutate_block <- function(
    exprs = list(new_col = "1"),
    ...
) {
  blockr.core::new_transform_block(
    function(id, data) {
      moduleServer(
        id,
        function(input, output, session) {
          ns <- session$ns

          # Expressions reactive value
          r_exprs <- reactiveVal(exprs)

          # Track expression indices
          r_expr_indices <- reactiveVal(seq_along(exprs))
          r_next_index <- reactiveVal(length(exprs) + 1)

          # Get current expressions from inputs
          get_current_exprs <- function() {
            indices <- r_expr_indices()
            if (length(indices) == 0) return(list())

            result <- list()
            for (i in indices) {
              name <- input[[paste0("expr_", i, "_name")]]
              val <- input[[paste0("expr_", i, "_val")]]

              if (!is.null(name) && !is.null(val) && name != "" && val != "") {
                result[[name]] <- val
              }
            }

            if (length(result) == 0) {
              result <- list(new_col = "1")
            }
            result
          }

          # Add expression
          observeEvent(input$add_expr, {
            current_indices <- r_expr_indices()
            new_index <- r_next_index()
            r_expr_indices(c(current_indices, new_index))
            r_next_index(new_index + 1)

            current <- get_current_exprs()
            new_name <- "new_col"
            i <- 1
            while (new_name %in% names(current)) {
              new_name <- paste0("new_col_", i)
              i <- i + 1
            }
            current[[new_name]] <- "1"
            r_exprs(current)
          })

          # Remove expression handlers
          observe({
            indices <- r_expr_indices()
            lapply(indices, function(i) {
              observeEvent(input[[paste0("expr_", i, "_remove")]], {
                current_indices <- r_expr_indices()
                if (length(current_indices) > 1) {
                  r_expr_indices(setdiff(current_indices, i))
                  r_exprs(get_current_exprs())
                }
              }, ignoreInit = TRUE)
            })
          })

          # Render expressions UI
          output$exprs_ui <- renderUI({
            indices <- r_expr_indices()
            expr_list <- r_exprs()

            expr_names <- names(expr_list)
            expr_values <- unname(expr_list)

            tagList(
              lapply(seq_along(indices), function(j) {
                i <- indices[j]
                nm <- if (j <= length(expr_names)) expr_names[j] else "new_col"
                val <- if (j <= length(expr_values)) expr_values[[j]] else "1"

                div(
                  class = "mutate-expr-pair",
                  div(
                    class = "mutate-name",
                    textInput(ns(paste0("expr_", i, "_name")), NULL, value = nm,
                              placeholder = "column name")
                  ),
                  div(class = "mutate-equals", "="),
                  div(
                    class = "mutate-value",
                    textInput(ns(paste0("expr_", i, "_val")), NULL, value = val,
                              placeholder = "e.g., col1 * 2")
                  ),
                  if (length(indices) > 1) {
                    actionButton(ns(paste0("expr_", i, "_remove")), NULL,
                                 icon = icon("xmark"), class = "btn btn-sm mutate-delete")
                  }
                )
              })
            )
          })

          # Store validated expression
          r_expr_validated <- reactiveVal(parse_mutate(exprs))

          # Watch for submit
          observeEvent(input$submit, {
            current <- get_current_exprs()
            r_exprs(current)
            tryCatch({
              expr <- parse_mutate(current)
              eval(expr, envir = list(data = data()))
              r_expr_validated(expr)
            }, error = function(e) {
              showNotification(conditionMessage(e), type = "error", duration = 5)
            })
          })

          # AI Assist integration
          mod_ai_assist_server(
            "ai",
            get_data = data,
            block_ctor = new_mutate_block,
            block_name = "new_mutate_block",
            on_apply = function(args) {
              if (!is.null(args$exprs)) {
                r_exprs(args$exprs)
                # Use NEW indices to force UI re-render with fresh inputs
                current_next <- r_next_index()
                new_indices <- seq(current_next, length.out = length(args$exprs))
                r_expr_indices(new_indices)
                r_next_index(current_next + length(args$exprs))
                tryCatch({
                  expr <- parse_mutate(args$exprs)
                  r_expr_validated(expr)
                }, error = function(e) NULL)
              }
            },
            get_current_args = function() {
              list(exprs = r_exprs())
            }
          )

          list(
            expr = r_expr_validated,
            state = list(
              exprs = reactive(as.list(r_exprs()))
            )
          )
        }
      )
    },
    function(id) {
      tagList(
        shinyjs::useShinyjs(),

        css_responsive_grid(),
        css_single_column("mutate"),
        css_mutate_grid(),

        div(
          class = "block-container mutate-block-container",

          # AI Assist Section
          mod_ai_assist_ui(
            NS(id, "ai"),
            placeholder = "e.g., create a new column that's Sepal.Length times 2"
          ),

          div(
            class = "block-form-grid",

            # Expressions Section
            div(
              class = "block-section",
              div(
                class = "block-section-grid",
                div(
                  class = "mutate-container",
                  uiOutput(NS(id, "exprs_ui")),
                  div(
                    class = "mutate-actions",
                    actionButton(
                      NS(id, "add_expr"),
                      "Add Expression",
                      icon = icon("plus"),
                      class = "btn btn-outline-secondary btn-sm"
                    ),
                    actionButton(
                      NS(id, "submit"),
                      "Submit",
                      class = "btn btn-primary btn-sm"
                    )
                  )
                )
              )
            )
          )
        )
      )
    },
    class = "mutate_block",
    ...
  )
}


#' Parse mutate expressions into dplyr expression
#' @noRd
parse_mutate <- function(exprs = list()) {
  if (length(exprs) == 0 || all(unname(unlist(exprs)) == "")) {
    return(parse(text = "dplyr::mutate(data)")[[1]])
  }

  # Convert list to character vector if needed
  if (is.list(exprs)) {
    exprs <- unlist(exprs)
  }

  new_names <- backtick_if_needed(names(exprs))
  mutate_string <- glue::glue("{new_names} = {unname(exprs)}")
  mutate_string <- glue::glue_collapse(mutate_string, sep = ", ")

  text <- glue::glue("dplyr::mutate(data, {mutate_string})")
  parse(text = text)[[1]]
}


#' CSS for mutate block grid
#' @noRd
css_mutate_grid <- function() {
  tags$style(HTML(
    "
    .mutate-container {
      grid-column: 1 / -1;
    }

    .mutate-expr-pair {
      display: flex;
      width: 100%;
      align-items: center;
      gap: 10px;
      margin-bottom: 8px;
    }

    .mutate-expr-pair .mutate-name {
      flex: 0 0 150px;
    }

    .mutate-expr-pair .mutate-equals {
      flex: 0 0 auto;
      color: var(--bs-gray-400);
      font-size: 0.9em;
    }

    .mutate-expr-pair .mutate-value {
      flex: 1 1 0;
      min-width: 0;
    }

    .mutate-expr-pair .mutate-delete {
      flex: 0 0 auto;
      height: 38px;
      width: 24px;
      display: flex;
      align-items: center;
      justify-content: center;
      color: #6c757d;
      border: none;
      background: transparent;
      padding: 0;
    }

    .mutate-expr-pair .mutate-delete:hover {
      color: #dc3545;
      background: rgba(220, 53, 69, 0.1);
    }

    .mutate-expr-pair .shiny-input-container {
      margin-bottom: 0 !important;
    }

    .mutate-expr-pair .form-control {
      height: 38px !important;
    }

    .mutate-actions {
      display: flex;
      justify-content: space-between;
      align-items: center;
      margin-top: 0.5rem;
      margin-bottom: 0.25rem;
    }

    .mutate-actions .btn-outline-secondary {
      border-color: #dee2e6;
      color: #6c757d;
    }

    .mutate-actions .btn-outline-secondary:hover {
      border-color: #adb5bd;
      background-color: #f8f9fa;
      color: #495057;
    }
    "
  ))
}
