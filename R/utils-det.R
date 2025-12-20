# Deterministic Loop Utilities
#
# Helper functions for the deterministic LLM block implementation.


#' Check if response indicates DONE
#'
#' @param response Character string from LLM
#' @return Logical
#' @noRd
is_done_response <- function(response) {
  # Match "DONE" as standalone or in response without code blocks

grepl("^\\s*DONE\\s*$", response, ignore.case = TRUE) ||
    (grepl("\\bDONE\\b", response) && !grepl("```", response))
}


#' Extract R code from markdown blocks
#'
#' @param text Character string containing markdown
#' @return Character string with code, or NULL if not found
#' @noRd
extract_code_from_markdown <- function(text) {
  # Match ```r ... ``` or ```R ... ``` blocks
  pattern <- "```[rR]\\s*\\n([\\s\\S]*?)\\n```"
  matches <- regmatches(text, gregexpr(pattern, text, perl = TRUE))[[1]]

  if (length(matches) == 0) {
    # Try without language specifier
    pattern <- "```\\s*\\n([\\s\\S]*?)\\n```"
    matches <- regmatches(text, gregexpr(pattern, text, perl = TRUE))[[1]]
  }

  if (length(matches) == 0) {
    return(NULL)
  }

  # Extract content from last code block
  last_block <- matches[length(matches)]
  code <- sub("```[rR]?\\s*\\n", "", last_block)
  code <- sub("\\n```$", "", code)
  trimws(code)
}


#' Create data preview for initial prompt
#'
#' @param datasets Named list of data.frames
#' @return Character string with formatted preview
#' @noRd
create_data_preview <- function(datasets) {
  if (length(datasets) == 0) {
    return("No datasets available.")
  }

  paste(
    sapply(names(datasets), function(nm) {
      d <- datasets[[nm]]
      preview_lines <- utils::capture.output(print(utils::head(d, 5)))
      paste0(
        "## Dataset: ", nm, "\n",
        "Dimensions: ", nrow(d), " rows x ", ncol(d), " cols\n",
        "Columns: ", paste(names(d), collapse = ", "), "\n\n",
        "```\n",
        paste(preview_lines, collapse = "\n"),
        "\n```"
      )
    }),
    collapse = "\n\n"
  )
}
