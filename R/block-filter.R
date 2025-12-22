#' Filter block constructor with AI assistance
#'
#' This block allows filtering rows in a data frame by selecting specific values
#' from columns (see [dplyr::filter()]). Provides a visual interface where users
#' can select columns and choose which values to include or exclude without
#' writing R expressions. Supports multiple conditions with AND/OR logic.
#'
#' This version includes an integrated AI assistant that can configure the
#' filter conditions based on natural language descriptions.
#'
#' @param conditions List of filter conditions. Each condition should be a list
#'   with elements: column (character), values (vector), mode ("include" or "exclude"),
#'   and optionally operator ("&" or "|") specifying how this condition connects to
#'   the previous one
#' @param preserve_order Logical. If TRUE, preserves the order of selected values
#'   in the filtered output (default: FALSE)
#' @param ... Additional arguments forwarded to [new_block()]
#'
#' @return A block object for value-based filter operations with AI assistance
#' @importFrom shiny req showNotification NS moduleServer reactive actionButton observeEvent icon div
#' @importFrom glue glue
#' @seealso [blockr.core::new_transform_block()]
#' @examples
#' # Create a filter block
#' new_filter_block()
#'
#' if (interactive()) {
#'   library(blockr.core)
#'
#'   # Basic usage with mtcars dataset
#'   serve(new_filter_block(), list(data = mtcars))
#'
#'   # With initial condition
#'   serve(new_filter_block(
#'     conditions = list(
#'       list(column = "cyl", values = c(4, 6), mode = "include")
#'     )
#'   ), list(data = mtcars))
#'
#'   # Connected blocks example (dataset -> filter)
#'   serve(
#'     new_board(
#'       blocks = list(
#'         a = new_dataset_block(dataset = "iris"),
#'         b = new_filter_block()
#'       ),
#'       links = links(
#'         from = c("a"),
#'         to = c("b")
#'       )
#'     )
#'   )
#' }
#' @export
new_filter_block <- function(
    conditions = list(),
    preserve_order = FALSE,
    ...
) {
  blockr.core::new_transform_block(
    function(id, data) {
      moduleServer(
        id,
        function(input, output, session) {
          # Reactive value to hold conditions set by AI
          r_ai_conditions <- reactiveVal(NULL)

          # Use value filter interface
          filter_result <- mod_value_filter_server(
            id = "vf",
            get_value = \() conditions,
            get_data = data,
            preserve_order = preserve_order
          )

          r_conditions <- filter_result$conditions
          r_preserve_order <- filter_result$preserve_order

          # AI Assist integration
          mod_ai_assist_server(
            "ai",
            get_data = data,
            block_ctor = new_filter_block,
            block_name = "new_filter_block",
            on_apply = function(args) {
              # Map discovered args to filter reactive values
              if (!is.null(args$conditions)) {
                filter_result$set_conditions(args$conditions)
              }
              if (!is.null(args$preserve_order)) {
                filter_result$set_preserve_order(args$preserve_order)
              }
            },
            get_current_args = function() {
              list(
                conditions = r_conditions(),
                preserve_order = r_preserve_order()
              )
            }
          )

          # Reactive expression that updates automatically when conditions change
          r_expr <- reactive({
            current_conditions <- r_conditions()
            current_preserve_order <- r_preserve_order()

            # Always try to parse, even with empty/invalid conditions
            tryCatch(
              {
                parse_value_filter(
                  current_conditions,
                  preserve_order = current_preserve_order
                )
              },
              error = function(e) {
                # Fallback to identity filter if parsing fails
                parse(text = "dplyr::filter(data, TRUE)")[[1]]
              }
            )
          })

          list(
            expr = r_expr,
            state = list(
              conditions = r_conditions,
              preserve_order = r_preserve_order
            )
          )
        }
      )
    },
    function(id) {
      tagList(
        shinyjs::useShinyjs(),

        # Add CSS
        css_responsive_grid(),
        css_single_column("value-filter"),

        div(
          class = "block-container value-filter-block-container",

          # AI Assist Section at top
          mod_ai_assist_ui(
            NS(id, "ai"),
            placeholder = "Describe what you want... (e.g., keep only rows where cyl equals 6)"
          ),

          div(
            class = "block-form-grid",

            # Value Filter Section
            div(
              class = "block-section",
              div(
                class = "block-section-grid",
                mod_value_filter_ui(NS(id, "vf"))
              )
            )
          )
        )
      )
    },
    class = "filter_block",
    ...
  )
}


#' Parse value filter conditions into dplyr expression
#'
#' @param conditions List of filter conditions
#' @param preserve_order Logical. If TRUE, preserves order of selected values
#' @return A parsed expression object
#' @noRd
parse_value_filter <- function(conditions = list(), preserve_order = FALSE) {
  if (length(conditions) == 0) {
    # No conditions - return identity filter
    text <- "dplyr::filter(data, TRUE)"
  } else {
    # Build filter expressions from conditions
    filter_parts <- character(0)
    # Track conditions that need order preservation
    order_columns <- character(0)
    order_values_list <- list()

    for (i in seq_along(conditions)) {
      condition <- conditions[[i]]

      if (is.null(condition$column) || condition$column == "") {
        next # Skip conditions without a column
      }

      column <- condition$column
      values <- condition$values
      mode <- condition$mode %||% "include"

      # Handle empty values - skip conditions with no values
      if (is.null(values) || length(values) == 0) {
        next # Skip conditions without values
      }

      # Separate special values from regular values
      has_na <- "<NA>" %in% values
      has_empty <- "<empty>" %in% values
      regular_values <- values[!values %in% c("<NA>", "<empty>")]

      # Build filter parts for regular values
      filter_parts_current <- character(0)

      if (length(regular_values) > 0) {
        # Try to convert to numeric if all regular values are numeric strings
        numeric_values <- suppressWarnings(as.numeric(regular_values))
        if (all(!is.na(numeric_values))) {
          values_str <- paste(numeric_values, collapse = ", ")
        } else {
          values_str <- paste(sprintf('"%s"', regular_values), collapse = ", ")
        }

        if (mode == "include") {
          filter_parts_current <- c(
            filter_parts_current,
            glue::glue("`{column}` %in% c({values_str})")
          )
        } else {
          filter_parts_current <- c(
            filter_parts_current,
            glue::glue("!(`{column}` %in% c({values_str}))")
          )
        }
      }

      # Add NA handling
      if (has_na) {
        if (mode == "include") {
          filter_parts_current <- c(
            filter_parts_current,
            glue::glue("is.na(`{column}`)")
          )
        } else {
          filter_parts_current <- c(
            filter_parts_current,
            glue::glue("!is.na(`{column}`)")
          )
        }
      }

      # Add empty string handling
      if (has_empty) {
        if (mode == "include") {
          filter_parts_current <- c(
            filter_parts_current,
            glue::glue('`{column}` == ""')
          )
        } else {
          filter_parts_current <- c(
            filter_parts_current,
            glue::glue('`{column}` != ""')
          )
        }
      }

      # Combine current filter parts with OR for include mode, AND for exclude mode
      if (length(filter_parts_current) > 1) {
        if (mode == "include") {
          # For include mode: value1 OR value2 OR is.na OR empty
          filter_part <- paste0(
            "(",
            paste(filter_parts_current, collapse = " | "),
            ")"
          )
        } else {
          # For exclude mode: NOT value1 AND NOT value2 AND NOT is.na AND NOT empty
          filter_part <- paste0(
            "(",
            paste(filter_parts_current, collapse = " & "),
            ")"
          )
        }
      } else if (length(filter_parts_current) == 1) {
        filter_part <- filter_parts_current[1]
      } else {
        next # Skip if no valid parts
      }

      # Track for order preservation if enabled (only for regular values)
      if (preserve_order && length(regular_values) > 0) {
        order_columns <- c(order_columns, column)
        # Reconstruct values_str for order preservation
        numeric_values <- suppressWarnings(as.numeric(regular_values))
        if (all(!is.na(numeric_values))) {
          order_values_list[[column]] <- paste(numeric_values, collapse = ", ")
        } else {
          order_values_list[[column]] <- paste(
            sprintf('"%s"', regular_values),
            collapse = ", "
          )
        }
      }

      filter_parts <- c(filter_parts, filter_part)
    }

    if (length(filter_parts) == 0) {
      text <- "dplyr::filter(data, TRUE)"
    } else if (length(filter_parts) == 1) {
      # Single condition - no operators needed
      text <- glue::glue("dplyr::filter(data, {filter_parts[1]})")
    } else {
      # Multiple conditions - combine with operators from conditions
      combined_filter <- filter_parts[1]
      for (i in 2:length(filter_parts)) {
        # Get operator from the condition (default to AND if not specified)
        operator <- conditions[[i]]$operator %||% "&"
        op <- if (operator == "|") " | " else " & "
        combined_filter <- paste0(combined_filter, op, filter_parts[i])
      }
      text <- glue::glue("dplyr::filter(data, {combined_filter})")
    }

    # Add arrange() to preserve order if requested
    if (preserve_order && length(order_columns) > 0) {
      # Build arrange expressions for each column that needs ordering
      arrange_parts <- character(0)
      for (col in order_columns) {
        values_str <- order_values_list[[col]]
        arrange_parts <- c(
          arrange_parts,
          glue::glue("match(`{col}`, c({values_str}))")
        )
      }

      if (length(arrange_parts) > 0) {
        arrange_expr <- paste(arrange_parts, collapse = ", ")
        text <- glue::glue("{text} |> dplyr::arrange({arrange_expr})")
      }
    }
  }

  parse(text = text)[[1]]
}
