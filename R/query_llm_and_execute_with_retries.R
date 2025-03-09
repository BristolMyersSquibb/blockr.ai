query_llm_and_execute_with_retries <- function(datasets, question, metadata, plot = FALSE, max_retries = 5) {
  local_env <- environment()
  dataset_env <- list2env(datasets, parent = .GlobalEnv)
  error_message <- NULL

  for (i in 1:max_retries) {
    rlang::try_fetch({
      response <- query_llm(question, metadata, names(datasets), error_message, plot = plot)
      result <- eval(parse(text = response$code), envir = dataset_env)
      # plots might not fail at definition time but only when printing.
      # We trigger the failure early with ggplotGrob()
      if (ggplot2::is.ggplot(result)) {
        suppressMessages(ggplot2::ggplotGrob(plt))
      }
      # If we get here, code executed successfully
      message("Code execution successful:\n", response$code)
      return(list(result = result, code = response$code, explanation = response$explanation))
    }, error = function(e) {
      local_env$error_message <- e$message
      warning(
        "Code execution attempt ",
        i,
        " failed:\n",
        "Code:\n",
        response$code,
        "\nError: ",
        e$message
      )
    })
  }
  # If we get here, max retries reached
  warning("Maximum retries reached. Last code:\n", response$code)
  return(list(error = "Maximum retries reached"))
}

rename_datasets <- function(datasets) {
  numeric_lgl <- grepl("^[0-9]+$", names(datasets))
  names(datasets)[numeric_lgl] <- paste0("dataset_", names(datasets)[numeric_lgl])
  datasets
}

build_code_prefix <- function(datasets) {
  numeric_lgl <- grepl("^[0-9]+$", names(datasets))
  numeric_names <- names(datasets)[numeric_lgl]
  code <- sprintf("dataset_%s <- `%s`", numeric_names, numeric_names)
  paste(code, collapse = "\n")
}
