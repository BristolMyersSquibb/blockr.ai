#' Summarize block constructor with AI assistance
#'
#' This block provides a no-code interface for summarizing data (see [dplyr::summarize()]).
#' Users select summary functions from dropdowns (mean, median, sum, etc.),
#' choose columns to summarize, and specify new column names.
#'
#' This version includes an integrated AI assistant that can configure the
#' summarization based on natural language descriptions.
#'
#' @param summaries Named list where each element is a list with 'func' and 'col' elements.
#'   For example: list(avg_mpg = list(func = "mean", col = "mpg"))
#' @param by Columns to define grouping
#' @param ... Additional arguments forwarded to [new_block()]
#'
#' @return A block object for no-code summarize operations with AI assistance
#' @importFrom shiny req showNotification NS moduleServer reactive observeEvent selectInput textInput actionButton div tagList tags HTML icon updateSelectInput
#' @importFrom glue glue
#' @seealso [blockr.core::new_transform_block()]
#' @examples
#' # Create a summarize block
#' new_summarize_block()
#'
#' if (interactive()) {
#'   library(blockr.core)
#'
#'   # Basic usage
#'   serve(new_summarize_block(), data = list(data = mtcars))
#'
#'   # With predefined summaries
#'   serve(
#'     new_summarize_block(
#'       summaries = list(
#'         avg_mpg = list(func = "mean", col = "mpg"),
#'         max_hp = list(func = "max", col = "hp")
#'       )
#'     ),
#'     data = list(data = mtcars)
#'   )
#' }
#' @export
new_summarize_block <- function(
    summaries = list(count = list(func = "dplyr::n", col = "")),
    by = character(),
    ...
) {
  blockr.core::new_transform_block(
    function(id, data) {
      moduleServer(
        id,
        function(input, output, session) {
          ns <- session$ns

          # Group by selector
          r_by_selection <- mod_column_selector_server(
            id = "by_selector",
            get_cols = \() colnames(data()),
            initial_value = by
          )

          # Summaries reactive value
          r_summaries <- reactiveVal(summaries)

          # Track summary indices
          r_summary_indices <- reactiveVal(seq_along(summaries))
          r_next_index <- reactiveVal(length(summaries) + 1)

          # Get current summaries from inputs
          get_current_summaries <- function() {
            indices <- r_summary_indices()
            if (length(indices) == 0) return(list())

            result <- list()
            for (i in indices) {
              new_name <- input[[paste0("summary_", i, "_new")]]
              func <- input[[paste0("summary_", i, "_func")]]
              col <- input[[paste0("summary_", i, "_col")]]

              if (!is.null(new_name) && !is.null(func) &&
                  new_name != "" && func != "" &&
                  (col != "" || func == "dplyr::n")) {
                result[[new_name]] <- list(func = func, col = col)
              }
            }

            if (length(result) == 0) {
              result <- list(count = list(func = "dplyr::n", col = ""))
            }
            result
          }

          # Add summary
          observeEvent(input$add_summary, {
            current_indices <- r_summary_indices()
            new_index <- r_next_index()
            r_summary_indices(c(current_indices, new_index))
            r_next_index(new_index + 1)

            current <- get_current_summaries()
            new_name <- "summary_col"
            i <- 1
            while (new_name %in% names(current)) {
              new_name <- paste0("summary_col_", i)
              i <- i + 1
            }
            current[[new_name]] <- list(func = "mean", col = colnames(data())[1])
            r_summaries(current)
          })

          # Remove summary handlers
          observe({
            indices <- r_summary_indices()
            lapply(indices, function(i) {
              observeEvent(input[[paste0("summary_", i, "_remove")]], {
                current_indices <- r_summary_indices()
                if (length(current_indices) > 1) {
                  r_summary_indices(setdiff(current_indices, i))
                  r_summaries(get_current_summaries())
                }
              }, ignoreInit = TRUE)
            })
          })

          # Render summaries UI
          output$summaries_ui <- renderUI({
            indices <- r_summary_indices()
            summ <- r_summaries()
            cols <- colnames(data())
            funcs <- get_summary_functions()

            req(length(cols) > 0)

            summary_names <- names(summ)
            tagList(
              lapply(seq_along(indices), function(j) {
                i <- indices[j]
                nm <- if (j <= length(summary_names)) summary_names[j] else "summary_col"
                spec <- if (j <= length(summ)) summ[[j]] else list(func = "mean", col = cols[1])

                div(
                  class = "multi-summarize-pair",
                  div(
                    class = "summarize-new",
                    textInput(ns(paste0("summary_", i, "_new")), "Output name", value = nm)
                  ),
                  div(class = "summarize-equals", "="),
                  div(
                    class = "summarize-func",
                    selectInput(ns(paste0("summary_", i, "_func")), "Function",
                                choices = funcs, selected = spec$func, width = "100%")
                  ),
                  div(
                    class = "summarize-col",
                    selectInput(ns(paste0("summary_", i, "_col")), "Column",
                                choices = cols, selected = spec$col, width = "100%")
                  ),
                  if (length(indices) > 1) {
                    actionButton(ns(paste0("summary_", i, "_remove")), NULL,
                                 icon = icon("xmark"), class = "btn btn-sm summarize-delete")
                  }
                )
              })
            )
          })

          # Store validated expression
          r_expr_validated <- reactiveVal(parse_summarize_nocode(summaries, by))

          # Auto-update when summaries change
          observeEvent(list(input$add_summary, r_summary_indices()), {
            indices <- r_summary_indices()
            has_inputs <- any(sapply(indices, function(i) {
              paste0("summary_", i, "_new") %in% names(input)
            }))
            if (has_inputs) {
              current <- get_current_summaries()
              r_summaries(current)
              tryCatch({
                expr <- parse_summarize_nocode(current, r_by_selection())
                eval(expr, envir = list(data = data()))
                r_expr_validated(expr)
              }, error = function(e) NULL)
            }
          }, ignoreInit = TRUE)

          # Watch individual inputs
          observe({
            indices <- r_summary_indices()
            for (i in indices) {
              local({
                ii <- i
                observeEvent(
                  list(input[[paste0("summary_", ii, "_new")]],
                       input[[paste0("summary_", ii, "_func")]],
                       input[[paste0("summary_", ii, "_col")]]),
                  {
                    current <- get_current_summaries()
                    r_summaries(current)
                    tryCatch({
                      expr <- parse_summarize_nocode(current, r_by_selection())
                      eval(expr, envir = list(data = data()))
                      r_expr_validated(expr)
                    }, error = function(e) NULL)
                  },
                  ignoreInit = TRUE
                )
              })
            }
          })

          # Watch grouping
          observeEvent(r_by_selection(), {
            tryCatch({
              expr <- parse_summarize_nocode(r_summaries(), r_by_selection())
              eval(expr, envir = list(data = data()))
              r_expr_validated(expr)
            }, error = function(e) NULL)
          }, ignoreInit = TRUE)

          # AI Assist integration
          mod_ai_assist_server(
            "ai",
            get_data = data,
            block_ctor = new_summarize_block,
            block_name = "new_summarize_block",
            on_apply = function(args) {
              if (!is.null(args$summaries)) {
                # Normalize function names to match dropdown values
                normalized <- lapply(args$summaries, function(s) {
                  s$func <- normalize_summary_func(s$func)
                  s
                })
                r_summaries(normalized)
                # Use NEW indices to force UI re-render with fresh inputs
                current_next <- r_next_index()
                new_indices <- seq(current_next, length.out = length(normalized))
                r_summary_indices(new_indices)
                r_next_index(current_next + length(normalized))
              }
              if (!is.null(args$by)) {
                # Update group by selector UI
                updateSelectInput(
                  session,
                  inputId = "by_selector-columns",
                  selected = args$by
                )
              }
              tryCatch({
                expr <- parse_summarize_nocode(
                  r_summaries(),
                  args$by %||% r_by_selection()
                )
                r_expr_validated(expr)
              }, error = function(e) NULL)
            },
            get_current_args = function() {
              list(
                summaries = r_summaries(),
                by = r_by_selection()
              )
            }
          )

          list(
            expr = r_expr_validated,
            state = list(
              summaries = r_summaries,
              by = r_by_selection
            )
          )
        }
      )
    },
    function(id) {
      tagList(
        shinyjs::useShinyjs(),

        css_responsive_grid(),
        css_single_column("summarize"),
        css_summarize_grid(),

        div(
          class = "block-container summarize-block-container",

          # AI Assist Section
          mod_ai_assist_ui(
            NS(id, "ai"),
            placeholder = "e.g., calculate mean Sepal.Length by Species"
          ),

          div(
            class = "block-form-grid",

            # Summaries Section
            div(
              class = "block-section",
              div(
                class = "block-section-grid",
                div(
                  class = "multi-summarize-container",
                  uiOutput(NS(id, "summaries_ui")),
                  div(
                    class = "multi-summarize-actions",
                    actionButton(
                      NS(id, "add_summary"),
                      "Add Summary",
                      icon = icon("plus"),
                      class = "btn btn-outline-secondary btn-sm"
                    )
                  )
                )
              )
            ),

            # Grouping Section
            div(
              class = "block-section",
              div(
                class = "block-section-grid",
                div(
                  style = "grid-column: 1 / -1;",
                  mod_column_selector_ui(
                    NS(id, "by_selector"),
                    label = tags$span(
                      "Columns to group by (optional)",
                      style = "font-size: 0.875rem; color: #666; font-weight: normal;"
                    ),
                    initial_choices = by,
                    initial_selected = by
                  )
                )
              )
            )
          )
        )
      )
    },
    class = "summarize_block",
    allow_empty_state = c("by"),
    ...
  )
}


#' Get available summary functions
#' @noRd
get_summary_functions <- function() {
  c(
    "mean" = "mean",
    "median" = "stats::median",
    "standard deviation (sd)" = "stats::sd",
    "IQR" = "stats::IQR",
    "minimum (min)" = "min",
    "maximum (max)" = "max",
    "first" = "dplyr::first",
    "last" = "dplyr::last",
    "count rows (n)" = "dplyr::n",
    "count distinct (n_distinct)" = "dplyr::n_distinct",
    "sum" = "sum",
    "product (prod)" = "prod"
  )
}

#' Normalize function names from AI to dropdown values
#' @noRd
normalize_summary_func <- function(func) {
  # Map common names to exact dropdown values
  mapping <- c(
    "median" = "stats::median",
    "sd" = "stats::sd",
    "IQR" = "stats::IQR",
    "iqr" = "stats::IQR",
    "min" = "min",
    "max" = "max",
    "first" = "dplyr::first",
    "last" = "dplyr::last",
    "n" = "dplyr::n",
    "n_distinct" = "dplyr::n_distinct",
    "prod" = "prod"
  )
  if (func %in% names(mapping)) {
    mapping[[func]]
  } else {
    func
  }
}


#' Parse summary specifications into dplyr expression
#' @noRd
parse_summarize_nocode <- function(summaries = list(), by_selection = character()) {
  if (length(summaries) == 0) {
    return(parse(text = "dplyr::summarize(data)")[[1]])
  }

  expr_parts <- character()
  summary_names <- names(summaries)

  for (i in seq_along(summaries)) {
    spec <- summaries[[i]]
    new_name <- summary_names[i]
    func <- spec$func
    col <- spec$col

    if (is.null(new_name) || is.na(new_name) || new_name == "") next
    if (is.null(func) || is.na(func) || func == "") next

    if (func == "dplyr::n") {
      expr_parts <- c(expr_parts, glue::glue(
        "{backtick_if_needed(new_name)} = {func}()"
      ))
    } else if (func == "dplyr::n_distinct") {
      if (is.null(col) || length(col) == 0 || col == "") next
      expr_parts <- c(expr_parts, glue::glue(
        "{backtick_if_needed(new_name)} = {func}({backtick_if_needed(col)})"
      ))
    } else {
      if (is.null(col) || length(col) == 0 || col == "") next
      expr_parts <- c(expr_parts, glue::glue(
        "{backtick_if_needed(new_name)} = {func}({backtick_if_needed(col)})"
      ))
    }
  }

  if (length(expr_parts) == 0) {
    return(parse(text = "dplyr::summarize(data)")[[1]])
  }

  summarize_string <- glue::glue_collapse(expr_parts, sep = ", ")

  if (length(by_selection) > 0 && !all(by_selection == "")) {
    by_selection <- paste0("\"", by_selection, "\"", collapse = ", ")
    text <- glue::glue(
      "dplyr::summarize(data, {summarize_string}, .by = c({by_selection}))"
    )
  } else {
    text <- glue::glue("dplyr::summarize(data, {summarize_string})")
  }

  parse(text = text)[[1]]
}


#' CSS for summarize block grid
#' @noRd
css_summarize_grid <- function() {
  tags$style(HTML(
    "
    .multi-summarize-container {
      grid-column: 1 / -1;
    }

    .multi-summarize-pair {
      display: flex;
      width: 100%;
      align-items: end;
      gap: 15px;
      margin-bottom: 8px;
    }

    .multi-summarize-pair .summarize-new {
      flex: 1 1 0;
      min-width: 0;
    }

    .multi-summarize-pair .summarize-equals {
      flex: 0 0 auto;
      display: flex;
      align-items: center;
      justify-content: center;
      color: var(--bs-gray-400);
      font-size: 0.9em;
      width: 20px;
      height: 38px;
      margin-left: -10px;
      margin-right: -10px;
    }

    .multi-summarize-pair .summarize-func {
      flex: 1 1 0;
      min-width: 0;
    }

    .multi-summarize-pair .summarize-col {
      flex: 1 1 0;
      min-width: 0;
    }

    .multi-summarize-pair .summarize-delete {
      flex: 0 0 auto;
      height: 38px;
      width: 24px;
      margin-left: -10px;
      display: flex;
      align-items: center;
      justify-content: center;
      color: #6c757d;
      border: none;
      background: transparent;
      padding: 0;
    }

    .multi-summarize-pair .summarize-delete:hover {
      color: #dc3545;
      background: rgba(220, 53, 69, 0.1);
    }

    .multi-summarize-pair .shiny-input-container {
      margin-bottom: 0 !important;
    }

    .multi-summarize-pair .form-control,
    .multi-summarize-pair .selectize-control,
    .multi-summarize-pair .selectize-input {
      width: 100% !important;
      height: 38px !important;
      margin-bottom: 0 !important;
    }

    .multi-summarize-pair .selectize-input {
      min-height: 38px;
      line-height: 24px;
      padding-top: 4px;
      padding-bottom: 4px;
      display: flex;
      align-items: center;
    }

    .multi-summarize-actions {
      display: flex;
      justify-content: flex-start;
      align-items: center;
      margin-top: 0.5rem;
      margin-bottom: 0.25rem;
    }

    .multi-summarize-actions .btn-outline-secondary {
      border-color: #dee2e6;
      color: #6c757d;
    }

    .multi-summarize-actions .btn-outline-secondary:hover {
      border-color: #adb5bd;
      background-color: #f8f9fa;
      color: #495057;
    }
    "
  ))
}
