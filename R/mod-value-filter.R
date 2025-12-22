# Value Filter Module for blockr.ai
#
# This module is copied from blockr.dplyr and provides the value-based
# filtering UI for the filter block.


#' Convert display value to actual value
#'
#' Converts special display strings back to their actual values (NA, empty string)
#'
#' @param value Character display value
#' @param original_type The original data type ("numeric" or "character")
#' @return The actual value (may be NA or empty string)
#' @noRd
display_to_actual <- function(value, original_type = "character") {
  if (value == "<NA>") {
    return(NA)
  } else if (value == "<empty>") {
    return("")
  } else if (original_type == "numeric") {
    return(as.numeric(value))
  } else {
    return(value)
  }
}

#' Convert actual value to display value
#'
#' Converts actual values (including NA and empty strings) to display strings
#'
#' @param value The actual value
#' @return Character display string
#' @noRd
actual_to_display <- function(value) {
  if (is.na(value)) {
    "<NA>"
  } else if (identical(value, "")) {
    "<empty>"
  } else {
    as.character(value)
  }
}

#' Value filter condition module for selecting values from columns
#'
#' A Shiny module that manages value-based filter conditions. Users can select
#' columns and choose specific discrete values to include or exclude without writing
#' R expressions. Works with both numeric and categorical columns using multi-select
#' inputs. Supports multiple conditions with AND/OR logic.
#'
#' @param id The module ID
#' @param get_value Function that returns initial conditions as a list
#' @param get_data Function that returns the data frame for extracting unique values
#' @param preserve_order Logical. If TRUE, preserves the order of selected values
#'
#' @return A list with reactive expressions for conditions and preserve_order
#' @importFrom shiny req NS moduleServer reactive actionButton observeEvent renderUI uiOutput tagList div selectInput checkboxInput updateSelectInput shinyApp selectizeInput updateSelectizeInput updateCheckboxInput observe isolate
#' @importFrom utils str
#' @importFrom shinyjs useShinyjs
#' @importFrom htmltools tags tagList
#' @noRd
mod_value_filter_server <- function(
    id,
    get_value,
    get_data,
    preserve_order = FALSE,
    set_conditions = NULL
) {
  moduleServer(id, function(input, output, session) {
    ns <- session$ns

    # Initialize with values from get_value
    initial_value <- get_value()

    if (!is.list(initial_value)) {
      initial_conditions <- list()
    } else {
      initial_conditions <- initial_value
    }

    # Add default condition if none provided
    if (length(initial_conditions) == 0) {
      initial_conditions <- list(
        list(column = NULL, values = character(0), mode = "include")
      )
    }

    # Store conditions as reactive value
    r_conditions <- reactiveVal(initial_conditions)
    r_data <- get_data

    # Store preserve_order as reactive value
    r_preserve_order <- reactiveVal(preserve_order)

    # Track which condition indices exist
    r_condition_indices <- reactiveVal(seq_along(initial_conditions))
    r_next_index <- reactiveVal(length(initial_conditions) + 1)

    # Get available columns
    available_columns <- reactive({
      req(r_data())
      colnames(r_data())
    })

    # Get unique values for a column
    get_unique_values <- function(column) {
      req(r_data(), column)
      if (!column %in% colnames(r_data())) {
        return(character(0))
      }

      values <- unique(r_data()[[column]])

      # Track whether we have NAs and empty strings
      has_na <- any(is.na(values))
      has_empty <- FALSE

      # Remove NAs temporarily for processing
      values_non_na <- values[!is.na(values)]

      # Convert factors to character for consistent handling
      if (is.factor(values_non_na)) {
        values_non_na <- as.character(values_non_na)
      }

      # Check for empty strings in character vectors
      if (is.character(values_non_na)) {
        has_empty <- any(values_non_na == "")
        # Remove empty strings temporarily
        values_non_na <- values_non_na[values_non_na != ""]
      }

      # Sort values for better UX
      if (is.numeric(values_non_na)) {
        sorted_values <- sort(values_non_na)
      } else {
        sorted_values <- sort(as.character(values_non_na))
      }

      # Convert all values to character for display
      result <- as.character(sorted_values)

      # Add special markers for empty strings and NAs at the end
      if (has_empty) {
        result <- c(result, "<empty>")
      }
      if (has_na) {
        result <- c(result, "<NA>")
      }

      result
    }

    # Collect current values from all inputs
    get_current_conditions <- function() {
      indices <- r_condition_indices()
      if (length(indices) == 0) {
        return(list())
      }

      result <- list()

      for (idx in seq_along(indices)) {
        i <- indices[idx]
        column_id <- paste0("condition_", i, "_column")
        values_id <- paste0("condition_", i, "_values")
        mode_id <- paste0("condition_", i, "_mode")

        column <- input[[column_id]]
        values <- input[[values_id]]
        mode <- if (isTRUE(input[[mode_id]])) "exclude" else "include"

        # Get operator if not the first condition
        operator <- if (idx > 1) {
          operator_id <- paste0("operator_", i)
          input[[operator_id]] %||% "&"
        } else {
          NULL
        }

        # Include condition if column is selected, even if values is empty/NULL
        if (!is.null(column) && column != "") {
          # Ensure values is a character vector, even if empty
          values <- if (is.null(values) || length(values) == 0) {
            character(0)
          } else {
            values
          }

          condition_data <- list(
            column = column,
            values = values,
            mode = mode
          )
          if (!is.null(operator)) {
            condition_data$operator <- operator
          }
          result <- append(result, list(condition_data))
        }
      }

      result
    }

    # Add new condition
    observeEvent(input$add_condition, {
      current_indices <- r_condition_indices()
      new_index <- r_next_index()

      # Add new index
      r_condition_indices(c(current_indices, new_index))
      r_next_index(new_index + 1)

      # Update conditions
      current <- get_current_conditions()
      new_condition <- list(
        column = NULL,
        values = character(0),
        mode = "include"
      )
      # Add operator if this is not the first condition
      if (length(current) > 0) {
        new_condition$operator <- "&"
      }
      current <- append(current, list(new_condition))
      r_conditions(current)
    })

    # Remove condition handlers
    observe({
      indices <- r_condition_indices()

      lapply(indices, function(i) {
        observeEvent(input[[paste0("condition_", i, "_remove")]], {
          current_indices <- r_condition_indices()

          if (length(current_indices) > 1) {
            # Remove this index
            new_indices <- setdiff(current_indices, i)
            r_condition_indices(new_indices)

            # Update conditions
            current <- get_current_conditions()
            r_conditions(current)
          }
        })
      })
    })

    # Render UI dynamically
    output$conditions_ui <- renderUI({
      indices <- r_condition_indices()
      conditions <- r_conditions()
      cols <- available_columns()

      if (length(indices) == 0) {
        return(NULL)
      }

      # Create UI for each condition
      ui_elements <- list()

      for (j in seq_along(indices)) {
        i <- indices[j]
        condition <- if (j <= length(conditions)) {
          conditions[[j]]
        } else {
          list(
            column = NULL,
            values = character(0),
            mode = "include"
          )
        }

        # Add operator dropdown before condition (except for first)
        if (j > 1) {
          operator_value <- condition$operator %||% "&"
          ui_elements <- append(
            ui_elements,
            list(
              div(
                class = "d-flex justify-content-start my-2",
                selectInput(
                  ns(paste0("operator_", i)),
                  label = NULL,
                  choices = list("AND" = "&", "OR" = "|"),
                  selected = operator_value,
                  width = "80px"
                )
              )
            )
          )
        }

        # Add the condition row with standard UI
        ui_elements <- append(
          ui_elements,
          list(
            value_filter_condition_ui(
              ns(paste0("condition_", i)),
              column = condition$column,
              values = condition$values,
              mode = condition$mode %||% "include",
              available_columns = cols,
              get_unique_values = get_unique_values,
              show_remove = (length(indices) > 1),
              ns = ns # Pass namespace function
            )
          )
        )
      }

      tagList(ui_elements)
    })

    # Handle dynamic updates for each condition
    observe({
      indices <- r_condition_indices()

      for (i in indices) {
        local({
          index <- i
          column_id <- paste0("condition_", index, "_column")
          values_id <- paste0("condition_", index, "_values")

          # Update select input choices when column changes
          observeEvent(input[[column_id]], {
            column <- input[[column_id]]
            if (!is.null(column) && column != "") {
              unique_vals <- get_unique_values(column)
              # Get current condition to preserve selected values if they exist
              current_conds <- isolate(r_conditions())
              saved_values <- NULL
              for (j in seq_along(current_conds)) {
                if (j <= length(isolate(r_condition_indices()))) {
                  if (isolate(r_condition_indices())[j] == index) {
                    cond_column <- current_conds[[j]]$column
                    if (
                      !is.null(cond_column) &&
                        length(cond_column) > 0 &&
                        !is.null(column) &&
                        length(column) > 0 &&
                        cond_column == column
                    ) {
                      saved_values <- current_conds[[j]]$values
                    }
                    break
                  }
                }
              }
              updateSelectizeInput(
                session,
                values_id,
                choices = unique_vals,
                selected = saved_values
              )
            } else {
              # Clear selections when no column selected
              updateSelectizeInput(
                session,
                values_id,
                choices = list(),
                selected = character(0)
              )
            }
          })
        })
      }
    })

    # Initialize preserve_order checkbox with saved value
    observe({
      # Only update once when the input becomes available
      if ("preserve_order" %in% names(input)) {
        initial_value <- isolate(r_preserve_order())
        if (!is.null(initial_value) && initial_value != input$preserve_order) {
          updateCheckboxInput(session, "preserve_order", value = initial_value)
        }
      }
    })

    # Handle preserve_order checkbox changes
    observeEvent(input$preserve_order, {
      r_preserve_order(input$preserve_order)
    })

    # Handle external updates to conditions (from AI assist)
    if (!is.null(set_conditions)) {
      observeEvent(set_conditions(), {
        new_conditions <- set_conditions()
        if (!is.null(new_conditions) && is.list(new_conditions)) {
          # Update the reactive value
          r_conditions(new_conditions)

          # Reset condition indices to match new conditions
          r_condition_indices(seq_along(new_conditions))
          r_next_index(length(new_conditions) + 1)
        }
      }, ignoreInit = TRUE)
    }

    # Return the reactive conditions and preserve_order
    list(
      conditions = reactive({
        # Force reactivity on all condition inputs
        indices <- r_condition_indices()

        # Touch all relevant input values to create dependencies
        for (i in indices) {
          input[[paste0("condition_", i, "_column")]]
          input[[paste0("condition_", i, "_values")]]
          input[[paste0("condition_", i, "_mode")]]
          # Also track operator changes
          if (i != indices[1]) {
            input[[paste0("operator_", i)]]
          }
        }

        # Check if any inputs exist yet
        has_inputs <- any(sapply(indices, function(i) {
          paste0("condition_", i, "_column") %in% names(input)
        }))

        if (has_inputs) {
          get_current_conditions()
        } else {
          r_conditions()
        }
      }),
      preserve_order = reactive({
        # Return input value if it exists, otherwise use the initial value
        if ("preserve_order" %in% names(input)) {
          input$preserve_order
        } else {
          r_preserve_order()
        }
      }),
      # Expose the internal reactiveVal for external updates
      set_conditions = function(new_conditions) {
        if (!is.null(new_conditions) && is.list(new_conditions)) {
          r_conditions(new_conditions)
          r_condition_indices(seq_along(new_conditions))
          r_next_index(length(new_conditions) + 1)
        }
      },
      set_preserve_order = function(value) {
        if (!is.null(value) && is.logical(value)) {
          r_preserve_order(value)
          updateCheckboxInput(session, "preserve_order", value = value)
        }
      }
    )
  })
}

#' Create value filter UI module
#'
#' @param id The module ID
#' @return A div containing the UI elements
#' @noRd
mod_value_filter_ui <- function(id) {
  ns <- NS(id)

  tagList(
    shinyjs::useShinyjs(),
    # Minimal layout CSS - only grid structure for condition rows
    css_value_filter_grid(),
    div(
      uiOutput(ns("conditions_ui")),
      div(
        class = "d-flex align-items-center gap-3 mt-2 mb-1",
        actionButton(
          ns("add_condition"),
          label = "Add Condition",
          icon = icon("plus"),
          class = "btn btn-outline-secondary btn-sm"
        )
      ),
      div(
        class = "mt-4 filter-preserve-order",
        checkboxInput(
          ns("preserve_order"),
          label = "Preserve selection order (drag to reorder)",
          value = FALSE
        )
      )
    )
  )
}

#' Create UI for a single value filter condition row
#'
#' @param id Row identifier
#' @param column Selected column name
#' @param values Selected values
#' @param mode Include or exclude mode
#' @param available_columns Available column choices
#' @param get_unique_values Function to get unique values for a column
#' @param show_remove Whether to show remove button
#' @param ns Namespace function (unused, kept for compatibility)
#' @return A div containing the row UI
#' @noRd
value_filter_condition_ui <- function(
    id,
    column = NULL,
    values = character(0),
    mode = "include",
    available_columns = character(0),
    get_unique_values = function(col) character(0),
    show_remove = TRUE,
    ns = function(x) x # Kept for compatibility
) {
  # Initialize choices - populate with actual values if we have a column
  unique_values <- if (!is.null(column) && column != "") {
    get_unique_values(column)
  } else {
    list()
  }

  div(
    class = "value-filter-condition mb-1",
    div(
      class = "value-filter-grid",
      div(
        class = "vf-column",
        selectInput(
          paste0(id, "_column"),
          label = "Column",
          choices = c("Select column..." = "", available_columns),
          selected = column,
          width = "100%"
        )
      ),
      div(
        class = if (show_remove) "vf-values" else "vf-values vf-values-full",
        selectizeInput(
          paste0(id, "_values"),
          label = "Values",
          choices = unique_values,
          selected = values,
          multiple = TRUE,
          width = "100%",
          options = list(
            plugins = list("drag_drop", "remove_button"),
            persist = FALSE
          )
        )
      ),
      if (show_remove) {
        div(
          class = "vf-delete d-flex align-items-center",
          actionButton(
            paste0(id, "_remove"),
            label = NULL,
            icon = icon("xmark"),
            class = "btn btn-link text-muted p-0",
            title = "Remove this condition"
          )
        )
      },
      div(
        class = "vf-mode d-flex align-items-center mt-1",
        checkboxInput(
          paste0(id, "_mode"),
          label = "Exclude",
          value = (mode == "exclude")
        )
      )
    )
  )
}


# =============================================================================
# CSS Utilities (copied from blockr.dplyr/R/css.R)
# =============================================================================

#' Responsive grid layout CSS for blocks
#'
#' Creates CSS for responsive grid layout with consistent styling.
#' This is the foundation CSS that must be loaded by all blocks.
#'
#' @return HTML style tag with responsive grid CSS
#' @noRd
css_responsive_grid <- function() {
  tags$style(HTML(
    "
    .block-container {
      width: 100%;
      padding-bottom: 10px;
    }

    /* One shared grid across the whole form */
    .block-form-grid {
      display: grid;
      gap: 15px;
      grid-template-columns: repeat(auto-fit, minmax(250px, 1fr));
    }

    /* Flatten wrappers so all controls share the same tracks */
    .block-section,
    .block-section-grid {
      display: contents;
    }

    /* Headings/help span full width in grid */
    .block-section h4,
    .block-help-text {
      grid-column: 1 / -1;
    }

    .block-section:not(:first-child) {
      margin-top: 20px;
    }

    .block-input-wrapper {
      width: 100%;
    }

    .block-input-wrapper .form-group {
      margin-bottom: 10px;
    }
    "
  ))
}

#' Force single-column layout for a block
#'
#' @param block_name Character string, name of the block
#' @return HTML style tag with single-column grid CSS
#' @noRd
css_single_column <- function(block_name) {
  tags$style(HTML(sprintf(
    "
    .%s-block-container .block-form-grid {
      grid-template-columns: 1fr !important;
    }
    ",
    block_name
  )))
}

#' CSS grid layout for value filter conditions
#'
#' Provides the grid structure for value filter condition rows.
#'
#' @return HTML style tag with value filter grid CSS
#' @noRd
css_value_filter_grid <- function() {
  tags$style(HTML(
    "
    /* Grid layout for condition rows */
    .value-filter-grid {
      display: grid;
      grid-template-columns: 1fr 1fr auto;
      gap: 0 15px; /* row-gap: 0, column-gap: 15px */
      align-items: end;
    }

    .value-filter-grid .vf-column { grid-column: 1; grid-row: 1; }
    .value-filter-grid .vf-values { grid-column: 2; grid-row: 1; }
    .value-filter-grid .vf-values-full { grid-column: 2 / -1; }
    .value-filter-grid .vf-delete {
      grid-column: 3;
      grid-row: 1;
      height: 38px; /* Match input height */
      display: flex;
      align-items: center;
    }
    .value-filter-grid .vf-mode   { grid-column: 1 / -1; grid-row: 2; }

    /* Remove Shiny's default input margins within value filter */
    .value-filter-condition .shiny-input-container {
      margin-bottom: 0 !important;
    }

    /* Consistent height for form controls */
    .value-filter-condition .selectize-input {
      min-height: 38px;
    }

    /* Remove bottom margin from preserve order checkbox */
    .filter-preserve-order .form-group,
    .filter-preserve-order .checkbox {
      margin-bottom: 0;
    }
    "
  ))
}
