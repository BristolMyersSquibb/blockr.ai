query_llm_with_tools <- function(client, task, user_prompt, system_prompt,
                                 tools) {

  system_prompt <- paste0(
    system_prompt,
    "\n\n",
    paste0(
      filter(has_length, lapply(tools, get_prompt)),
      collapse = "\n"
    )
  )

  log_debug(
    "\n----------------- user prompt -----------------\n\n",
    user_prompt,
    "\n"
  )

  log_trace(
    "\n---------------- system prompt ----------------\n\n",
    system_prompt,
    "\n"
  )

  log_debug(
    "\n-----------------------------------------------\n\n"
  )

  client$set_system_prompt(system_prompt)
  client$set_tools(lapply(tools, get_tool))

  task$invoke(client, "chat", user_prompt)

  invisible()
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

      stream <- client$stream_async(
        user_input,
        stream = "content"
      )

      promises::promise_resolve(stream) |>
        promises::then(
          function(stream) {
            shinychat::chat_append(ui_id, stream)
          }
        )
    }
  )
}

last_turn_structured <- function(client) {
  client$chat_structured(
    client$last_turn()@text,
    type = type_response()
  )
}

eval_tool_code <- function(client) {

  tool <- client$get_tools()[["eval_tool"]]
  code <- get0("current_code", envir = environment(tool), inherits = FALSE)

  if (is.null(code)) {
    stop(
      "Code not validated successfully using the `eval_tool`. Please try ",
      "again."
    )
  }

  list(code = code, explanation = client$last_turn()@text)
}

extract_result <- function(client) {

  extractor <- blockr_option(
    "result_callback",
    if ("eval_tool" %in% names(client$get_tools())) {
      eval_tool_code
    } else {
      last_turn_structured
    }
  )

  res <- extractor(client)

  stopifnot(
    is.list(res),
    setequal(names(res), c("code", "explanation")),
    is.character(res[["code"]]),
    is.character(res[["explanation"]])
  )

  res[["code"]] <- style_code(res[["code"]])

  res
}
