query_llm_and_run_with_retries <- function(datasets, user_prompt, system_prompt,
                                           max_retries = 5) {

  error_msg <- NULL
  curr_try <- 1L

  while (curr_try <= max_retries) {

    res <- query_llm(user_prompt, system_prompt, error_msg)
    val <- try_eval_code(res$code, datasets)

    if (inherits(val, "try-error")) {

      warning("Code execution attempt ", curr_try, " failed:\nCode:\n",
              res$code, "\nError: ", val)

      curr_try <- curr_try + 1L
      error_msg <- unclass(val)

      next
    }

    log_debug("Code execution successful")

    return(
      list(value = val, code = res$code, explanation = res$explanation)
    )
  }

  warning("Maximum retries reached. Last code:\n", res$code)

  list(error = "Maximum retries reached")
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
