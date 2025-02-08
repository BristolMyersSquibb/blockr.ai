# Define response types
type_response <- function() {
  type_object(
    explanation = type_string("Explanation of the analysis approach"),
    code = type_string("R code to perform the analysis")
  )
}

return_result_if_success <- function(result, code) {
  warning("Expression status: ", result$success, "\nFinal code:\n", code)
  if (isTRUE(result$success)) {
    result$result  # Return the cached result
  } else {
    data.frame()  # Return empty dataframe on error
  }
}

fixed_ace_editor <- function(code) {
  code_styled <- styler::style_text(code)
  n_lines <- length(code_styled)
  # FIXME: is there a better or more robust way to set a height to fit input?
  height <- sprintf("%spx", n_lines * 12 * 1.4)
  shinyAce::aceEditor(
    "codeEditor",
    mode = "r",
    theme = "chrome",
    value = code_styled,
    readOnly = TRUE,
    height = height,
    showPrintMargin = FALSE
  )
}
