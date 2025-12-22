# Helper Modules for blockr.ai Blocks
#
# This file contains reusable helper modules and utility functions
# copied/adapted from blockr.dplyr for use with AI-integrated blocks.


#' Check if names need backticks for dplyr operations (vectorized)
#'
#' @param names Character vector of names to check
#' @return Logical vector indicating if backticks are needed
#' @noRd
needs_backticks <- function(names) {
  # Check which names are non-syntactic
  needs_bt <- make.names(names) != names
  # Empty or NA names don't need backticks (handled separately)
  needs_bt[is.na(names) | names == ""] <- FALSE
  needs_bt
}

#' Wrap names in backticks if needed (vectorized)
#'
#' @param names Character vector of names to potentially wrap
#' @return Character vector with non-syntactic names wrapped in backticks
#' @noRd
backtick_if_needed <- function(names) {
  needs_bt <- needs_backticks(names)
  names[needs_bt] <- sprintf("`%s`", names[needs_bt])
  names
}


#' Generic Multi-Column Selector Module UI
#'
#' A reusable Shiny module for selecting multiple columns from a dataset.
#'
#' @param id Character string. Module ID.
#' @param label Label for the selector (character or tag).
#' @param initial_choices Character vector. Initial choices for the selector.
#' @param initial_selected Character vector. Initial selected values.
#' @param width Width of the input (e.g., "100%", "300px", NULL for default).
#'
#' @return A shiny tag for the select input.
#' @noRd
mod_column_selector_ui <- function(
    id,
    label,
    initial_choices = character(),
    initial_selected = character(),
    width = NULL
) {
  ns <- NS(id)
  selectInput(
    inputId = ns("columns"),
    label = label,
    choices = initial_choices,
    selected = initial_selected,
    multiple = TRUE,
    width = width
  )
}

#' Generic Multi-Column Selector Server Module
#'
#' @param id Character string. Module ID.
#' @param get_cols Reactive function that returns available column names.
#' @param initial_value Character vector. Initial selected columns.
#'
#' @return A reactive containing selected column names.
#' @noRd
mod_column_selector_server <- function(id, get_cols, initial_value = character()) {
  moduleServer(id, function(input, output, session) {
    # Reactive to store current selection
    r_selection <- reactiveVal(initial_value)

    # Update reactive value when selection changes
    observeEvent(
      input$columns,
      {
        r_selection(input$columns %||% character())
      }
    )

    # Update choices when data changes, preserving selection
    observeEvent(get_cols(), {
      current_cols <- get_cols()
      if (length(current_cols) > 0) {
        updateSelectInput(
          session,
          inputId = "columns",
          choices = current_cols,
          selected = r_selection()
        )
      }
    })

    # Return the reactive selection
    r_selection
  })
}


#' CSS for collapsible advanced options section
#'
#' Provides standardized CSS for expandable/collapsible sections with
#' animated chevron indicator.
#'
#' @param id Character string, the namespaced ID for the advanced options div.
#' @param use_subgrid Logical, whether to use CSS subgrid for better grid integration.
#' @return HTML style tag with advanced toggle CSS
#' @noRd
css_advanced_toggle <- function(id, use_subgrid = FALSE) {
  subgrid_css <- if (use_subgrid) {
    "
    grid-column: 1 / -1;
    display: grid;
    grid-template-columns: subgrid;
    gap: 15px;
    "
  } else {
    ""
  }

  tags$style(HTML(sprintf(
    "
    #%s {
      max-height: 0;
      overflow: hidden;
      transition: max-height 0.3s ease-out;
      %s
    }
    #%s.expanded {
      max-height: 500px;
      overflow: visible;
      transition: max-height 0.5s ease-in;
    }
    .block-advanced-toggle {
      cursor: pointer;
      user-select: none;
      padding: 8px 0;
      margin-bottom: 0;
      display: flex;
      align-items: center;
      gap: 6px;
      font-size: 0.8125rem;
    }
    .block-chevron {
      transition: transform 0.2s;
      display: inline-block;
      font-size: 14px;
      font-weight: bold;
    }
    .block-chevron.rotated {
      transform: rotate(90deg);
    }
    ",
    id,
    subgrid_css,
    id
  )))
}


#' CSS for documentation helper links
#'
#' Provides standardized styling for inline documentation links.
#'
#' @return HTML style tag with documentation link CSS
#' @noRd
css_doc_links <- function() {
  tags$style(HTML(
    "
    .expression-help-link {
      margin-top: 0.25rem;
      margin-bottom: 0.5rem;
      display: block;
    }
    "
  ))
}
