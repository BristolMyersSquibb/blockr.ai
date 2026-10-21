# Text helpers for the chat panel.

#' Truncate a summary string with an ellipsis.
#' @noRd
truncate_summary <- function(x, n = 80L) {
  if (is.null(x)) return("")
  x <- gsub("\\s+", " ", trimws(as.character(x)))
  if (length(x) != 1L) x <- paste(x, collapse = " ")
  if (nchar(x) > n) paste0(substr(x, 1L, n - 1L), "\u2026") else x
}
