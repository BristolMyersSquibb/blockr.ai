# Implementation Plan: Deterministic LLM Transform Block

## Goal

Create `new_llm_transform_block_det()` - a parallel implementation that uses the deterministic loop approach instead of tool-based communication.

## Why This Matters

| Metric | Tool-based (current) | Deterministic (new) |
|--------|---------------------|---------------------|
| Speed | 39.0s avg | 9.1s avg (4.3x faster) |
| Reliability | 100% (with validation) | 100% |
| Complexity | Tools + schemas | Plain text |

## Architecture Comparison

### Current (Tool-based)
```
User prompt → LLM decides → call eval_tool? → call data_tool?
                              ↓
                         LLM controls flow
                              ↓
                         Eventually returns
```

### New (Deterministic)
```
User prompt + data preview → LLM writes code → System runs code
                                                    ↓
                                           [Error] → show error → iterate
                                           [Success] → show result → DONE?
```

## Files to Create/Modify

### 1. New File: `R/block-transform-det.R`

```r
# Deterministic transform block constructor
new_llm_transform_block_det <- function(...) {
  new_llm_block_det(c("llm_transform_block_det", "transform_block"), ...)
}

# System prompt (simpler, no tool instructions)
system_prompt.llm_transform_block_det_proxy <- function(x, datasets, ...) {
  # No tool prompts needed
  # Include data preview directly
  # Instructions for DONE signal
}
```

### 2. New File: `R/llm-block-det.R`

```r
# Base constructor for deterministic blocks
new_llm_block_det <- function(class, messages = list(), code = character(),
                               ctor = sys.parent(), ...) {
  # Similar to new_llm_block but:
  # - No tools registration
  # - Different proxy class suffix: _det_proxy
}
```

### 3. New File: `R/llm-server-det.R`

```r
# Deterministic server implementation
llm_block_server.llm_block_det_proxy <- function(x) {
  function(id, data = NULL, ...args = list()) {
    moduleServer(id, function(input, output, session) {

      # Key differences from tool-based:
      # 1. No tools registered
      # 2. Data preview in first message (automatic)
      # 3. Code extraction from markdown blocks
      # 4. System runs code after each response
      # 5. Iterate until DONE or max iterations

    })
  }
}
```

### 4. Modify: `R/llm-ui.R` (optional)

May need a variant UI or can reuse existing.

## Detailed Implementation

### Step 1: Create Proxy Class

```r
# In R/llm-block-det.R

new_llm_block_det <- function(class, messages = list(), code = character(),
                               ctor = sys.parent(), ...) {

  cls <- c(class, "llm_block")

  llm_obj <- structure(
    list(
      messages = check_messages(messages),
      code = code
    ),
    class = paste0(cls[1], "_det_proxy")  # e.g., llm_transform_block_det_proxy
  )

  new_block(
    server = llm_block_server_det(llm_obj),
    ui = llm_block_ui_det(llm_obj),
    class = cls,
    ctor = ctor,
    allow_empty_state = "messages",
    ...
  )
}
```

### Step 2: System Prompt (No Tools)

```r
# In R/block-transform-det.R

system_prompt.llm_transform_block_det_proxy <- function(x, datasets, ...) {
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
```

### Step 3: Deterministic Server Loop

```r
# In R/llm-server-det.R

llm_block_server_det <- function(x) {
  function(id, data = NULL, ...args = list()) {
    moduleServer(id, function(input, output, session) {

      # Reactive values
      rv_code <- reactiveVal(x[["code"]])
      rv_msgs <- reactiveVal(x[["messages"]])
      rv_iteration <- reactiveVal(0)
      rv_status <- reactiveVal("idle")  # idle, running, done, error

      # Get datasets
      r_datasets <- reactive({
        c(
          if (is.reactive(data) && !is.null(data())) list(data = data()),
          if (is.reactivevalues(...args)) reactiveValuesToList(...args)
        )
      })

      # Create data preview
      data_preview <- reactive({
        create_data_preview(r_datasets())
      })

      # Build initial message with data preview
      initial_message <- reactive({
        paste0(
          "# Data Available\n\n",
          data_preview(),
          "\n\n# Task\n\n",
          "[USER_PROMPT_HERE]",
          "\n\nWrite R code to complete this task."
        )
      })

      # LLM client
      client <- reactive({
        blockr_option("llm_chat_fn", ellmer::chat_openai)()
      })

      # Async task for LLM
      task <- ExtendedTask$new(function(client, method, ...) {
        rlang::inject(client[[method]](...))
      })

      # Handle user input - START the deterministic loop
      observeEvent(input$chat_user_input, {
        req(input$chat_user_input)

        user_prompt <- input$chat_user_input

        # Build first message with data preview
        first_msg <- paste0(
          "# Data Available\n\n",
          data_preview(),
          "\n\n# Task\n\n",
          user_prompt,
          "\n\nWrite R code to complete this task. Wrap code in ```r ... ``` blocks."
        )

        # Update messages
        msgs <- rv_msgs()
        msgs <- append(msgs, list(list(role = "user", content = first_msg)))
        rv_msgs(msgs)

        # Set system prompt and start
        client()$set_system_prompt(system_prompt(x, r_datasets()))
        rv_iteration(1)
        rv_status("running")

        # Query LLM
        task$invoke(client(), "chat", first_msg)
      })

      # Handle LLM response - CONTINUE the deterministic loop
      task_ready <- reactive({
        switch(task$status(), error = FALSE, success = TRUE, NULL)
      })

      observeEvent(task_ready(), {
        req(task_ready())
        req(rv_status() == "running")

        response <- task$result()

        # Update messages with assistant response
        msgs <- rv_msgs()
        msgs <- append(msgs, list(list(role = "assistant", content = response)))
        rv_msgs(msgs)

        # Check for DONE
        if (is_done_response(response)) {
          rv_status("done")
          return()
        }

        # Extract code from markdown
        code <- extract_code_from_markdown(response)

        if (is.null(code) || nchar(trimws(code)) == 0) {
          # No code found - ask for code
          next_msg <- "Please provide R code wrapped in ```r ... ``` blocks."
          msgs <- append(msgs, list(list(role = "user", content = next_msg)))
          rv_msgs(msgs)
          task$invoke(client(), "chat", next_msg)
          return()
        }

        # Run code
        result <- try_eval_code(x, code, r_datasets())

        if (inherits(result, "try-error")) {
          # Error - show to LLM
          error_msg <- paste0(
            "Your code produced an error:\n\n",
            "```\n", attr(result, "condition")$message, "\n```\n\n",
            "Please fix the code and try again."
          )
          msgs <- append(msgs, list(list(role = "user", content = error_msg)))
          rv_msgs(msgs)

          rv_iteration(rv_iteration() + 1)
          if (rv_iteration() > 5) {
            rv_status("error")
            return()
          }

          task$invoke(client(), "chat", error_msg)

        } else if (is.data.frame(result)) {
          # Success - show result and ask for confirmation
          rv_code(code)

          result_preview <- paste(
            utils::capture.output(print(result)),
            collapse = "\n"
          )

          confirm_msg <- paste0(
            "Your code executed successfully. Here is the result:\n\n",
            "```\n", result_preview, "\n```\n\n",
            "Does this look correct? If yes, respond with just: DONE\n",
            "If not, provide corrected code in ```r ... ``` blocks."
          )
          msgs <- append(msgs, list(list(role = "user", content = confirm_msg)))
          rv_msgs(msgs)

          rv_iteration(rv_iteration() + 1)
          task$invoke(client(), "chat", confirm_msg)

        } else {
          # Not a data.frame
          type_msg <- paste0(
            "Your code ran but did not produce a data.frame. ",
            "Result class: ", class(result)[1], "\n\n",
            "Please fix the code to produce a data.frame."
          )
          msgs <- append(msgs, list(list(role = "user", content = type_msg)))
          rv_msgs(msgs)

          rv_iteration(rv_iteration() + 1)
          task$invoke(client(), "chat", type_msg)
        }
      })

      # Return block output
      list(
        expr = reactive(code_expr(rv_code())),
        state = list(
          messages = rv_msgs,
          code = rv_code
        )
      )
    })
  }
}
```

### Step 4: Helper Functions

```r
# In R/utils-det.R

# Check if response indicates DONE
is_done_response <- function(response) {
  grepl("^\\s*DONE\\s*$", response, ignore.case = TRUE) ||
    (grepl("\\bDONE\\b", response) && !grepl("```", response))
}

# Extract code from markdown blocks
extract_code_from_markdown <- function(text) {
  # Match ```r ... ``` or ```R ... ``` blocks

pattern <- "```[rR]\\s*\\n([\\s\\S]*?)\\n```"
  matches <- regmatches(text, gregexpr(pattern, text, perl = TRUE))[[1]]

  if (length(matches) == 0) {
    # Try without language specifier
    pattern <- "```\\s*\\n([\\s\\S]*?)\\n```"
    matches <- regmatches(text, gregexpr(pattern, text, perl = TRUE))[[1]]
  }

  if (length(matches) == 0) return(NULL)

  # Extract content from last code block
  last_block <- matches[length(matches)]
  code <- sub("```[rR]?\\s*\\n", "", last_block)
  code <- sub("\\n```$", "", code)
  trimws(code)
}

# Create data preview for prompt
create_data_preview <- function(datasets) {
  paste(
    sapply(names(datasets), function(nm) {
      d <- datasets[[nm]]
      preview_lines <- utils::capture.output(print(utils::head(d, 5)))
      paste0(
        "## Dataset: ", nm, "\n",
        "Dimensions: ", nrow(d), " rows x ", ncol(d), " cols\n",
        "Columns: ", paste(names(d), collapse = ", "), "\n\n",
        "```\n",
        paste(preview_lines, collapse = "\n"),
        "\n```"
      )
    }),
    collapse = "\n\n"
  )
}
```

## Implementation Order

1. **Create `R/utils-det.R`** - Helper functions
   - `is_done_response()`
   - `extract_code_from_markdown()`
   - `create_data_preview()`

2. **Create `R/llm-block-det.R`** - Base constructor
   - `new_llm_block_det()`

3. **Create `R/llm-server-det.R`** - Server logic
   - `llm_block_server_det()`
   - Main deterministic loop

4. **Create `R/block-transform-det.R`** - Transform block
   - `new_llm_transform_block_det()`
   - `system_prompt.llm_transform_block_det_proxy()`

5. **Test interactively** - Verify it works in Shiny app

6. **Compare performance** - Run side-by-side with current implementation

## Testing Plan

```r
# In a Shiny app or blockr workspace:

# Current (tool-based)
block1 <- new_llm_transform_block()

# New (deterministic)
block2 <- new_llm_transform_block_det()

# Same prompt, compare:
# - Time to completion
# - Number of iterations
# - Result correctness
```

## Open Questions

1. **UI reuse**: Can we reuse `llm_block_ui()` or need a variant?
2. **Streaming**: Should we stream responses or wait for complete?
3. **Skills integration**: How to add skills to deterministic loop?
4. **Cancellation**: How to handle user cancellation mid-loop?
5. **History**: How to display iteration history in UI?

## Success Criteria

- [ ] Block creates successfully
- [ ] Data preview appears in first message
- [ ] Code extraction works reliably
- [ ] Iteration loop continues until DONE
- [ ] Final code is captured correctly
- [ ] Performance is ~4x faster than tool-based
- [ ] 100% reliability on well-defined transforms
