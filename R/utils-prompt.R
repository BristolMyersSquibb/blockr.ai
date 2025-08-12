#' LLM system prompts
#'
#' System prompts for instructing the LLM to return code using certain packages,
#' adhering to certain styles, etc. are created per LLM block class and a
#' corresponding S3 generic is available as `system_prompt()`, which is
#' dispatched on LLM block proxy objects.
#'
#' @param x LLM block proxy object
#' @param ... Generic consistency
#'
#' @return A string.
#'
#' @export
system_prompt <- function(x, ...) {
  UseMethod("system_prompt")
}

#' @rdname system_prompt
#' @export
system_prompt.default <- function(x, ...) {
  paste0(
    "You are an R programming assistant.\n",
    "Your task is to produce working R code according to user instructions.\n",
    "In addition, you should provide clear explanations to accompany the ",
    "generated R code.\n",
    "Important: If you call functions in packages, always use namespace ",
    "prefixes. Do not use library calls for attaching package namespaces.\n"
  )
}

#' @param datasets Data sets from which to extract metadata
#' @param has_image Whether an image has been uploaded (optional)
#' @rdname system_prompt
#' @export
system_prompt.llm_block_proxy <- function(x, datasets, has_image = FALSE, ...) {

  build_metadata <- blockr_option("make_meta_data", build_metadata_default)

  if (!is.function(build_metadata)) {
    build_metadata <- get(build_metadata, mode = "function")
  }

  metadata <- build_metadata(datasets)

  # Format metadata for better LLM understanding
  metadata_text <- format_metadata_for_prompt(metadata$summaries, names(datasets))
  
  res <- paste0(
    system_prompt.default(x, ...),
    "\n\n",
    "You have the following dataset(s) at your disposal: ",
    paste(shQuote(names(datasets)), collapse = ", "), ".\n",
    metadata$description, "\n\n",
    metadata_text, "\n\n",
    "IMPORTANT: Be very careful to use only the provided dataset names in your code.\n",
    "This means you should not use generic names of undefined datasets ",
    "like `x`, `df`, or `my_data` unless these are explicitly provided.\n",
    "You should not produce code to rebuild the input objects.\n",
    "Use the exact dataset names shown above: ", 
    paste(shQuote(names(datasets)), collapse = ", "), ".\n"
  )
}

#' @rdname system_prompt
#' @export
system_prompt.llm_transform_block_proxy <- function(x, datasets, ...) {

  paste0(
    system_prompt.llm_block_proxy(x, datasets, ...),
    "\n\n",
    "Your task is to transform input datasets into a single output dataset.\n",
    "If possible, use dplyr for data transformations.\n",
    "Use the base R pipe and not the magrittr pipe to make nested function ",
    "calls more readable.\n\n",
    "Example of good code you might write:\n",
    "data |>\n",
    "  dplyr::group_by(category) |>\n",
    "  dplyr::summarize(mean_value = mean(value))\n\n",
    "CRITICAL: Your code MUST always return a data.frame object as the ",
    "final result. Do NOT return lists, vectors, or other object types.\n",
    "BAD examples that will FAIL:\n",
    "- Returning a list: list(summary = data)\n",
    "- Returning a vector: c(1, 2, 3)\n",
    "- Returning other objects: matrix(), tibble without data.frame conversion\n"
  )
}

#' @rdname system_prompt
#' @export
system_prompt.llm_plot_block_proxy <- function(x, datasets, has_image = FALSE, ...) {

  base_prompt <- paste0(
    system_prompt.llm_block_proxy(x, datasets, has_image = has_image, ...),
    "\n\n",
    "Your task is to produce code to generate a data visualization using ",
    "the ggplot2 package.\n",
    "Example of good code you might write:\n",
    "ggplot2::ggplot(data) +\n",
    "  ggplot2::geom_point(ggplot2::aes(x = displ, y = hwy)) +\n",
    "  ggplot2::facet_wrap(~ class, nrow = 2)\n\n",
    "CRITICAL: Your code MUST always return a ggplot2 object as the ",
    "final result. The plot must be complete and renderable.\n",
    "BAD examples that will FAIL:\n",
    "- Saving to file: ggsave('plot.png', plot)\n",
    "- Returning NULL or other objects\n",
    "- Using base R plot() functions\n",
    "- Incomplete ggplot objects missing required aesthetics\n",
    "GOOD: Always end with a complete ggplot2::ggplot() + geom_*() expression.\n"
  )

  # Add image-specific instructions if image is present
  if (has_image) {
    base_prompt <- paste0(
      base_prompt,
      "\n\nIMAGE CONTEXT: An example image has been provided. Use it as visual ",
      "reference for the style, layout, or approach you should follow in your ",
      "visualization. Pay attention to colors, themes, chart types, and overall ",
      "aesthetic choices shown in the example image.\n"
    )
  }

  base_prompt
}

#' @rdname system_prompt
#' @export
system_prompt.llm_gt_block_proxy <- function(x, datasets, has_image = FALSE, ...) {

  base_prompt <- paste0(
    system_prompt.llm_block_proxy(x, datasets, has_image = has_image, ...),
    "\n\n",
    "Your task is to produce code to generate a table using the gt package.\n",
    "Example of good code you might write:\n",
    "gt::gt(data) |>\n",
    "  gt::tab_header(\n",
    "    title = \"Summary Statistics\",\n",
    "    subtitle = \"Data Overview\"\n",
    "  ) |>\n",
    "  gt::fmt_number(columns = c(mpg, hp), decimals = 1)\n\n",
    "CRITICAL: Your code MUST always return a properly constructed gt object.\n",
    "- ALWAYS start with gt::gt(your_data_frame)\n",
    "- Use the pipe operator |> to chain gt functions\n",
    "- Always use namespace prefixes: gt::tab_header(), gt::fmt_number(), etc.\n\n",
    "BAD examples that will FAIL:\n",
    "- Returning a data.frame instead of gt object\n",
    "- Missing gt::gt() constructor: tab_header(data, title = 'x')\n",
    "- Malformed function calls with syntax errors\n",
    "- Using print() or other output functions\n\n",
    "GOOD: Always end with a complete gt pipeline starting with gt::gt(data).\n"
  )

  # Add image-specific instructions if image is present
  if (has_image) {
    base_prompt <- paste0(
      base_prompt,
      "\n\nIMAGE CONTEXT: An example image has been provided showing a table ",
      "layout or formatting style. Use it as reference for the visual appearance, ",
      "styling, colors, and formatting approach you should follow in your gt table. ",
      "Pay attention to headers, borders, alignment, and overall design shown in the example.\n"
    )
  }

  # Add explicit console output for debugging
  cat("==== GT BLOCK SYSTEM PROMPT ====\n")
  cat(base_prompt)
  cat("\n==== END GT BLOCK SYSTEM PROMPT ====\n")

  # Also use the logging system
  log_info("GT Block system prompt generated for datasets: ", paste(names(datasets), collapse = ", "))

  base_prompt
}

build_metadata_default <- function(x) {
  # Use the rich metadata extraction with no filtering patterns
  # This ensures we capture all variables and their unique values
  metadata <- make_metadata(x, extract_codelist_vars = NULL)
  
  list(
    description = paste0(
      "You have access to the following datasets with their detailed metadata: "
    ),
    summaries = metadata$datasets
  )
}

#' Format metadata for LLM prompt
#' 
#' @param metadata_list List of metadata for each dataset
#' @param dataset_names Names of the datasets
#' @return Formatted string for LLM prompt
format_metadata_for_prompt <- function(metadata_list, dataset_names) {
  if (length(metadata_list) == 0) return("")
  
  formatted_parts <- mapply(function(meta, name) {
    if (is.null(meta$variables) || length(meta$variables) == 0) {
      return(paste0("Dataset '", name, "': No variables available"))
    }
    
    # Format variables info
    var_info <- sapply(meta$variables, function(var) {
      var_text <- paste0("  - ", var$name)
      if (!is.null(var$label) && !is.na(var$label) && nzchar(var$label)) {
        var_text <- paste0(var_text, " (", var$label, ")")
      }
      var_text <- paste0(var_text, ": ", paste(var$type, collapse = ", "))
      
      # Add unique values or levels if available
      if (!is.null(var$unique_values) && length(var$unique_values) > 0) {
        unique_vals <- utils::head(var$unique_values, 10)  # Limit to first 10
        var_text <- paste0(var_text, " [values: ", paste(unique_vals, collapse = ", "))
        if (length(var$unique_values) > 10) {
          var_text <- paste0(var_text, ", ...]")
        } else {
          var_text <- paste0(var_text, "]")
        }
      }
      
      return(var_text)
    })
    
    dataset_desc <- if (!is.null(meta$description) && nzchar(meta$description)) {
      paste0("Dataset '", name, "' (", meta$description, "):")
    } else {
      paste0("Dataset '", name, "':")
    }
    
    return(paste0(dataset_desc, "\n", paste(var_info, collapse = "\n")))
  }, metadata_list, dataset_names, SIMPLIFY = FALSE, USE.NAMES = FALSE)
  
  return(paste(formatted_parts, collapse = "\n\n"))
}
