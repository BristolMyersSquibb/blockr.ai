query_llm_with_retry <- function(datasets, user_prompt, system_prompt,
                                 block_proxy = NULL, image_content = NULL, max_retries = 5, progress = FALSE) {

  if (isTRUE(progress)) {
    shinyjs::show(id = "progress_container", anim = TRUE)
    on.exit(
      shinyjs::hide(id = "progress_container", anim = TRUE)
    )
  }

  error_msg <- NULL
  curr_try <- 1L

  while (curr_try <= max_retries) {

    res <- try_query_llm(user_prompt, system_prompt, error_msg, image_content)

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

    # Validate result type if block_proxy provided
    if (!is.null(block_proxy)) {
      validation <- validate_block_result(val, block_proxy)
      if (!validation$valid) {
        log_warn("Type validation attempt ", curr_try, " failed:\nCode:\n",
                 res$code, "\nValidation error: ", validation$message)

        error_msg <- validation$message
        curr_try <- curr_try + 1L
        next  # Retry with validation feedback
      }
    }

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

query_llm <- function(user_prompt, system_prompt, error = NULL, image_content = NULL) {

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

  # Build message content - combine text and image if available
  if (!is.null(image_content)) {
    # For multimodal content, pass both image and text
    response <- chat$chat_structured(image_content, user_prompt, type = type_response())
    log_debug("Multimodal query sent with image and text prompt")
  } else {
    # Text-only query
    response <- chat$chat_structured(user_prompt, type = type_response())
  }

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

default_chat <- function(system_prompt) {
  ellmer::chat_openai(system_prompt, model = "gpt-4o")
}

chat_dispatch <- function(...) {

  fun <- blockr_option(
    "chat_function",
    default_chat
  )

  fun(...)
}
