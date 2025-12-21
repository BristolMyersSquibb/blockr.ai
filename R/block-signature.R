# Block Signature Utilities
#
# Functions to introspect block constructors and format their signatures
# for use in LLM prompts.


#' Get block signature information
#'
#' Extracts parameter information from a block constructor function.
#'
#' @param block_ctor Block constructor function (e.g., new_summarize_block)
#' @return List with:
#'   - name: Constructor function name
#'   - params: Named list of parameters with their default values
#'   - param_names: Character vector of parameter names (excluding ...)
#'
#' @examples
#' \dontrun{
#' sig <- get_block_signature(blockr.dplyr::new_summarize_block)
#' sig$param_names
#' # [1] "summaries" "by"
#' }
#'
#' @export
get_block_signature <- function(block_ctor, name = NULL) {
  # Get the function name - try multiple approaches
  if (is.null(name)) {
    # Try to get from the call
    ctor_name <- deparse(substitute(block_ctor))
    if (ctor_name == "block_ctor") {
      # Fallback: try to extract from environment
      ctor_name <- tryCatch({
        # Check if it has a ctor attribute (from blockr registry)
        attr_name <- attr(block_ctor, "ctor_name")
        if (!is.null(attr_name)) {
          attr_name
        } else {
          "unknown_block"
        }
      }, error = function(e) "unknown_block")
    }
  } else {
    ctor_name <- name
  }

  # Get formals (parameters with defaults)
  params <- formals(block_ctor)

  # Remove ... from params
  param_names <- setdiff(names(params), "...")
  params_clean <- params[param_names]

  list(
    name = ctor_name,
    params = params_clean,
    param_names = param_names
  )
}


#' Format block signature for LLM prompt
#'
#' Converts a block signature to a human-readable format suitable
#' for inclusion in an LLM prompt.
#'
#' @param block_ctor Block constructor function
#' @return Character string with formatted signature
#'
#' @examples
#' \dontrun{
#' cat(format_block_signature(blockr.dplyr::new_summarize_block))
#' }
#'
#' @export
format_block_signature <- function(block_ctor, name = NULL) {
  sig <- get_block_signature(block_ctor, name = name)

  lines <- character()
  lines <- c(lines, paste0("Block: ", sig$name))
  lines <- c(lines, "")
  lines <- c(lines, "Parameters:")

  for (param_name in sig$param_names) {
    default_val <- sig$params[[param_name]]

    # Format the default value
    if (is.call(default_val) || is.symbol(default_val)) {
      # It's an expression - deparse it
      default_str <- paste(deparse(default_val), collapse = " ")
    } else if (is.character(default_val)) {
      if (length(default_val) == 0) {
        default_str <- 'character()'
      } else {
        default_str <- paste0('"', default_val, '"')
      }
    } else if (is.logical(default_val)) {
      default_str <- as.character(default_val)
    } else if (is.numeric(default_val)) {
      default_str <- as.character(default_val)
    } else if (is.list(default_val)) {
      default_str <- paste(deparse(default_val), collapse = " ")
    } else {
      default_str <- paste(deparse(default_val), collapse = " ")
    }

    lines <- c(lines, paste0("  - ", param_name, ": ", default_str))

    # Add description based on parameter name and default value
    desc <- infer_param_description(param_name, default_val)
    if (!is.null(desc)) {
      lines <- c(lines, paste0("    ", desc))
    }
  }

  # Add example if available
  example <- get_block_example(sig$name)
  if (!is.null(example)) {
    lines <- c(lines, "")
    lines <- c(lines, "Example:")
    lines <- c(lines, paste0("  ", example))
  }

  paste(lines, collapse = "\n")
}


#' Get example usage for a block
#'
#' @param block_name Name of the block constructor
#' @return Character string with example, or NULL
#' @noRd
get_block_example <- function(block_name) {
  examples <- list(
    new_summarize_block = 'list(summaries = list(mean_hp = list(func = "mean", col = "hp")), by = "cyl")',
    new_filter_block = 'list(conditions = list(list(column = "Species", values = "setosa", mode = "include")))',
    new_filter_expr_block = 'list(exprs = "mpg > 20 & cyl == 4")',
    new_select_block = 'list(columns = c("mpg", "cyl", "hp"), exclude = FALSE)',
    new_mutate_block = 'list(exprs = list(hp_per_cyl = "hp / cyl", is_efficient = "mpg > 25"))',
    new_arrange_block = 'list(columns = list(list(column = "mpg", direction = "desc")))'
  )
  examples[[block_name]]
}


#' Infer parameter description from name and default value
#'
#' @param param_name Name of the parameter
#' @param default_val Default value
#' @return Character string with description, or NULL
#' @noRd
infer_param_description <- function(param_name, default_val) {
  # Common parameter patterns
  if (param_name == "summaries") {
    return("Named list of summaries. Each item: list(func = 'function_name', col = 'column_name')")
  }
  if (param_name == "by") {
    return("Character vector of column names to group by")
  }
  if (param_name == "conditions") {
    return("List of filter conditions. Each: list(column = 'col', values = c(...), mode = 'include'/'exclude')")
  }
  if (param_name == "columns") {
    # Check parent function context based on other parameters
    return("Character vector of column names, OR list of specs: list(list(column='name', direction='asc'/'desc'))")
  }
  if (param_name == "exprs") {
    if (is.list(default_val)) {
      return("Named list of R expressions as strings (e.g., list(new_col = 'old_col * 2'))")
    } else {
      return("R expression as string (e.g., 'column > 5')")
    }
  }
  if (param_name == "exclude" && is.logical(default_val)) {
    return("If TRUE, exclude the specified columns instead of selecting them")
  }
  if (param_name == "distinct" && is.logical(default_val)) {
    return("If TRUE, return only distinct rows")
  }
  if (param_name == "preserve_order" && is.logical(default_val)) {
    return("If TRUE, preserve the order of selected values")
  }

  NULL
}


#' Get available aggregation functions for summarize block
#'
#' Returns a list of common aggregation functions that can be used
#' in the summarize block.
#'
#' @return Character vector of function names
#' @export
get_summarize_functions <- function() {
  c(
    "mean", "median", "sum", "min", "max",
    "sd", "var", "first", "last",
    "dplyr::n", "dplyr::n_distinct"
  )
}
