#' Extract R code blocks from text using stringr
#' @param text A character string containing R code blocks between r code tags
#' @return A character vector containing the extracted code blocks
#' @importFrom stringr str_match_all str_trim str_replace_all regex
#' @export
extract_r_code <- function(text) {
  # Clean up any R/r variations
  text <- gsub("`R", "`r", text)

  # Try different patterns for code blocks
  patterns <- c(
    "```\\{?r\\}?\\s*(.*?)```",  # Standard R markdown
    "```r\\s*(.*?)```",          # Simple R code block
    "`r\\s*(.*?)`"               # Inline R code
  )

  for (pattern in patterns) {
    matches <- stringr::str_match_all(
      string = text,
      pattern = stringr::regex(pattern, dotall = TRUE)
    )[[1]]

    if (length(matches) > 0 && nrow(matches) > 0) {
      # Extract and clean the captured code
      code <- paste(matches[, 2], collapse = "\n")
      code <- stringr::str_trim(code)
      if (nchar(code) > 0) return(code)
    }
  }

  # If no matches found or all empty, return empty character vector
  character()
}
