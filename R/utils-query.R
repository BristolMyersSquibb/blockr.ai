query_llm_with_tools <- function(user_prompt, system_prompt, tools,
                                 progress = FALSE) {

  if (isTRUE(progress)) {
    shinyjs::show(id = "progress_container", anim = TRUE)
    on.exit(
      shinyjs::hide(id = "progress_container", anim = TRUE)
    )
  }

  stopifnot(
    is.list(tools), all(lgl_ply(tools, is_llm_tool))
  )

  chat <- chat_dispatch(system_prompt)

  for (tool in lapply(tools, get_tool)) {
    chat$register_tool(tool)
  }

  system_prompt <- paste0(
    system_prompt,
    "\n\n",
    paste0(filter(has_length, lapply(tools, get_prompt)), collapse = "\n")
  )

  log_wrap(
    "\n----------------- user prompt -----------------\n\n",
    user_prompt,
    "\n",
    "\n---------------- system prompt ----------------\n\n",
    system_prompt,
    "\n",
    level = "debug"
  )

  response <- try(
    chat$chat_structured(
      chat$chat(user_prompt),
      type = type_response()
    ),
    silent = TRUE
  )

  if (inherits(response, "try-error")) {

    msg <- extract_try_error(response)

    log_error("Error encountered during chat: ", msg)

    return(
      list(error = msg)
    )
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

default_chat <- function(...) {
  ellmer::chat_openai(..., model = "gpt-4o")
}

chat_dispatch <- function(...) {

  fun <- blockr_option(
    "chat_function",
    default_chat
  )

  fun(...)
}

type_response <- function() {
  type_object(
    explanation = type_string("Explanation of the analysis approach"),
    code = type_string("R code to perform the analysis")
  )
}

setup_chat_task <- function(session) {
  ExtendedTask$new(
    function(client, ui_id, user_input) {
      res <- client$chat(user_input)
      shinychat::chat_append(ui_id, res, session = session)
      client$chat_structured(res, type = type_response())
    }
  )
}
