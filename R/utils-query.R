query_llm_and_run_with_retries <- function(datasets, user_prompt, system_prompt, max_retries = 5) {
  local_env <- environment()
  dataset_env <- list2env(datasets, parent = .GlobalEnv)
  error_message <- NULL

  for (i in 1:max_retries) {
    rlang::try_fetch({
      response <- query_llm(user_prompt, system_prompt, error_message)
      value <- eval(parse(text = response$code), envir = dataset_env)
      # plots might not fail at definition time but only when printing.
      # We trigger the failure early with ggplotGrob()
      if (ggplot2::is.ggplot(value)) {
        suppressMessages(ggplot2::ggplotGrob(value))
      }
      # If we get here, code executed successfully
      message("Code execution successful")
      return(list(value = value, code = response$code, explanation = response$explanation))
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

query_llm <- function(user_prompt, system_prompt, error = NULL,
                      verbose = blockr_option("verbose", TRUE)) {

  # user message ---------------------------------------------------------------
  if (!is.null(error)) {
    user_prompt <-
      paste(
        user_prompt,
        "\nIn another conversation your solution resulted in this error:",
        shQuote(error, type = "cmd"),
        "Be careful to provide a solution that doesn't reproduce this problem",
        sep = "\n"
      )
    }

  if (verbose) {
    cat(
      "\n-------------------- user prompt --------------------\n",
      user_prompt,
      "\n",
      sep = ""
    )
  }

  # response -------------------------------------------------------------------
  chat <- chat_dispatch(system_prompt)
  response <- chat$extract_data(user_prompt, type = type_response())

  if (verbose) {
    cat(
      "\n-------------------- response explanation -----------\n",
      response$explanation,
      "\n",
      "\n-------------------- response code ------------------\n",
      response$code,
      "\n",
      sep = ""
    )
  }

  response
}
