query_llm_with_retry <- function(datasets, user_prompt, system_prompt,
                                 max_retries = 5, progress = FALSE) {

  if (isTRUE(progress)) {
    shinyjs::show(id = "progress_container", anim = TRUE)
    on.exit(
      shinyjs::hide(id = "progress_container", anim = TRUE)
    )
  }

  error_msg <- NULL
  curr_try <- 1L

  while (curr_try <= max_retries) {

    res <- try_query_llm(user_prompt, system_prompt, error_msg)

    if (inherits(res, "try-error")) {

      if (is.null(attr(res, "condition"))) {
        msg <- unclass(res)
      } else {
        msg <- conditionMessage(attr(res, "condition"))
      }

      log_error("Error encountered querying: ", msg)

      return(list(error = msg))
    }

    val <- try_eval_code(res$code, datasets)

    if (inherits(val, "try-error")) {

      log_warn("Code execution attempt ", curr_try, " failed:\nCode:\n",
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

  log_warn("Maximum retries reached. Last code:\n", res$code)

  list(
    error = "Maximum retries reached",
    code = res$code,
    explanation = res$explanation
  )
}

try_query_llm <- function(...) {
  try(query_llm(...), silent = TRUE)
}

query_llm <- function(user_prompt, system_prompt, error = NULL) {

  # user message ---------------------------------------------------------------
  if (!is.null(error)) {
    user_prompt <- paste(
      user_prompt,
      "\nIn another conversation your solution resulted in this error:",
      shQuote(error, type = "cmd"),
      "Be careful to provide a solution that doesn't reproduce this problem",
      sep = "\n"
    )
  }

  log_wrap(
    "\n----------------- user prompt -----------------\n\n",
    user_prompt,
    "\n",
    "\n---------------- system prompt ----------------\n\n",
    system_prompt,
    "\n",
    level = "debug"
  )

  chat <- chat_dispatch(system_prompt)
  response <- chat$chat_structured(user_prompt, type = type_response())

  response$code <- style_code(response$code)

  log_wrap(
    "\n------------- response explanation ------------\n\n",
    response$explanation,
    "\n",
    level = "debug"
  )

  log_asis(
    "\n---------------- response code ----------------\n\n",
    response$code,
    "\n\n",
    level = "debug"
  )

  response
}

type_response <- function() {
  type_object(
    explanation = type_string("Explanation of the analysis approach"),
    code = type_string("R code to perform the analysis")
  )
}

chat_dispatch <- function(system_prompt, ...,
                          model = blockr_option("chat_model", "gpt-4o"),
                          vendor = blockr_option("chat_vendor", "openai")) {

  chat <- switch(
    vendor,
    bedrock = ellmer::chat_bedrock,
    claude = ellmer::chat_claude,
    gemini = ellmer::chat_gemini,
    github = ellmer::chat_github,
    groq = ellmer::chat_groq,
    ollama = ellmer::chat_ollama,
    openai = ellmer::chat_openai,
    perplexity = ellmer::chat_perplexity,
    stop("Unknown LLM vendor ", vendor, ".")
  )

  chat(system_prompt, model = model, ...)
}
