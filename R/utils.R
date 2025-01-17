#' @noRd
#' @param x list of datasets
name_unnamed_datasets <- function(x) {
  names(x) <- if_else(
    names2(x) == "",
    paste0("data", seq_along(x)),
    names2(x)
  )
  x
}

# Define response types
type_response <- function() {
  type_object(
    explanation = type_string("Explanation of the analysis approach"),
    code = type_string("R code to perform the analysis")
  )
}

format_generated_code <- function(code) {
  if (!is_string(code)) abort("`code` must be a string")
  if (nchar(code) > 0) {
    formatR::tidy_source(text = code, output = FALSE)$text.tidy
  } else {
    "No code generated yet"
  }
}
