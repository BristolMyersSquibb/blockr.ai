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

return_result_if_success <- function(result, code) {
  warning("Expression status: ", result$success, "\nFinal code:\n", code)
  if (isTRUE(result$success)) {
    result$result  # Return the cached result
  } else {
    data.frame()  # Return empty dataframe on error
  }
}
