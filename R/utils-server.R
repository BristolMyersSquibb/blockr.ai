setup_chat_observer <- function(rv_msgs, client, session) {

  observeEvent(
    TRUE,
    {
      msg <- split_messages(rv_msgs())

      if (not_null(msg[["current"]])) {
        shinychat::update_chat_user_input(
          "chat",
          value = msg[["current"]][["content"]],
          session = session
        )
      }

      hist <- msg[["history"]]

      if (not_null(msg[["history"]])) {
        client$set_turns(
          map(
            ellmer::Turn,
            lst_xtr(hist, "role"),
            lst_xtr(hist, "content")
          )
        )
      }
    },
    once = TRUE
  )
}

chat_input_observer <- function(x, client, task, input, r_datasets, rv_msgs,
                                rv_cond) {

  observeEvent(input$chat_user_input, {

    dat <- r_datasets()

    cur <- rv_msgs()
    new <- list(
      list(role = "user", content = input$chat_user_input)
    )

    if (last(cur)[["role"]] == "user") {
      rv_msgs(c(cur[-length(cur)], new))
    } else {
      rv_msgs(c(cur, new))
    }

    if (length(dat) == 0 || any(lengths(dat) == 0)) {

      if (length(dat)) {
        msg <- paste(
          "Incomplete data:",
          paste0(names(dat), " (", lengths(dat), ")", collapse = ", "),
          "."
        )
      } else {
        msg <- "No data available."
      }

      log_warn(msg)
      rv_cond$warning <- msg

    } else {

      rv_cond$warning <- character()

      tools <- llm_tools(x, dat)

      query_llm_with_tools(
        client = client,
        task = task,
        user_prompt = input$chat_user_input,
        system_prompt = system_prompt(x, dat, tools),
        tools = tools
      )
    }
  })
}
