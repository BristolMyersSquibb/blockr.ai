# AI Control Block Plugin
#
# Provides AI-powered control for blocks with external_ctrl enabled.

#' AI-powered control block plugin
#'
#' Replaces the default ctrl_block with an AI chat interface. Users can
#' describe what they want in natural language and the LLM will configure
#' the block parameters.
#'
#' @return A ctrl_block plugin object
#'
#' @examples
#' \dontrun{
#' serve(
#'   new_board(new_dataset_block("iris")),
#'   plugins = custom_plugins(ai_ctrl_block())
#' )
#' }
#'
#' @export
ai_ctrl_block <- function() {
  blockr.core::ctrl_block(
    server = ai_ctrl_server,
    ui = ai_ctrl_ui
  )
}


#' @param id Namespace ID
#' @param x Block object
#' @rdname ai_ctrl_block
#' @export
ai_ctrl_ui <- function(id, x) {
  # No UI for blocks without external_ctrl
  if (length(blockr.core:::block_external_ctrl_vars(x)) == 0) {
    return(tagList())
  }

  ns <- NS(id)

  chat_id <- ns("chat")

  tagList(
    css_ai_ctrl(),
    shinychat::chat_ui(
      chat_id,
      placeholder = "Describe what you want...",
      width = "100%",
      height = "auto",
      icon_assistant = bsicons::bs_icon("stars")
    ),
    tags$div(
      style = "text-align: right; padding: 4px 0;",
      tags$a(
        href = "#",
        class = "blockr-report-conversation",
        onclick = sprintf("blockrReportConversation('%s'); return false;", chat_id),
        "Report"
      )
    )
  )
}

css_ai_ctrl <- function() {
  htmltools::htmlDependency(
    "blockr-ai-ctrl",
    pkg_version(),
    src = c(href = ""),
    head = paste0("<style>",
      ".blockr-ctrl-body shiny-chat-container {
        --_chat-container-padding: 0;
      }
      .blockr-ctrl-body shiny-chat-input textarea {
        border-radius: 6px !important;
        min-height: 38px !important;
        scrollbar-width: none;
        -ms-overflow-style: none;
      }
      .blockr-ctrl-body shiny-chat-input textarea::-webkit-scrollbar {
        display: none;
      }
      .blockr-ctrl-body shiny-chat-input textarea:focus {
        border-color: #7c3aed !important;
        box-shadow: none !important;
        outline: none !important;
      }
      .blockr-ctrl-body shiny-chat-input .shiny-chat-btn-send {
        bottom: 7px !important;
      }
      .blockr-ctrl-body shiny-chat-message[data-role=user] {
        border-radius: 6px !important;
        background-color: rgba(124, 58, 237, 0.1) !important;
      }
      .blockr-ctrl-body shiny-chat-message[data-role=assistant] {
        border-radius: 6px !important;
      }
      .blockr-report-conversation {
        font-size: 0.75em;
        color: #adb5bd;
        text-decoration: none;
        cursor: pointer;
      }
      .blockr-report-conversation:hover {
        color: #7c3aed;
      }",
    "</style>",
    "<script>",
    "Shiny.addCustomMessageHandler('blockr-report-data', function(data) {
      window._blockrReports = window._blockrReports || {};
      window._blockrReports[data.chatId] = window._blockrReports[data.chatId] || [];
      window._blockrReports[data.chatId].push(data.entry);
    });
    function blockrReportConversation(chatId) {
      var entries = (window._blockrReports || {})[chatId] || [];
      if (entries.length === 0) return;
      var parts = [];
      entries.forEach(function(entry, i) {
        var section = ['--- Prompt: ' + (entry.prompt || '') + ' ---'];
        (entry.conversation || []).forEach(function(m) {
          section.push('[' + (m.role || '').toUpperCase() + '] ' + (m.content || ''));
        });
        section.push('Result: success=' + entry.success +
          ', args=' + (entry.args || 'null') +
          ', error=' + (entry.error || 'none'));
        parts.push(section.join('\\n'));
      });
      var body = parts.join('\\n\\n');
      if (body.length > 1800) {
        body = body.substring(0, 1800) + '\\n\\n[truncated]';
      }
      var mailto = 'mailto:contact@cynkra.com'
        + '?subject=' + encodeURIComponent('blockr AI conversation report')
        + '&body=' + encodeURIComponent(body);
      window.location.href = mailto;
    }",
    "</script>")
  )
}


#' @param vars Reactive state values (pre-filtered to externally controllable vars)
#' @param data Input data as list of reactive values
#' @param eval Reactive that evaluates block expression against input data
#' @rdname ai_ctrl_block
#' @export
ai_ctrl_server <- function(id, x, vars, data, eval) {
  moduleServer(id, function(input, output, session) {

    # vars is now pre-filtered by blockr.core to only externally controllable
    # reactiveVal entries
    ctrl_names <- names(vars)

    # No reactiveVal vars means this block doesn't support external_ctrl.
    # Return TRUE (no-op) so default block evaluation proceeds normally.
    if (length(ctrl_names) == 0) {
      return(reactive(TRUE))
    }

    # Gate controls downstream evaluation
    gate <- reactiveVal(TRUE)

    # Persistent client — created on first prompt, reused for conversation memory
    client <- NULL

    observeEvent(input$chat_user_input, {
      prompt <- input$chat_user_input
      if (is.null(prompt) || nchar(trimws(prompt)) == 0) return()

      gate(FALSE)
      on.exit(gate(TRUE))

      dat_snapshot <- shiny::isolate(data())
      input_data <- if (inherits(dat_snapshot, "dm")) {
        dat_snapshot
      } else if (is.list(dat_snapshot) && !is.data.frame(dat_snapshot) &&
                        length(dat_snapshot) > 0) {
        dat_snapshot[[1]]
      } else {
        dat_snapshot
      }

      # Validator: sets reactiveVals then reads expr() which recomputes lazily.
      # Rolls back on failure so block state stays valid.
      eval_validator <- function(args) {
        # Save state for rollback on failure
        old <- lapply(ctrl_names, function(nm) shiny::isolate(vars[[nm]]()))
        names(old) <- ctrl_names
        for (nm in names(args)) {
          if (nm %in% ctrl_names) vars[[nm]](args[[nm]])
        }
        result <- try(shiny::isolate(eval()), silent = TRUE)
        if (inherits(result, "try-error")) {
          # Rollback to previous state
          for (nm in ctrl_names) vars[[nm]](old[[nm]])
          stop(attr(result, "condition"))
        }
        result
      }

      # Create client on first prompt, reuse thereafter (R6 reference semantics)
      if (is.null(client)) {
        client <<- llm_client()
        sp <- build_system_prompt(block_ctor_inputs(x), x)
        client$set_system_prompt(sp)
      }

      # Snapshot current state for LLM context
      current_state <- lapply(vars[ctrl_names], function(v) isolate(v()))

      result <- tryCatch(
        discover_block_args(
          prompt = prompt,
          block = x,
          data = input_data,
          validate = eval_validator,
          client = client,
          current_state = current_state,
          verbose = TRUE
        ),
        error = function(e) {
          message("[discover] error: ", conditionMessage(e))
          list(success = FALSE, error = conditionMessage(e))
        }
      )

      report_data <- list(
        prompt = prompt,
        success = result$success,
        args = if (!is.null(result$args)) jsonlite::toJSON(result$args, auto_unbox = TRUE) else NULL,
        error = result$error,
        conversation = lapply(result$conversation %||% list(), function(m) {
          list(role = m$role, content = m$content)
        })
      )
      session$sendCustomMessage("blockr-report-data", list(
        chatId = session$ns("chat"),
        entry = report_data
      ))
      if (result$success) {
        reply <- if (nzchar(result$message %||% "")) result$message else "Done!"
        shinychat::chat_append("chat", reply, session = session)
      } else if (!is.null(result$question)) {
        # LLM asked a clarifying question — show it in chat
        shinychat::chat_append("chat", result$question, session = session)
      } else {
        shinychat::chat_append(
          "chat",
          paste("Failed:", result$error),
          session = session
        )
      }
    })

    reactive(gate())
  })
}
