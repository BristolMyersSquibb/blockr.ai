# LLM Utilities for AI Control Block

#' Create chat client
#' @param model Model name (default from blockr_option("ai_model"))
#' @return An ellmer chat client
#' @noRd
llm_client <- function(model = blockr.core::blockr_option("ai_model", "gpt-4o-mini")) {
  ellmer::chat_openai(model = model)
}


#' Check if LLM response indicates completion
#' @param response Character string from LLM
#' @return Logical
#' @noRd
is_done_response <- function(response) {
  grepl("^\\s*DONE\\s*$", response, ignore.case = TRUE) ||
    (grepl("\\bDONE\\b", response) && !grepl("```", response))
}


#' Extract JSON from markdown code blocks or raw text
#' @param text Character string containing markdown or raw JSON
#' @return Character string with JSON, or NULL if not found
#' @noRd
extract_json <- function(text) {
  # Try code block first
  pattern <- "```(?:json)?\\s*\\n([\\s\\S]*?)\\n```"
  matches <- regmatches(text, gregexpr(pattern, text, perl = TRUE))[[1]]

  if (length(matches) > 0) {
    last_block <- matches[length(matches)]
    json <- sub("```(?:json)?\\s*\\n", "", last_block, perl = TRUE)
    json <- sub("\\n```$", "", json)
    return(trimws(json))
  }

  # Try raw JSON (starts with {)
  if (grepl("^\\s*\\{", text)) {
    return(trimws(text))
  }

  NULL
}


#' Create input data preview for LLM prompt
#'
#' Handles all input types: NULL, single data.frame, named list (x, y),
#' or variadic list of data.frames.
#'
#' @param input The raw result from dat() - can be NULL, data.frame, or list
#' @return Character string with formatted preview section, or "" if no data
#' @noRd
data_preview <- function(input) {
  if (is.null(input)) {
    return("")
  }

  # Empty list = no input data (source block)
  if (is.list(input) && length(input) == 0) {
    return("")
  }

  body <- if (is.data.frame(input)) {
    format_df_preview(input)
  } else if (is.list(input) && length(input) > 0) {
    previews <- vapply(seq_along(input), function(i) {
      name <- names(input)[i] %||% paste0("Input ", i)
      item <- input[[i]]
      if (is.data.frame(item)) {
        paste0("## ", name, "\n\n", format_df_preview(item))
      } else {
        paste0("## ", name, "\n\n", "Non-dataframe object: ", class(item)[1])
      }
    }, character(1))
    paste(previews, collapse = "\n\n")
  } else {
    paste0("Unknown input type: ", class(input)[1])
  }

  paste0("# Input Data\n\n", body, "\n\n")
}


#' Format a single data.frame for preview
#' @noRd
format_df_preview <- function(df) {
  col_info <- vapply(df, function(x) {
    paste0(class(x)[1])
  }, character(1))
  cols <- paste0(names(df), " (", col_info, ")", collapse = ", ")

  paste0(nrow(df), " rows x ", ncol(df), " cols: ", cols)
}


#' Build system prompt for block argument discovery
#' @param var_names Names of controllable variables
#' @param block Block object for context
#' @return Character string with system prompt
#' @noRd
build_system_prompt <- function(var_names, block) {
  block_name <- class(block)[1]

  # Get registry info for richer context
  reg_info <- get_block_registry_info(block_name)

  block_context <- if (!is.null(reg_info$description)) {
    paste0(
      "You are configuring a ", reg_info$name, " (", block_name, ").\n",
      reg_info$description, "\n\n"
    )
  } else {
    paste0("You are configuring a ", block_name, ".\n\n")
  }

  example <- get_block_example(block_name)
  example_text <- if (!is.null(example)) {
    paste0("Example:\n```json\n", example, "\n```\n\n")
  } else {
    paste0("Return JSON like: {\"", var_names[1], "\": <value>}\n\n")
  }

  paste0(
    block_context,
    "Return JSON with parameter values.\n\n",
    "Parameters: ", paste(var_names, collapse = ", "), "\n\n",
    example_text,
    "After seeing the result, respond with just DONE if correct, or provide fixed JSON."
  )
}


#' Get registry info for a block type
#' @param block_name Name of the block class
#' @return List with name, description, category (or NULLs if not found)
#' @noRd
get_block_registry_info <- function(block_name) {
  reg <- tryCatch(
    blockr.core:::block_registry,
    error = function(e) NULL
  )

  if (is.null(reg)) {
    return(list(name = NULL, description = NULL, category = NULL))
  }

  entry <- tryCatch(
    get(block_name, envir = reg, inherits = FALSE),
    error = function(e) NULL
  )

  if (is.null(entry)) {
    return(list(name = NULL, description = NULL, category = NULL))
  }

  list(
    name = attr(entry, "name"),
    description = attr(entry, "description"),
    category = attr(entry, "category")
  )
}


#' Get example JSON for a block type
#' @param block_name Name of the block
#' @return JSON string example or NULL
#' @noRd
get_block_example <- function(block_name) {
  examples <- list(
    filter_block = '{"conditions": [{"column": "Species", "values": ["setosa"]}]}',
    summarize_block = '{"summaries": {"mean_val": {"func": "mean", "col": "column_name"}}, "by": ["group_col"]}',
    summarize_expr_block = '{"exprs": {"mean_val": "mean(column_name)"}, "by": ["group_col"]}',
    mutate_expr_block = '{"exprs": {"new_col": "old_col * 2"}}',
    select_block = '{"columns": ["col1", "col2"], "exclude": false}',
    arrange_block = '{"columns": ["col1", "col2"]}',
    dataset_block = '{"dataset": "mtcars", "package": "datasets"}'
  )
  examples[[block_name]]
}
