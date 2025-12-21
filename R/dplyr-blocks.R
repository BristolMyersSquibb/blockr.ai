# blockr.dplyr Block Descriptions
#
# Information about available blocks for LLM planning.


#' Get descriptions of available dplyr blocks
#'
#' Returns a list of block information suitable for LLM planning.
#'
#' @return Named list with block info (name, description, ctor)
#' @export
get_dplyr_block_info <- function() {
  list(
    filter_block = list(
      name = "filter_block",
      ctor = "new_filter_block",
      description = "Keep rows matching EXACT values. Use ONLY for exact matches like 'Species is setosa' or 'cyl equals 6'. NOT for comparisons.",
      params = "conditions: list of (column, values, mode='include'/'exclude')"
    ),
    filter_expr_block = list(
      name = "filter_expr_block",
      ctor = "new_filter_expr_block",
      description = "Keep rows using R expression with comparisons. Use for: >, <, >=, <=, != (e.g., 'mpg > 20', 'cyl >= 6', 'hp between 100 and 200')",
      params = "exprs: R expression as string"
    ),
    select_block = list(
      name = "select_block",
      ctor = "new_select_block",
      description = "Keep or drop columns. Use for: selecting specific columns or removing unwanted ones",
      params = "columns: character vector, exclude: TRUE to drop instead of keep"
    ),
    mutate_expr_block = list(
      name = "mutate_expr_block",
      ctor = "new_mutate_expr_block",
      description = "Add or modify columns using R expressions. Use for: creating new columns from existing ones (e.g., 'add column hp_per_cyl = hp/cyl')",
      params = "expression: R code as string (e.g., 'hp_per_cyl = hp / cyl')"
    ),
    summarize_block = list(
      name = "summarize_block",
      ctor = "new_summarize_block",
      description = "Aggregate data with grouping. Use for: calculating statistics like mean, sum, count per group",
      params = "summaries: list of (func, col), by: grouping columns"
    ),
    arrange_block = list(
      name = "arrange_block",
      ctor = "new_arrange_block",
      description = "Sort rows by columns. Use for: ordering data ascending or descending",
      params = "columns: list of (column, direction='asc'/'desc')"
    ),
    slice_block = list(
      name = "slice_block",
      ctor = "new_slice_block",
      description = "Take first/last N rows. Use for: getting top/bottom N rows",
      params = "type: 'head'/'tail', n: number of rows"
    ),
    rename_block = list(
      name = "rename_block",
      ctor = "new_rename_block",
      description = "Rename columns. Use for: changing column names",
      params = "mapping: named list (new_name = 'old_name')"
    ),
    pivot_wider_block = list(
      name = "pivot_wider_block",
      ctor = "new_pivot_wider_block",
      description = "Reshape from long to wide format. Use for: spreading values across columns",
      params = "names_from, values_from columns"
    ),
    pivot_longer_block = list(
      name = "pivot_longer_block",
      ctor = "new_pivot_longer_block",
      description = "Reshape from wide to long format. Use for: gathering columns into rows",
      params = "cols: columns to pivot, names_to, values_to"
    )
  )
}


#' Format block info for LLM prompt
#'
#' @param blocks List from get_dplyr_block_info()
#' @return Character string for LLM prompt
#' @export
format_blocks_for_llm <- function(blocks = get_dplyr_block_info()) {
  lines <- "Available blocks:\n"

  for (block in blocks) {
    lines <- paste0(
      lines,
      "\n- **", block$name, "**: ", block$description, "\n",
      "  Parameters: ", block$params, "\n"
    )
  }

  lines
}


#' Get block constructor by name
#'
#' @param block_name Name like "filter_block" or "new_filter_block"
#' @return The constructor function
#' @export
get_block_ctor <- function(block_name) {
  # Normalize name
  if (!startsWith(block_name, "new_")) {
    block_name <- paste0("new_", block_name)
  }

  # Get from blockr.dplyr
  tryCatch(
    getExportedValue("blockr.dplyr", block_name),
    error = function(e) {
      stop("Unknown block: ", block_name)
    }
  )
}
