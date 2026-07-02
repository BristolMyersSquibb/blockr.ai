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
# nolint start: quotes_linter.
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
# nolint end

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
ai_ctrl_ui <- structure(
  function(id, x) {
    # No UI for blocks without external_ctrl
    if (isFALSE(attr(x, "external_ctrl"))) {
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
        ),
        # Subtle, hover-revealed list of skills the assistant can use here
        # (only rendered when a skill library targets this block).
        skills_footer_ui(x)
      )
    )
  },
  # Customize the dock ctrl-toggle button: empty label = icon only,
  # sparkle SVG as the icon, blockr-sparkle-btn class for hover/active styling.
  ctrl_label   = "",
  ctrl_icon    = sparkle_icon(14),
  ctrl_class   = "blockr-sparkle-btn",
  ctrl_tooltip = "AI Assistant"
)

#' Footer "Skills" affordance for the assistant panel.
#'
#' A grey "Skills" word (matching Clear / Report) that reveals a compact popover
#' on hover/focus, listing the skills the assistant can consult for this block
#' plus how to invoke them. Returns `NULL` when no skill targets the block, so it
#' is invisible unless relevant. Intentionally compact -- the skill's templates
#' are NOT dumped here; the model lists them on demand.
#' @noRd
skills_footer_ui <- function(x) {
  skills <- tryCatch(block_skills(x), error = function(e) list())
  if (!length(skills)) {
    return(NULL)
  }

  items <- lapply(skills, function(s) {
    desc <- truncate_summary(s$description %||% "", 64)
    tags$li(
      tags$span(class = "blockr-skills-name", s$name),
      if (nzchar(desc)) tags$span(class = "blockr-skills-desc", paste0(" \u2014 ", desc))
    )
  })
  first <- skills[[1]]$name

  tagList(
    tags$span(class = "blockr-action-sep", "\u00b7"),
    tags$span(
      class = "blockr-skills-link", tabindex = "0",
      "Skills",
      tags$span(
        class = "blockr-skills-pop",
        tags$ul(class = "blockr-skills-pop-list", items),
        tags$div(class = "blockr-skills-pop-hint",
                 sprintf("e.g. \u201cuse the %s skill to \u2026\u201d", first))
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
      /* The dock wraps each section in a bordered accordion-body; the AI
       * section sitting above the params shows a doubled divider (its own
       * bottom border + the next section's top border). Drop this section's
       * bottom border so a single divider remains. */
      .accordion-body:has(> .blockr-ctrl-body) {
        border-bottom: 0 !important;
      }
      .blockr-ctrl-body .shiny-chat-messages {
        --_chat-container-padding: 0;
        --shiny-chat-messages-padding-bottom: 0;
        min-height: 0;
        overflow-y: auto;
      }
      .blockr-ctrl-body .shiny-chat-input {
        overflow-x: hidden;
      }
      .blockr-ctrl-body .shiny-chat-input textarea {
        /* Standard bordered input (cf. blockr.dplyr .blockr-input--bordered):
         * taller + more rounded, with room on the right for the send button. */
        border-radius: 10px !important;
        min-height: 46px !important;
        height: 46px;
        max-height: 140px !important;
        padding: 11px 44px 11px 14px !important;
        background-color: var(--blockr-color-bg-input, #f9fafb) !important;
        border: 1px solid var(--blockr-color-border, #e5e7eb) !important;
        font-size: var(--blockr-font-size-base, 0.875rem) !important;
        scrollbar-width: none;
        -ms-overflow-style: none;
        box-shadow: none !important;
      }
      .blockr-ctrl-body .shiny-chat-input textarea::-webkit-scrollbar {
        display: none;
      }
      .blockr-ctrl-body .shiny-chat-input textarea:focus {
        /* Border-only focus (like blockr.dplyr's standard input). No box-shadow
         * ring: the parent .shiny-chat-input has overflow-x:hidden/overflow-y:auto,
         * which clips the ring into an asymmetric shadow + a corner artifact. */
        border-color: #7c3aed !important;
        box-shadow: none !important;
        outline: none !important;
      }
      /* Send button: a bare arrow in the accent colour -- no background, no
       * circle, centred. (The arrow-in-circle bootstrap icon is swapped for a
       * plain arrow by the script below.) */
      .blockr-ctrl-body .shiny-chat-input .shiny-chat-btn-send {
        /* Vertically centred in the input (height-agnostic), not bottom-pinned. */
        top: 50% !important;
        bottom: auto !important;
        transform: translateY(-50%) !important;
        right: 8px !important;
        width: 26px !important;
        height: 26px !important;
        padding: 0 !important;
        background: transparent !important;
        border: none !important;
        border-radius: 0 !important;
        box-shadow: none !important;
        color: #7c3aed !important;
        display: inline-flex !important;
        align-items: center !important;
        justify-content: center !important;
        transition: color 0.15s ease !important;
      }
      .blockr-ctrl-body .shiny-chat-input .shiny-chat-btn-send:hover {
        color: #6d28d9 !important;
      }
      .blockr-ctrl-body .shiny-chat-input .shiny-chat-btn-send:disabled {
        color: var(--blockr-grey-400, #adb5bd) !important;
        transform: none;
      }
      .blockr-ctrl-body .shiny-chat-input .shiny-chat-btn-send svg {
        width: 20px !important;
        height: 20px !important;
        fill: currentColor !important;
      }
      .blockr-ctrl-body .shiny-chat-message[data-role=user] {
        border-radius: 6px !important;
        background-color: var(--blockr-grey-50, #f9fafb) !important;
        color: var(--blockr-color-text-muted, #6b7280) !important;
        padding: 6px 12px !important;
        font-size: var(--blockr-font-size-sm, 0.8125rem);
      }
      .blockr-ctrl-body .shiny-chat-message[data-role=assistant] {
        border-radius: 6px !important;
        color: var(--blockr-color-text-muted, #6b7280) !important;
        font-size: var(--blockr-font-size-sm, 0.8125rem);
      }
      .blockr-ctrl-body .shiny-chat-message .message-icon {
        border: none;
        border-radius: 0;
        color: #7c3aed;
      }
      .blockr-ctrl-body .shiny-chat-message:has(.blockr-ai-status-empty) {
        display: none !important;
      }
      /* shinychat 0.4 shows a default pulsing dot while a response streams; we
         already have our own Analyzing badge, so hide it in the message stream
         (but keep any dot inside our own status badge). */
      .blockr-ctrl-body .markdown-stream-dot {
        display: none !important;
      }
      .blockr-ctrl-body .blockr-ai-status .markdown-stream-dot {
        display: inline-block !important;
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
      .blockr-skills-link {
        font-size: 0.75em;
        color: #adb5bd;
        cursor: default;
        position: relative;
      }
      .blockr-skills-link:hover,
      .blockr-skills-link:focus-within { color: #7c3aed; }
      .blockr-skills-pop {
        display: none;
        position: absolute;
        right: 0;
        bottom: 1.7em;            /* open upward, above the footer */
        z-index: 1000;
        width: 280px;
        max-width: 80vw;
        padding: 7px 9px;
        border: 1px solid #e5e7eb;
        border-radius: 6px;
        background: #fff;
        box-shadow: 0 4px 14px rgba(0,0,0,0.12);
        color: #374151;
        font-size: 12px;
        line-height: 1.35;
        text-align: left;
        cursor: default;
      }
      .blockr-skills-link:hover .blockr-skills-pop,
      .blockr-skills-link:focus-within .blockr-skills-pop { display: block; }
      .blockr-skills-pop-list {
        margin: 0; padding: 0; list-style: none;
      }
      .blockr-skills-pop-list li {
        white-space: nowrap; overflow: hidden; text-overflow: ellipsis;
      }
      .blockr-skills-name { font-weight: 600; }
      .blockr-skills-desc { opacity: 0.8; }
      .blockr-skills-pop-hint { margin-top: 5px; opacity: 0.75; font-style: italic; }
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
      /* stack of per-tool-call badges (one per call, option A) */
      .blockr-ai-status-stack {
        flex-direction: column;
        align-items: flex-start;
        gap: 3px;
      }
      /* the one-line summary appended after a badge label */
      .blockr-ai-status-summary {
        font-weight: 400;
        opacity: 0.85;
        overflow: hidden;
        text-overflow: ellipsis;
        max-width: 240px;
      }
      .blockr-ai-status-summary code {
        font-size: 0.92em;
        background: rgba(0, 0, 0, 0.05);
        padding: 0 3px;
        border-radius: 3px;
      }
      .blockr-ai-status-sep { opacity: 0.45; }
      .blockr-ai-status-icon svg { display: block; }
      /* completed badge: drop the colour wash, go quiet/grey, keep the trace */
      .blockr-ai-status-badge.is-done {
        background-color: #fff;
        border-color: #ececf0;
        color: #9ca3af;
      }
      .blockr-ai-status-badge.is-done .blockr-ai-status-summary code {
        background: var(--blockr-grey-100, #f3f4f6);
      }
      .blockr-ai-status-badge.is-done .blockr-ai-status-icon { color: #22c55e; }
      .blockr-ai-status-badge.is-done.is-error {
        background-color: #fffbeb;
        border-color: #fde68a;
        color: #b45309;
      }
      .blockr-ai-status-badge.is-error .blockr-ai-status-icon { color: #d97706; }
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
      .blockr-ctrl-body.ai-working .shiny-chat-message:last-of-type .message-icon .sparkle-main {
        animation: sparkle-rotate 3s ease-in-out infinite;
        transform-origin: center;
      }
      .blockr-ctrl-body.ai-working .shiny-chat-message:last-of-type .message-icon .sparkle-sm-1 {
        animation: sparkle-twinkle 2s ease-in-out 0.3s infinite;
        transform-origin: center;
      }
      .blockr-ctrl-body.ai-working .shiny-chat-message:last-of-type .message-icon .sparkle-sm-2 {
        animation: sparkle-twinkle 2s ease-in-out 0.8s infinite;
        transform-origin: center;
      }
      .blockr-sparkle-btn {
        display: inline-flex;
        align-items: center;
        transition: color 0.2s ease, transform 0.2s ease;
      }
      .blockr-sparkle-btn:hover {
        color: #7c3aed !important;
        transform: scale(1.15);
      }
      .blockr-sparkle-btn:hover .blockr-sparkle-svg {
        filter: drop-shadow(0 0 3px rgba(124, 58, 237, 0.4));
      }
      .btn-check:checked + .btn .blockr-sparkle-btn {
        color: #7c3aed !important;
      }
      .btn-check:checked + .btn .blockr-sparkle-btn .sparkle-main {
        animation: sparkle-rotate 3s ease-in-out infinite;
        transform-origin: center;
      }
      .btn-check:checked + .btn .blockr-sparkle-btn .sparkle-sm-1 {
        animation: sparkle-twinkle 2s ease-in-out 0.3s infinite;
        transform-origin: center;
      }
      .btn-check:checked + .btn .blockr-sparkle-btn .sparkle-sm-2 {
        animation: sparkle-twinkle 2s ease-in-out 0.8s infinite;
        transform-origin: center;
      }",
    "</style>",
    "<script>",
    "var BLOCKR_ARROW_D = 'M8 12a.5.5 0 0 0 .5-.5V3.707l3.146 3.147a.5.5 0 0 0 .708-.708l-4-4a.5.5 0 0 0-.708 0l-4 4a.5.5 0 1 0 .708.708L7.5 3.707V11.5a.5.5 0 0 0 .5.5';
    function blockrEnsureArrow(svg) {
      var path = svg.querySelector('path');
      if (path && path.getAttribute('d') === BLOCKR_ARROW_D) return; // already plain arrow
      svg.setAttribute('viewBox', '0 0 16 16');
      while (svg.firstChild) svg.removeChild(svg.firstChild);
      var np = document.createElementNS('http://www.w3.org/2000/svg', 'path');
      np.setAttribute('d', BLOCKR_ARROW_D);
      svg.appendChild(np);
    }
    function blockrSwapSendIcon() {
      document.querySelectorAll('.blockr-ctrl-body .shiny-chat-input .shiny-chat-btn-send').forEach(function(btn) {
        var svg = btn.querySelector('svg');
        if (svg) blockrEnsureArrow(svg);
        // shinychat re-renders the icon when the input goes enabled/disabled,
        // which can restore the arrow-in-circle; observe the button so we
        // re-swap synchronously (no poll flash). Content-based, so an in-place
        // revert is caught too.
        if (!btn.getAttribute('data-blockr-obs')) {
          btn.setAttribute('data-blockr-obs', '1');
          new MutationObserver(function() {
            var s = btn.querySelector('svg');
            if (s) blockrEnsureArrow(s);
          }).observe(btn, { childList: true, subtree: true, attributes: true });
        }
      });
    }
    blockrSwapSendIcon();
    // Backstop: the button is rendered by shinychats web component after the
    // panel mutation fires, so a cheap poll catches newly-appeared buttons (and
    // attaches their observer); blockrEnsureArrow is a no-op once correct.
    setInterval(blockrSwapSendIcon, 400);
    new MutationObserver(function(mutations) {
      blockrSwapSendIcon();
      mutations.forEach(function(m) {
        m.addedNodes.forEach(function(node) {
          if (node.nodeType !== 1) return;
          var ta = node.matches && node.matches('.blockr-ctrl-body .shiny-chat-input textarea')
            ? node
            : node.querySelector && node.querySelector('.blockr-ctrl-body .shiny-chat-input textarea');
          if (ta) setTimeout(function() { ta.focus(); blockrSwapSendIcon(); }, 100);
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
        var input = container.querySelector('.shiny-chat-input');
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

    # Persistent client -- created on first prompt, reused for conversation memory
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

      # Snapshot current state for LLM context. Exclude block_name (the block
      # title) -- it isn't a data parameter, and showing it just invites the
      # model to rename the block.
      state_names <- setdiff(ctrl_names, "block_name")
      current_state <- lapply(vars[state_names], function(v) isolate(v()))

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
        effect = result$effect,
        noop = result$noop,
        error = result$error,
        conversation = lapply(result$conversation %||% list(), function(m) {
          list(role = m$role, content = m$content)
        })
      )
      if (result$success) {
        reply <- if (nzchar(result$message %||% "")) result$message else "Done!"
        shinychat::chat_append("chat", reply, session = session)
      } else if (!is.null(result$question)) {
        # LLM asked a clarifying question -- show it in chat
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
