#' Deterministic LLM block server
#'
#' Server implementation for deterministic LLM blocks.
#' Uses system-controlled flow instead of tool-based communication.
#'
#' @param x An LLM block proxy object
#' @return A Shiny module server function
#'
#' @keywords internal
#' @export
llm_block_server_det <- function(x) {
  UseMethod("llm_block_server_det", x)
}

#' @export
llm_block_server_det.default <- function(x) {

  function(id, data = NULL, ...args = list()) {
    moduleServer(
      id,
      function(input, output, session) {

        # --- Async task for LLM communication ---
        task <- ExtendedTask$new(
          function(client, user_input) {
            stream <- client$stream_async(user_input, stream = "content")
            promises::then(
              promises::promise_resolve(stream),
              onFulfilled = function(stream) {
                shinychat::chat_append("chat", stream, session = session)
              }
            )
          }
        )

        task_ready <- reactive(
          switch(task$status(), error = FALSE, success = TRUE, NULL)
        )

        # --- LLM client ---
        client <- reactiveVal()

        setup_client_observer(client, session)

        # --- Dark mode for code editor ---
        observeEvent(
          get_board_option_or_default("dark_mode"),
          shinyAce::updateAceEditor(
            session,
            "code_editor",
            theme = switch(
              get_board_option_or_default("dark_mode"),
              light = "katzenmilch",
              dark = "dracula"
            )
          )
        )

        # --- Datasets ---
        r_datasets <- reactive(
          c(
            if (is.reactive(data) && !is.null(data())) list(data = data()),
            if (is.reactivevalues(...args)) reactiveValuesToList(...args)
          )
        )

        # --- Reactive values ---
        # Initialize without value to avoid triggering observer with empty code
        rv_code <- reactiveVal()
        rv_msgs <- reactiveVal(x[["messages"]])
        rv_iteration <- reactiveVal(0L)
        rv_status <- reactiveVal("idle")  # idle, running, done, error

        rv_cond <- reactiveValues(
          error = character(),
          warning = character(),
          message = character()
        )

        # --- Initialize chat history ---
        setup_chat_observer(rv_msgs, client, session)

        # --- Handle user input: START deterministic loop ---
        observeEvent(input$chat_user_input, {
          req(input$chat_user_input)

          dat <- r_datasets()

          # Check for data availability
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
            return()
          }

          rv_cond$warning <- character()

          user_prompt <- input$chat_user_input

          # Build first message with data preview (deterministic approach)
          data_preview <- create_data_preview(dat)
          first_msg <- paste0(
            "# Data Available\n\n",
            data_preview,
            "\n\n# Task\n\n",
            user_prompt,
            "\n\nWrite R code to complete this task. ",
            "Wrap your code in ```r ... ``` blocks."
          )

          # Update messages
          cur <- rv_msgs()
          new <- list(list(role = "user", content = first_msg))

          if (length(cur) && last(cur)[["role"]] == "user") {
            rv_msgs(c(cur[-length(cur)], new))
          } else {
            rv_msgs(c(cur, new))
          }

          # Set system prompt (no tools)
          sys_prompt <- system_prompt_det(x, dat)
          client()$set_system_prompt(sys_prompt)

          # Reset state
          rv_iteration(1L)
          rv_status("running")

          log_debug(
            "\n----------------- user prompt -----------------\n\n",
            first_msg,
            "\n"
          )

          # Query LLM (no tools)
          task$invoke(client(), first_msg)
        })

        # --- Handle LLM response: CONTINUE deterministic loop ---
        observeEvent(task_ready(), {
          req(task_ready())
          req(rv_status() == "running")

          # Get response
          response <- tryCatch(
            client()$last_turn()@text,
            error = function(e) {
              rv_cond$error <- conditionMessage(e)
              rv_status("error")
              return(NULL)
            }
          )

          if (is.null(response)) return()

          log_debug(
            "\n---------------- LLM response ----------------\n\n",
            substr(response, 1, 500),
            if (nchar(response) > 500) "..." else "",
            "\n"
          )

          # Update messages with assistant response
          rv_msgs(c(rv_msgs(), list(list(role = "assistant", content = response))))

          # Check for DONE
          if (is_done_response(response)) {
            log_debug("LLM said DONE\n")
            rv_status("done")
            return()
          }

          # Extract code from markdown
          code <- extract_code_from_markdown(response)

          if (is.null(code) || nchar(trimws(code)) == 0) {
            # No code found - ask for code
            next_msg <- "I couldn't find R code in your response. Please provide code wrapped in ```r ... ``` blocks."
            rv_msgs(c(rv_msgs(), list(list(role = "user", content = next_msg))))

            rv_iteration(rv_iteration() + 1L)
            if (rv_iteration() > 10L) {
              rv_cond$error <- "Maximum iterations exceeded without valid code."
              rv_status("error")
              return()
            }

            shinychat::chat_append_message(
              "chat",
              list(role = "user", content = next_msg),
              session = session
            )
            task$invoke(client(), next_msg)
            return()
          }

          log_debug("Code extracted (", nchar(code), " chars)\n")

          # Run code
          dat <- r_datasets()
          result <- try_eval_code(x, code, dat)

          if (inherits(result, "try-error")) {
            # Error - show to LLM
            error_text <- extract_try_error(result)
            log_debug("Code error: ", substr(error_text, 1, 100), "\n")

            error_msg <- paste0(
              "Your code produced an error:\n\n",
              "```\n", error_text, "\n```\n\n",
              "Please fix the code and try again."
            )
            rv_msgs(c(rv_msgs(), list(list(role = "user", content = error_msg))))

            rv_iteration(rv_iteration() + 1L)
            if (rv_iteration() > 10L) {
              rv_cond$error <- "Maximum iterations exceeded."
              rv_status("error")
              return()
            }

            shinychat::chat_append_message(
              "chat",
              list(role = "user", content = error_msg),
              session = session
            )
            task$invoke(client(), error_msg)

          } else if (is.data.frame(result)) {
            # Success - capture code and ask for confirmation
            rv_code(style_code(code))
            rv_cond$error <- character()

            result_preview <- paste(
              utils::capture.output(print(result)),
              collapse = "\n"
            )

            log_debug("Success: data.frame with ", nrow(result), " rows\n")

            confirm_msg <- paste0(
              "Your code executed successfully. Here is the result:\n\n",
              "```\n", result_preview, "\n```\n\n",
              "Does this look correct? If yes, respond with just: DONE\n",
              "If not, provide corrected code in ```r ... ``` blocks."
            )
            rv_msgs(c(rv_msgs(), list(list(role = "user", content = confirm_msg))))

            rv_iteration(rv_iteration() + 1L)
            if (rv_iteration() > 10L) {
              # Accept the result even if LLM doesn't say DONE
              rv_status("done")
              return()
            }

            shinychat::chat_append_message(
              "chat",
              list(role = "user", content = confirm_msg),
              session = session
            )
            task$invoke(client(), confirm_msg)

          } else {
            # Not a data.frame
            log_debug("Result is not a data.frame: ", class(result)[1], "\n")

            type_msg <- paste0(
              "Your code ran but did not produce a data.frame. ",
              "The result was of class: ", class(result)[1], "\n\n",
              "Please fix the code to produce a data.frame as output."
            )
            rv_msgs(c(rv_msgs(), list(list(role = "user", content = type_msg))))

            rv_iteration(rv_iteration() + 1L)
            if (rv_iteration() > 10L) {
              rv_cond$error <- "Maximum iterations exceeded."
              rv_status("error")
              return()
            }

            shinychat::chat_append_message(
              "chat",
              list(role = "user", content = type_msg),
              session = session
            )
            task$invoke(client(), type_msg)
          }
        })

        # --- Sync code to editor ---
        observeEvent(
          rv_code(),
          {
            code_val <- rv_code()
            req(length(code_val) > 0 && nchar(code_val) > 0)
            shinyAce::updateAceEditor(
              session,
              "code_editor",
              value = code_val
            )
          }
        )

        # --- Handle manual code edits ---
        observeEvent(
          input$code_editor,
          {
            req(input$code_editor)
            res <- try_eval_code(x, input$code_editor, r_datasets())
            if (inherits(res, "try-error")) {
              rv_cond$error <- paste0(
                "Encountered an error evaluating code: ", extract_try_error(res)
              )
            } else {
              rv_code(style_code(input$code_editor))
              rv_cond$error <- character()
            }
          }
        )

        # --- Return block output ---
        list(
          expr = reactive(code_expr(rv_code())),
          state = list(
            messages = rv_msgs,
            code = rv_code
          ),
          cond = rv_cond
        )
      }
    )
  }
}


#' System prompt for deterministic blocks (no tools)
#'
#' @param x Block proxy
#' @param datasets Named list of datasets
#' @return Character string with system prompt
#' @keywords internal
system_prompt_det <- function(x, datasets) {
  UseMethod("system_prompt_det")
}

#' @export
system_prompt_det.default <- function(x, datasets) {
  paste0(
    "You are an R code assistant. You write dplyr code to transform data.\n\n",

    "IMPORTANT RULES:\n",
    "1. Always prefix dplyr functions: dplyr::filter(), dplyr::mutate(), etc.\n",
    "2. Always prefix tidyr functions: tidyr::pivot_wider(), etc.\n",
    "3. Use the native pipe |> (not %>%)\n",
    "4. Your code must produce a data.frame\n",
    "5. Wrap your R code in ```r ... ``` markdown blocks\n\n",

    "When you see the result of your code:\n",
    "- If it's correct, respond with just: DONE\n",
    "- If it needs fixing, provide corrected code in ```r ... ``` blocks\n"
  )
}


#' UI for deterministic LLM blocks
#'
#' @param x Block proxy
#' @return UI function
#' @keywords internal
#' @export
llm_block_ui_det <- function(x) {
  UseMethod("llm_block_ui_det", x)
}

#' @export
llm_block_ui_det.default <- function(x) {

  function(id) {

    msg <- split_messages(x[["messages"]])

    chat <- shinychat::chat_ui(
      NS(id, "chat"),
      width = "100%",
      style = "max-height: 400px; overflow-y: auto;",
      messages = msg[["history"]]
    )

    code <- shinyAce::aceEditor(
      NS(id, "code_editor"),
      mode = "r",
      value = style_code(x[["code"]]),
      showPrintMargin = FALSE,
      height = "200px"
    )

    bslib::accordion(
      multiple = TRUE,
      id = NS(id, "accordion"),
      bslib::accordion_panel(title = "Chat", chat),
      bslib::accordion_panel(title = "Code output", code)
    )
  }
}
