# AI Control: The discover_block_args Loop

> The core function that drives AI control: iterative LLM prompting,
> JSON extraction, validation, and confirmation.

## Function Signature

```r
# blockr.ai/R/discover.R
discover_block_args <- function(
  prompt,              # User's natural language request
  block,               # Block object (e.g. new_filter_block())
  data = NULL,         # Input data (data.frame, dm, or NULL for source blocks)
  validate = NULL,     # Validation function; NULL = standalone mode
  max_iter = 5,        # Maximum LLM round-trips
  verbose = FALSE,     # If TRUE, records full conversation
  client = NULL,       # Existing ellmer chat client (for conversation memory)
  current_state = NULL # Plain list of current block param values
)
```

## Return Value

```r
list(
  success = TRUE/FALSE,
  args    = list(conditions = ..., preserve_order = ...),  # last valid args
  result  = <data.frame/dm/ggplot/...>,                    # block output
  error   = "error message" or NULL,
  conversation = list(...)  # if verbose = TRUE
)
```

## The Iterative Loop

```
┌──────────────────────────────────────────────────────┐
│  1. Build system prompt (from registry metadata)     │
│  2. Build first user message (data preview + task)   │
│                                                      │
│  for i in 1:max_iter:                                │
│    ├─ Send message to LLM                            │
│    ├─ Check: is response "DONE"?  ──yes──► break     │
│    ├─ Extract JSON from response                     │
│    │   └─ No JSON found? → ask again, next           │
│    ├─ Parse JSON (fromJSON)                          │
│    │   └─ Parse error? → send error, next            │
│    ├─ Identical to prev args? ──yes──► accept, break │
│    ├─ Validate (call validate(args))                 │
│    │   └─ Validation error? → send error, next       │
│    └─ Success! Show result preview to LLM            │
│        → "Correct? Say DONE or fix."                 │
│                                                      │
│  Return {success, args, result, error, conversation} │
└──────────────────────────────────────────────────────┘
```

### Step-by-step

#### 1. Setup

```r
var_names <- block_ctor_inputs(block)
# e.g. c("conditions", "preserve_order")

client <- llm_client()
system_prompt <- build_system_prompt(var_names, block)
client$set_system_prompt(system_prompt)
```

`block_ctor_inputs()` reads the constructor's `formals()`:

```r
# blockr.ai/R/discover.R
block_ctor_inputs <- function(x) {
  ctor <- attr(x, "ctor")
  if (is.null(ctor)) return(character())
  setdiff(names(formals(ctor)), "...")
}
```

#### 2. First user message

```r
msg <- paste0(
  data_preview(data),
  "# Task\n\n", prompt,
  "\n\nReturn JSON with parameter values."
)
```

Example with iris data and "setosa only" prompt:

```
# Input Data

150 rows x 5 cols: Sepal.Length (numeric), Sepal.Width (numeric),
Petal.Length (numeric), Petal.Width (numeric), Species (factor)

# Task

setosa only

Return JSON with parameter values.
```

#### 3. LLM response → JSON extraction

The LLM responds with markdown containing a JSON block:

```
I'll filter for setosa species.

```json
{"conditions": [{"column": "Species", "values": ["setosa"], "mode": "include"}]}
```
```

`extract_json()` parses this:

```r
# blockr.ai/R/utils-llm.R
extract_json <- function(text) {
  # Try code block first: ```json ... ```
  pattern <- "```(?:json)?\\s*\\n([\\s\\S]*?)\\n```"
  matches <- regmatches(text, gregexpr(pattern, text, perl = TRUE))[[1]]
  if (length(matches) > 0) {
    # extract from last code block
    ...
  }
  # Fallback: raw JSON starting with {
  if (grepl("^\\s*\\{", text)) return(trimws(text))
  NULL
}
```

#### 4. Validation

The extracted JSON is parsed with `jsonlite::fromJSON()` and passed to
the validator:

```r
new_args <- jsonlite::fromJSON(json_str, simplifyVector = FALSE)
result <- validate(new_args)
```

If validation succeeds, the result preview is sent back to the LLM:

```r
preview <- format_result_preview(result)
msg <- paste0("Result:\n```\n", preview, "\n```\nCorrect? Say DONE or fix.")
```

#### 5. Confirmation

The LLM sees the result and responds either:
- `"DONE"` → loop breaks, success
- New JSON → loop continues with the new parameters

`is_done_response()` checks for the DONE keyword:

```r
is_done_response <- function(response) {
  grepl("^\\s*DONE\\s*$", response, ignore.case = TRUE) ||
    (grepl("\\bDONE\\b", response) && !grepl("```", response))
}
```

## Two Validator Modes

### Standalone Mode (for testing outside Shiny)

When `validate = NULL`, `discover_block_args` creates a standalone
validator using `testServer`:

```r
# blockr.ai/R/discover.R
standalone_validator_internal <- function(ctor, data) {
  ctor_fun_name <- attr(ctor, "fun")
  ctor_pkg_name <- attr(ctor, "pkg")

  function(args) {
    # Build pkg::fun(...) call
    if (!is.null(ctor_pkg_name)) {
      fn_call <- call("::", as.symbol(ctor_pkg_name), as.symbol(ctor_fun_name))
      call_expr <- as.call(c(list(fn_call), args))
    } else {
      call_expr <- as.call(c(list(as.symbol(ctor_fun_name)), args))
    }
    test_block <- eval(call_expr)

    # Run through testServer
    result <- NULL
    server_args <- list(x = test_block)
    if (blockr.core::block_arity(test_block) > 0) {
      server_args$data <- list(data = function() data)
    }

    shiny::testServer(
      blockr.core::get_s3_method("block_server", test_block),
      { session$flushReact(); result <<- session$returned$result() },
      args = server_args
    )
    result
  }
}
```

This mode:
- Creates a fresh block from the constructor with the proposed args
- Runs it through `shiny::testServer` to get a real reactive evaluation
- Works outside of a running Shiny app (e.g. in tests or scripts)
- Does NOT update any existing block's state

### Shiny Mode (live in-app)

When `ai_ctrl_server` calls `discover_block_args`, it provides a custom
validator with rollback:

```r
# blockr.ai/R/ai-ctrl-block.R
eval_validator <- function(args) {
  # Save state for rollback on failure
  old <- lapply(ctrl_names, function(nm) shiny::isolate(vars[[nm]]()))
  names(old) <- ctrl_names
  for (nm in names(args)) {
    if (nm %in% ctrl_names) vars[[nm]](args[[nm]])
  }
  result <- try(
    shiny::isolate(blockr.core:::eval_impl(x, expr(), dat_snapshot)),
    silent = TRUE
  )
  if (inherits(result, "try-error")) {
    for (nm in ctrl_names) vars[[nm]](old[[nm]])
    stop(attr(result, "condition"))
  }
  result
}
```

This mode:
- Writes proposed args directly into the block's `reactiveVal` objects
- Evaluates using `isolate(expr())` which forces lazy recomputation
  (the 4 expression blocks return `expr = reactive(parse_*(...))`)
- On failure, **rolls back** all reactiveVals to previous state
- Works within a live Shiny session
- Updates the block's state in-place (changes are visible immediately
  when the gate opens)

## LLM Client Configuration

`llm_client()` in `blockr.ai/R/utils-llm.R` creates an ellmer chat client:

```r
llm_client <- function(
  model = blockr.core::blockr_option("ai_model", "gpt-4o-mini")
) {
  # Option 1: custom chat function (e.g. for Azure)
  chat_fns <- getOption("blockr.chat_function")
  if (!is.null(chat_fns) && model %in% names(chat_fns)) {
    return(chat_fns[[model]]())
  }

  # Option 2: default OpenAI-compatible endpoint
  ellmer::chat_openai(model = model)
}
```

### Configuration options

| Method | Setting | Example |
|---|---|---|
| Model name | `blockr.ai_model` option | `blockr.core::blockr_option("ai_model", "gpt-4o-mini")` |
| Custom chat factory | `blockr.chat_function` R option | `options(blockr.chat_function = list("gpt-4o" = my_azure_fn))` |
| OpenAI API key | `OPENAI_API_KEY` env var | Standard OpenAI setup |
| Azure endpoint | `AZURE_OPENAI_ENDPOINT` + `AZURE_OPENAI_API_KEY` env vars | Used by custom chat functions |
| Base URL override | `OPENAI_BASE_URL` env var | For OpenAI-compatible proxies |

### Custom chat function example (Azure)

```r
options(blockr.chat_function = list(
  "gpt-4o-mini" = function() {
    ellmer::chat_azure(
      endpoint = Sys.getenv("AZURE_OPENAI_ENDPOINT"),
      deployment_id = "gpt-4o-mini",
      api_version = "2024-08-01-preview",
      api_key = Sys.getenv("AZURE_OPENAI_API_KEY")
    )
  }
))
```

## Error Handling

### LLM errors

If `client$chat(msg)` throws, the error is caught and the loop breaks:

```r
response <- tryCatch(client$chat(msg), error = function(e) {
  last_error <<- paste0("LLM error: ", conditionMessage(e))
  NULL
})
if (is.null(response)) break
```

### JSON extraction failures

If `extract_json()` returns NULL:

```r
msg <- "No JSON found. Please return a JSON object like {\"param\": \"value\"}."
next
```

### JSON parse failures

If `jsonlite::fromJSON()` throws:

```r
msg <- paste0("Error: ", last_error)
next
```

### Validation failures

If the validator throws an error:

```r
msg <- paste0("Validation failed: ", last_error, "\nPlease fix.")
next
```

### Max iterations

If all `max_iter` iterations are exhausted without success, the function
returns with `success = FALSE` and the last error.

## Conversation Logging

When `verbose = TRUE`, the full conversation is recorded:

```r
result <- discover_block_args(
  prompt = "setosa only",
  block = new_filter_block(),
  data = iris,
  verbose = TRUE
)
print_conversation(result)
```

Output:

```
=== SYSTEM ===
You are configuring a Filter Rows (filter_block)...

=== USER ===
# Input Data
150 rows x 5 cols: ...
# Task
setosa only
Return JSON with parameter values.

=== ASSISTANT ===
```json
{"conditions": [{"column": "Species", "values": ["setosa"], "mode": "include"}]}
```

=== USER ===
Result:
```
  Sepal.Length Sepal.Width Petal.Length Petal.Width Species
1         5.1         3.5         1.4         0.2  setosa
2         4.9         3.0         1.4         0.2  setosa
3         4.7         3.2         1.3         0.2  setosa
```
Correct? Say DONE or fix.

=== ASSISTANT ===
DONE
```

## Typical Iteration Counts

| Scenario | Iterations | Notes |
|---|---|---|
| Simple filter | 2 | JSON + DONE |
| Wrong column name | 3 | JSON → error → fixed JSON + DONE |
| Complex multi-condition | 2-3 | JSON + DONE (or one refinement) |
| Ambiguous prompt | 3-4 | JSON → wrong result → refined JSON + DONE |
| Unresolvable | 5 | Exhausts max_iter, returns failure |

## Current Divergences from Target

1. **No streaming.** The LLM response is waited for in full before
   processing. Streaming would improve perceived responsiveness.

2. **Single-turn confirmation.** After the LLM sees the result preview,
   it either says DONE or fixes. There's no mechanism for the user to
   provide follow-up refinement within the same discover call (though
   they can send a new chat message which starts a new discover call).

3. ~~**No conversation memory across calls.**~~ **Resolved.** The
   `ai_ctrl_server` now creates a persistent `client` on first prompt
   and reuses it across subsequent chat messages. The `current_state`
   parameter passes the block's current parameter values so the LLM
   sees what's already configured.

## Related Specs

- [01-architecture.md](01-architecture.md) — How the validator integrates with the block server
- [02-block-requirements.md](02-block-requirements.md) — What blocks need for AI control
- [03-registry.md](03-registry.md) — How registry metadata feeds the system prompt
