# The Discovery Process

What happens when a user types a prompt in the AI chat -- from natural
language to configured block. The harness is **ellmer tool calling**;
there is no longer a hand-rolled JSON / "DONE or fix" loop (removed June
2026 -- see [harness-comparison.md](harness-comparison.md)).

## The Big Picture

```
User: "only setosa"
  |
  v
discover_block_args()  ->  discover_via_ellmer_tools()
  |
  +-- Build system prompt (block identity, params, registry prompt/examples,
  |     behavioural rules) and user message (data preview + current config + task)
  +-- Register two tools on the ellmer client and call client$chat() ONCE:
  |     - data_tool       : run read-only R against the input data (capped)
  |     - validate_config : apply a config; returns {ok, effect, preview} or {error}
  |
  +-- ellmer drives the tool loop:
  |     explore with data_tool -> propose with validate_config -> read the
  |     effect -> retry on error or wrong effect -> stop when it matches
  |
  v
Result: {success, args, result, message, error, question, client}
```

The model proposes a configuration **by calling `validate_config`**, not by
emitting JSON text. The last successful `validate_config` call is the applied
configuration -- in a live board its `validate` function writes the block's
reactiveVals, so the block updates in place.

## The two tools

| Tool | Kind | What it does |
|---|---|---|
| `data_tool` | read-only | Runs arbitrary R against the input datasets (by name) to inspect columns, types, value ranges, unique levels. Capped at `max_data_probes` (default 8). Built by `new_data_tool()` (`R/tool-data.R`). |
| `validate_config` | apply + verify | Takes the block's parameters as a JSON object (a `config` string), validates/applies them, and returns `{ok, effect, preview}` or `{ok:false, error}`. Built by `new_validate_tool()` (`R/harness-ellmer.R`). |

`validate_config` does two things beyond "is it valid":

- **Effect, not just validity.** A config can be valid yet do nothing (a filter
  that removes no rows, a transform that adds no column). `validate_config`
  returns the *effect* via `data_effect()` (`R/effect.R`) -- e.g.
  `rows: 32 -> 32 (UNCHANGED)` or `columns added: ratio`, and a per-table diff
  for `dm` results. The prompt tells the model `ok=true` means *valid, not
  correct* -- it must check the effect matches the request before finishing.
- **Unknown-key rejection.** Keys the block can't consume are rejected (instead
  of silently dropped), so a save-format leak (`{state:{...}}`) errors and the
  model retries with the right shape. `block_name` (the title) is allowed.

## What the LLM sees

### System prompt (`build_tool_system_prompt`)

Built from the block's **registry metadata**:

1. **Block identity** -- "You are configuring a Filter Rows (filter_block)."
2. **Parameter names/descriptions** from the `arguments` registry field.
3. **Block-specific guidance** from the `prompt` attribute.
4. **Tool usage + behaviour rules** -- when to explore vs apply; that `ok=true`
   is valid-not-done; ask one clarifying question on vague prompts; don't force
   an invalid config; only set what was asked.

`validate_config`'s own description carries the per-block parameter docs and an
example, so the model knows the config shape.

### User message

- **Data preview**: `data_schema()` -- dimensions, column types, 5 sample rows,
  per-column value summaries. Methods exist for data.frame, `dm`, ggplot, and
  (via blockr.sandbox) gt/flextable/composer tables. Packages can add methods.
- **Current configuration** (if any) as JSON, minus `block_name`.
- **The task**: the user's prompt.

Images: an optional `images` list is sent with the first message for
vision-capable models.

## Validation

The `validate_config` tool wraps a `validate` function:

- **Standalone** (`validate = NULL`): builds a fresh block with the proposed args
  and evaluates it via `shiny::testServer`. Used in tests and scripting.
- **Shiny** (live app): `ai_ctrl_server` passes a validator that writes the
  block's `reactiveVal`s and rolls back on failure. So the last successful
  `validate_config` *is* the apply, and the existing block UI stays in sync.

## Conversation memory

The returned `client` is the ellmer chat client with full history. Pass it to
subsequent calls to retain context:

```r
r1 <- discover_block_args("use iris", new_dataset_block())
r2 <- discover_block_args("now mtcars", new_dataset_block(), client = r1$client)
```

In Shiny, `ai_ctrl_server` keeps a persistent client across messages; "Clear"
resets it.

## Outcomes

| Situation | Result |
|---|---|
| `validate_config` succeeded | `success = TRUE`, `args`, `result`, `message` (the model's reply) |
| Model asked a clarifying question (no config) | `success = FALSE`, `question` set, `error = NULL` |
| Model produced nothing usable | `success = FALSE`, `error` set |
| LLM/transport error | `success = FALSE`, `error` set |

## LLM configuration

| Setting | How |
|---|---|
| Model | `blockr.ai_model` option / `BLOCKR_AI_MODEL` env var |
| Custom provider | `options(blockr.chat_function = list("model" = function() ellmer::chat_*(...)))` |
| API key | provider env var (e.g. `OPENAI_API_KEY`) |

## Source files

| File | Key contents |
|---|---|
| `R/discover.R` | `discover_block_args()` (thin wrapper) + standalone validator, `simplify_leaves`, `block_ctor_inputs` |
| `R/harness-ellmer.R` | `discover_via_ellmer_tools()`, `new_validate_tool()`, `build_tool_system_prompt()` |
| `R/harness-tools.R` | `build_harness_tools()` -- the shared data + validate tools |
| `R/effect.R` | `data_effect()` -- the config-effect (rows/cols/per-table diff) |
| `R/tool-data.R` | `new_data_tool()` -- read-only data exploration |
| `R/utils-llm.R` | `data_schema()`, `data_preview()`, `llm_client()` |
| `R/ai-ctrl-block.R` | `ai_ctrl_block()` plugin (Shiny integration) |

## See Also

- [architecture.md](architecture.md) -- how blockr.ai plugs into blockr.core
- [harness-comparison.md](harness-comparison.md) -- why the harness is ellmer
- [external-ctrl-guide.md](external-ctrl-guide.md) -- writing registry metadata
- [debugging.md](debugging.md) -- when discovery doesn't work
