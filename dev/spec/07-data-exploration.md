# Data Exploration Backends

> How the LLM inspects input data before answering. Covers the three
> built-in backends, configuration, tuning, and custom backends.

## What It Does

When `discover_block_args()` runs, the LLM sees a 5-row preview of the
input data. For many tasks (mutate expressions, simple filters) this is
enough. But when the task depends on values the preview doesn't show —
unique factor levels, computed aggregates, column formats — the LLM
needs to run R code against the full dataset.

Data exploration backends provide this capability. The LLM can execute
small R snippets ("probes") and see the results before committing to a
JSON answer.

## Three Backends

| Backend | Mechanism | When to use |
|---------|-----------|-------------|
| `none` | No exploration. LLM sees only the 5-row preview. | Simple tasks where the preview suffices. Default. |
| `manual` | LLM writes a `` ```data_query `` code block. blockr.ai extracts and runs it, then sends the result back as a follow-up message. Each probe is one extra LLM round-trip. | Recommended for strong API models (gpt-4o-mini, gpt-4o). Fastest, visible probe trail. |
| `tools` | LLM calls `data_tool` via ellmer's native tool-use API. Execution happens inside the tool callback. | Recommended for local/open-source models where text-based probing fails. |

### How each backend works

**manual**: The LLM's system prompt includes an exploration preamble
encouraging it to probe. When the LLM responds with a fenced
`` ```data_query `` block, `process()` extracts the code, executes it in
a sandboxed environment containing the input data, and returns the
captured output as a user message. The LLM then incorporates the result
into its JSON answer.

**tools**: `setup()` registers an ellmer tool (`data_tool`) on the chat
client. The LLM invokes it like any native tool call. The tool callback
executes the R code and returns the result. No manual response parsing
is needed.

**none**: Both `setup()` and `process()` return NULL. No exploration
prompt is added.

## Configuration

Three ways to set the backend, in order of precedence:

### 1. Per-call parameter

```r
discover_block_args(
  prompt = "only gmail users",
  block  = new_filter_block(),
  data   = users,
  data_exploration = "manual"
)
```

### 2. R option (takes precedence over per-call default)

```r
options(blockr.data_exploration = "manual")
```

### 3. Environment variable (takes precedence over R option)

```bash
export BLOCKR_DATA_EXPLORATION=manual
```

All three feed through `blockr_option()` from blockr.core, which checks
the env var first, then the R option, then the default.

In a Shiny app, the simplest approach is the env var in `.Renviron`:

```
BLOCKR_DATA_EXPLORATION=manual
```

## Tuning Probes

Each backend limits how many probes the LLM can run per
`discover_block_args()` call.

| Setting | Default |
|---------|---------|
| `BLOCKR_MAX_DATA_PROBES` (env var) | 3 |
| `blockr.max_data_probes` (R option) | 3 |

```r
# Allow up to 5 probes per call
options(blockr.max_data_probes = 5L)

# Or via env var
Sys.setenv(BLOCKR_MAX_DATA_PROBES = "5")
```

When the limit is reached, the backend tells the LLM to provide its
JSON answer with whatever information it has gathered so far.

## Which Backend to Use

**Use `manual` (recommended default)**. Benchmarks on gpt-4o-mini show:

- 54% correctness vs 49% for tools (not statistically significant)
- 1.68x faster on aggregate
- Probe round-trips visible in the conversation for debugging
- Probe rates identical between backends (0.7 avg)

**Use `tools` for local/open-source models**. Benchmarks on Qwen-2.5
20B showed text-based exploration failing entirely (25%, same as `none`),
while tools reached 50%. Weaker models don't understand the
`` ```data_query `` convention but do recognise native tool calls.

**Use `none` when exploration isn't needed** — e.g. mutate blocks where
the 5-row preview provides enough context (100% accuracy without probes
in benchmarks).

See `blockr.ai/dev/benchmark-summary.md` for the full benchmark results.

## Custom Backends

A backend is any list with three functions:

```r
my_backend <- list(
  setup = function(client, data) {
    # Called once when discover_block_args() starts.
    # client: ellmer chat client (can register tools, modify prompts)
    # data: input data (data.frame, dm, named list, or NULL)
    # Return: character string to append to system prompt, or NULL
  },

  process = function(response, data) {
    # Called after each LLM response during the discovery loop.
    # response: LLM's response text
    # data: same input data
    # Return: follow-up prompt string (if the backend consumed the
    #         response), or NULL to continue to JSON extraction
  },

  probes_used = function() {
    # Return: integer count of probes executed, or NA_integer_
  }
)
```

Pass it directly instead of a string:

```r
discover_block_args(
  prompt = "...",
  block  = new_filter_block(),
  data   = df,
  data_exploration = my_backend
)
```

`data_exploration_backend()` in `backend-data.R` accepts either a string
(`"none"`, `"manual"`, `"tools"`) or a list implementing this interface.

## Source Files

| File | Contents |
|------|----------|
| `blockr.ai/R/backend-data.R` | Backend constructors, `data_exploration_preamble()`, `execute_data_query()`, code extraction |
| `blockr.ai/R/tool-data.R` | `new_data_tool()` — the ellmer tool for the tools backend |
| `blockr.ai/R/discover.R` | Integration point: `discover_block_args()` calls `setup()`, `process()`, `probes_used()` |
| `blockr.core/R/utils-misc.R` | `blockr_option()` — env var / R option resolution |

## Related Specs

- [04-discover.md](04-discover.md) — The discover_block_args loop (JSON extraction, validation, confirmation)
- [03-registry.md](03-registry.md) — How registry metadata feeds the system prompt
