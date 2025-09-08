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

  log_wrap(
    "\n----------------- user prompt -----------------\n\n",
    user_prompt,
    "\n",
    "\n---------------- system prompt ----------------\n\n",
    system_prompt,
    "\n",
    level = "debug"
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
