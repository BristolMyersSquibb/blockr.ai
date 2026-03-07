# The Discovery Process

What happens when a user types a prompt in the AI chat -- from natural
language to configured block.

## The Big Picture

```
User: "only setosa"
  |
  v
discover_block_args()
  |
  +-- Build system prompt (block type, parameters, examples from registry)
  +-- Build user message (data preview + task)
  |
  +-- Loop (up to max_iter = 5):
  |     |
  |     +-- Send to LLM
  |     +-- LLM wants to explore data? -> run R code, send result back
  |     +-- LLM returns JSON? -> validate by applying to block
  |     |     +-- Error? -> send error back, retry
  |     |     +-- Success? -> show result preview, ask "DONE or fix?"
  |     +-- LLM says "DONE"? -> break
  |     +-- LLM asks a question? -> return question to caller
  |
  v
Result: {success, args, result, client}
```

A typical successful run takes **2 iterations**: the LLM proposes JSON,
validation succeeds, the LLM sees the result and says DONE.

## What the LLM Sees

### System prompt

Built automatically from the block's **registry metadata**:

1. **Block identity**: "You are configuring a Filter Rows (filter_block)."
2. **Parameter names and descriptions** from the `arguments` registry field
3. **Block-specific guidance** from the `prompt` attribute (e.g. "values must be strings")
4. **Example JSON** from the `examples` attribute
5. **Behavioral rules** (ask back on vague prompts, explain before JSON, etc.)

The quality of registry metadata directly determines how well the LLM
performs. See [external-ctrl-guide.md](external-ctrl-guide.md) for how
to write good `arguments` and `examples`.

### User message

The first message includes:

- **Data preview**: dimensions, column types, 5 sample rows, per-column
  value summaries (unique values or ranges)
- **Current configuration** (if any): the block's current parameter
  values as JSON, so the LLM can build on them
- **The task**: the user's prompt

## Validation

Two modes depending on context:

- **Standalone** (`validate = NULL`): creates a fresh block with the
  proposed args and evaluates it via `shiny::testServer`. Used in tests
  and scripts.
- **Shiny** (live app): writes args into the block's `reactiveVal`
  objects, evaluates, and rolls back on failure. Used by
  `ai_ctrl_server`.

## Data Exploration

The LLM sees a 5-row preview by default. When the task requires
information not in the preview (unique factor levels, computed
aggregates, date formats), the LLM can run R code against the full
dataset.

| Backend | How it works | When to use |
|---------|-------------|-------------|
| `none` | No exploration | Simple tasks where the preview suffices |
| `manual` | LLM writes `` ```data_query `` code blocks, blockr.ai runs them | Recommended for API models. Fastest. |
| `tools` | LLM uses ellmer tool calling | Recommended for local/open-source models |

Configure via (in order of precedence):

```r
discover_block_args(..., data_exploration = "manual")  # per-call
options(blockr.data_exploration = "manual")             # R option
# export BLOCKR_DATA_EXPLORATION=manual                 # env var
```

Probes are limited per call (default 3, set via `BLOCKR_MAX_DATA_PROBES`
or `blockr.max_data_probes`).

See [benchmark-summary.md](benchmark-summary.md) for backend comparison.

### Custom backends

Any list with `setup(client, data)`, `process(response, data)`, and
`probes_used()` can be passed as `data_exploration`.

## Conversation Memory

The `client` field in the return value is the ellmer chat client with
full conversation history. Pass it to subsequent calls to retain context:

```r
r1 <- discover_block_args("use iris", new_dataset_block())
r2 <- discover_block_args("now mtcars", new_dataset_block(), client = r1$client)
```

In Shiny, `ai_ctrl_server` keeps a persistent client across chat
messages automatically. The "Clear" link resets it.

## LLM Configuration

| Setting | How |
|---|---|
| Model | `blockr.ai_model` option or `BLOCKR_AI_MODEL` env var (default: `gpt-4o-mini`) |
| Custom provider | `options(blockr.chat_function = list("model-name" = function() ellmer::chat_azure(...)))` |
| API key | `OPENAI_API_KEY` env var (or provider-specific vars) |

## Error Handling

| Situation | What happens |
|---|---|
| LLM error | Loop breaks, returns failure |
| No JSON in response | Treated as a clarifying question, returned to caller |
| Invalid JSON | Error sent back to LLM, retries |
| Validation failure | Error sent back to LLM with "Please fix" |
| Max iterations hit | Returns `success = FALSE` with last error |

## Source Files

| File | Key contents |
|------|----------|
| `R/discover.R` | `discover_block_args()`, standalone validator |
| `R/utils-llm.R` | `build_system_prompt()`, `extract_json()`, `data_preview()` |
| `R/backend-data.R` | Data exploration backends |
| `R/reporter.R` | Progress reporters (silent, console, shiny) |
| `R/ai-ctrl-block.R` | `ai_ctrl_block()` plugin (Shiny integration) |

## See Also

- [architecture.md](architecture.md) -- How blockr.ai plugs into blockr.core
- [external-ctrl-guide.md](external-ctrl-guide.md) -- Writing registry metadata for blocks
- [debugging.md](debugging.md) -- When discovery doesn't work
- [benchmark-summary.md](benchmark-summary.md) -- Data exploration benchmark results
