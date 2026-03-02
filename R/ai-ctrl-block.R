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

  tags$div(
    class = "blockr-ctrl-body",
    css_ai_ctrl(),
    shinychat::chat_ui(
      chat_id,
      placeholder = "Describe what you want...",
      width = "100%",
      height = "auto",
      icon_assistant = bsicons::bs_icon("stars")
    ),
    tags$div(
      style = "text-align: right; padding: 4px 0; display: none;",
      class = "blockr-report-wrapper",
      `data-chat-id` = chat_id,
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
      ".blockr-ctrl-body {
        padding-bottom: 8px;
      }
      .blockr-ctrl-body shiny-chat-container {
        --_chat-container-padding: 0;
      }
      .blockr-ctrl-body shiny-chat-input textarea {
        border-radius: 6px !important;
        min-height: 38px !important;
        scrollbar-width: none;
        -ms-overflow-style: none;
        box-shadow: none !important;
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
        background-color: #e5e7eb !important;
        color: #374151 !important;
        padding: 6px 12px !important;
        font-size: 0.9em;
      }
      .blockr-ctrl-body shiny-chat-message[data-role=assistant] {
        border-radius: 6px !important;
      }
      .blockr-ctrl-body shiny-chat-message:has(.blockr-ai-status-empty) {
        display: none !important;
      }
      .blockr-report-conversation {
        font-size: 0.75em;
        color: #adb5bd;
        text-decoration: none;
        cursor: pointer;
      }
      .blockr-report-conversation:hover {
        color: #7c3aed;
      }
      .blockr-ai-status {
        display: flex;
        margin: 2px 0;
      }
      .blockr-ai-status:empty {
        display: none;
      }
      .blockr-ai-status-badge {
        display: inline-flex;
        align-items: center;
        gap: 5px;
        font-size: 0.625rem;
        padding: 2px 8px;
        border-radius: 4px;
        background-color: var(--blockr-grey-100, #f3f4f6);
        border: 1px solid var(--blockr-color-border, #e5e7eb);
        color: var(--blockr-color-text-muted, #6b7280);
        white-space: nowrap;
      }
      .blockr-ai-status-icon {
        display: inline-flex;
        align-items: center;
      }
      .blockr-ai-status-badge .spinner-border {
        width: 9px;
        height: 9px;
        border-width: 1.5px;
        color: var(--blockr-color-text-muted, #6b7280);
      }
      .blockr-ai-status .markdown-stream-dot {
        display: none;
      }",
    "</style>",
    "<script>",
    "new MutationObserver(function(mutations) {
      mutations.forEach(function(m) {
        m.addedNodes.forEach(function(node) {
          if (node.nodeType !== 1) return;
          var ta = node.matches && node.matches('.blockr-ctrl-body shiny-chat-input textarea')
            ? node
            : node.querySelector && node.querySelector('.blockr-ctrl-body shiny-chat-input textarea');
          if (ta) setTimeout(function() { ta.focus(); }, 100);
        });
      });
    }).observe(document.body, { childList: true, subtree: true });
    Shiny.addCustomMessageHandler('blockr-scroll-chat', function(data) {
      var container = document.getElementById(data.chatId);
      if (!container) return;
      var input = container.querySelector('shiny-chat-input');
      var target = input || container;
      setTimeout(function() {
        target.scrollIntoView({ behavior: 'smooth', block: 'end' });
      }, 100);
    });
    Shiny.addCustomMessageHandler('blockr-report-data', function(data) {
      window._blockrReports = window._blockrReports || {};
      window._blockrReports[data.chatId] = window._blockrReports[data.chatId] || [];
      window._blockrReports[data.chatId].push(data.entry);
      var wrapper = document.querySelector(
        '.blockr-report-wrapper[data-chat-id=\"' + data.chatId + '\"]'
      );
      if (wrapper) wrapper.style.display = '';
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
      var blob = new Blob([body], {type: 'text/plain'});
      var url = URL.createObjectURL(blob);
      var a = document.createElement('a');
      a.href = url;
      a.download = 'blockr-ai-report.txt';
      document.body.appendChild(a);
      a.click();
      document.body.removeChild(a);
      URL.revokeObjectURL(url);
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
      raw_input <- input$chat_user_input
      if (is.list(raw_input)) {
        prompt <- raw_input$text %||% ""
        images <- raw_input$images
      } else {
        prompt <- raw_input
        images <- NULL
      }
      if (is.null(prompt) || (nchar(trimws(prompt)) == 0 &&
          (is.null(images) || length(images) == 0))) return()

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

      # Snapshot current state for LLM context
      current_state <- lapply(vars[ctrl_names], function(v) isolate(v()))

      rpt <- reporter_shiny("chat", session)

      result <- tryCatch(
        discover_block_args(
          prompt = prompt,
          block = x,
          data = input_data,
          validate = eval_validator,
          client = client,
          current_state = current_state,
          verbose = TRUE,
          data_exploration = blockr.core::blockr_option(
            "data_exploration", "manual"
          ),
          reporter = rpt,
          images = images
        ),
        error = function(e) {
          message("[discover] error: ", conditionMessage(e))
          list(success = FALSE, error = conditionMessage(e))
        }
      )

      # Save client for conversation memory across prompts
      if (!is.null(result$client)) client <<- result$client

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
      session$sendCustomMessage("blockr-scroll-chat", list(
        chatId = session$ns("chat")
      ))
    })

    reactive(gate())
  })
}
