# AI Control Block Plugin
#
# Provides AI-powered control for blocks with external_ctrl enabled.

#' Sparkle icon SVG
#'
#' Three-star sparkle SVG icon used as the blockr.ai brand icon.
#'
#' @param size Icon pixel size (default 18)
#'
#' @return An [htmltools::HTML()] string containing an SVG element.
#'
#' @keywords internal
sparkle_icon <- function(size = 18) {
  HTML(sprintf(
    paste0(
      '<svg class="blockr-sparkle-svg" width="%d" height="%d" ',
      'viewBox="0 0 24 24" fill="none" xmlns="http://www.w3.org/2000/svg">',
      '<path class="sparkle-main" d="M12 2L13.5 8.5L20 10L13.5 11.5L12 18',
      'L10.5 11.5L4 10L10.5 8.5L12 2Z" fill="currentColor"/>',
      '<path class="sparkle-sm sparkle-sm-1" d="M19 15L19.75 17.25L22 18',
      'L19.75 18.75L19 21L18.25 18.75L16 18L18.25 17.25L19 15Z" ',
      'fill="currentColor" opacity="0.7"/>',
      '<path class="sparkle-sm sparkle-sm-2" d="M5 1L5.5 2.5L7 3L5.5 3.5',
      'L5 5L4.5 3.5L3 3L4.5 2.5L5 1Z" fill="currentColor" opacity="0.5"/>',
      '</svg>'
    ),
    size, size
  ))
}

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
      icon_assistant = sparkle_icon(16)
    ),
    tags$div(
      style = "padding: 4px 0;",
      class = "blockr-report-wrapper",
      `data-chat-id` = chat_id,
      tags$a(
        href = "#",
        class = "blockr-clear-conversation",
        onclick = sprintf(
          "Shiny.setInputValue('%s', Date.now()); return false;",
          ns("clear_chat")
        ),
        "Clear"
      ),
      tags$span(class = "blockr-action-sep", "\u00b7"),
      tags$a(
        id = ns("download_report"),
        class = "blockr-report-conversation shiny-download-link",
        href = "",
        target = "_blank",
        download = "",
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
        display: flex;
        flex-direction: column;
        flex: 1;
        min-height: 0;
        padding-bottom: 0;
      }
      .blockr-ctrl-body shiny-chat-container {
        --_chat-container-padding: 0;
        min-height: 0;
        overflow-y: auto;
      }
      .blockr-ctrl-body shiny-chat-input textarea {
        border-radius: 6px !important;
        height: 38px;
        min-height: 38px !important;
        max-height: 120px !important;
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
        background-color: var(--blockr-grey-50, #f9fafb) !important;
        color: var(--blockr-color-text-muted, #6b7280) !important;
        padding: 6px 12px !important;
        font-size: var(--blockr-font-size-sm, 0.8125rem);
      }
      .blockr-ctrl-body shiny-chat-message[data-role=assistant] {
        border-radius: 6px !important;
        color: var(--blockr-color-text-muted, #6b7280) !important;
        font-size: var(--blockr-font-size-sm, 0.8125rem);
      }
      .blockr-ctrl-body shiny-chat-message .message-icon {
        border: none;
        border-radius: 0;
        color: #7c3aed;
      }
      .blockr-ctrl-body shiny-chat-message:has(.blockr-ai-status-empty) {
        display: none !important;
      }
      .blockr-report-wrapper {
        display: flex;
        align-items: center;
        justify-content: flex-end;
        gap: 4px;
        flex-shrink: 0;
      }
      .blockr-action-sep {
        font-size: 0.75em;
        color: #d1d5db;
      }
      .blockr-clear-conversation,
      .blockr-report-conversation {
        font-size: 0.75em;
        color: #adb5bd;
        text-decoration: none;
        cursor: pointer;
      }
      .blockr-clear-conversation:hover,
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
        color: inherit;
      }
      .blockr-ai-status-badge.phase-thinking {
        background-color: #f0fdfa; border-color: #99f6e4; color: #14b8a6;
      }
      .blockr-ai-status-badge.phase-exploring {
        background-color: #eff6ff; border-color: #bfdbfe; color: #3b82f6;
      }
      .blockr-ai-status-badge.phase-validating {
        background-color: #f5f3ff; border-color: #c4b5fd; color: #7c3aed;
      }
      .blockr-ai-status-badge.phase-confirming {
        background-color: #f0fdf4; border-color: #bbf7d0; color: #22c55e;
      }
      .blockr-ai-status-badge.phase-retrying {
        background-color: #fffbeb; border-color: #fde68a; color: #d97706;
      }
      .blockr-ai-status .markdown-stream-dot {
        display: none;
      }
      @keyframes sparkle-rotate {
        0%   { transform: rotate(0deg) scale(1); }
        25%  { transform: rotate(5deg) scale(1.1); }
        50%  { transform: rotate(0deg) scale(1); }
        75%  { transform: rotate(-5deg) scale(1.1); }
        100% { transform: rotate(0deg) scale(1); }
      }
      @keyframes sparkle-twinkle {
        0%, 100% { opacity: 0.5; transform: scale(0.8); }
        50% { opacity: 1; transform: scale(1.2); }
      }
      .blockr-ctrl-body.ai-working shiny-chat-message:last-of-type .message-icon .sparkle-main {
        animation: sparkle-rotate 3s ease-in-out infinite;
        transform-origin: center;
      }
      .blockr-ctrl-body.ai-working shiny-chat-message:last-of-type .message-icon .sparkle-sm-1 {
        animation: sparkle-twinkle 2s ease-in-out 0.3s infinite;
        transform-origin: center;
      }
      .blockr-ctrl-body.ai-working shiny-chat-message:last-of-type .message-icon .sparkle-sm-2 {
        animation: sparkle-twinkle 2s ease-in-out 0.8s infinite;
        transform-origin: center;
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
    Shiny.addCustomMessageHandler('blockr-ai-working', function(data) {
      var container = document.getElementById(data.chatId);
      if (!container) return;
      var body = container.closest('.blockr-ctrl-body');
      if (!body) return;
      if (data.working) {
        body.classList.add('ai-working');
      } else {
        body.classList.remove('ai-working');
      }
    });
    Shiny.addCustomMessageHandler('blockr-scroll-chat', function(data) {
      var container = document.getElementById(data.chatId);
      if (!container) return;
      var sidebar = container.closest('.blockr-ctrl-sidebar-content');
      if (sidebar) {
        setTimeout(function() { sidebar.scrollTop = sidebar.scrollHeight; }, 100);
      } else {
        var input = container.querySelector('shiny-chat-input');
        var target = input || container;
        setTimeout(function() {
          target.scrollIntoView({ behavior: 'smooth', block: 'end' });
        }, 100);
      }
    });
",
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

    # Server-side report data accumulator
    report_entries <- list()

    output$download_report <- downloadHandler(
      filename = function() "blockr-ai-report.txt",
      content = function(file) {
        parts <- vapply(report_entries, function(entry) {
          section <- sprintf("--- Prompt: %s ---", entry$prompt %||% "")
          msgs <- vapply(entry$conversation %||% list(), function(m) {
            sprintf("[%s] %s", toupper(m$role %||% ""), m$content %||% "")
          }, character(1))
          result_line <- sprintf(
            "Result: success=%s, args=%s, error=%s",
            entry$success,
            entry$args %||% "null",
            entry$error %||% "none"
          )
          paste(c(section, msgs, result_line), collapse = "\n")
        }, character(1))
        writeLines(paste(parts, collapse = "\n\n"), file)
      }
    )

    observeEvent(input$clear_chat, {
      shinychat::chat_clear("chat", session = session)
      client <<- NULL
      report_entries <<- list()
    })

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

      session$sendCustomMessage("blockr-ai-working", list(
        chatId = session$ns("chat"), working = TRUE
      ))
      on.exit(session$sendCustomMessage("blockr-ai-working", list(
        chatId = session$ns("chat"), working = FALSE
      )), add = TRUE)

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

      report_entries[[length(report_entries) + 1L]] <<- list(
        prompt = prompt,
        success = result$success,
        args = if (!is.null(result$args)) jsonlite::toJSON(result$args, auto_unbox = TRUE) else NULL,
        error = result$error,
        conversation = lapply(result$conversation %||% list(), function(m) {
          list(role = m$role, content = m$content)
        })
      )
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
