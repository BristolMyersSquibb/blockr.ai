# AI Control: Registry and LLM Context

> How block metadata is stored in the registry and assembled into LLM
> prompts by blockr.ai.

## The Block Registry

blockr.core maintains a global `block_registry` environment. Each entry
maps a block class name (UID) to a `block_registry_entry` object with
metadata.

### Registration

```r
# blockr.core/R/block-registry.R
register_block <- function(ctor, name, description, classes = NULL,
                           uid = NULL, category = NULL, icon = NULL,
                           arguments = NULL,
                           package = NULL, overwrite = FALSE)
```

Key AI-relevant field:

| Field | Type | Purpose |
|---|---|---|
| `arguments` | named character vector (with `structure()` attributes) or NULL | Parameter descriptions for LLM prompt. Vector-level `examples` attribute provides R-native example values; optional `prompt` attribute adds block-specific guidance. |

### Auto-detection of arguments

If `arguments` is `NULL` at registration time, `register_block()` falls
back to `block_external_ctrl(obj)` — the character vector of
external_ctrl parameter names. This gives the LLM parameter *names* but
no *descriptions*.

```r
# blockr.core/R/block-registry.R (lines 118-133)
if (is.null(classes) || is.null(arguments)) {
  # ... instantiate block ...
  if (is.null(arguments)) {
    arguments <- block_external_ctrl(obj)
  }
}
```

### Batch registration

```r
# blockr.dplyr/R/registry.R (excerpt)
register_blocks(
  c("new_filter_block", ...),
  name = c("Filter Rows", ...),
  description = c("Keep only rows that match selected values...", ...),
  arguments = list(
    ...,
    # filter_block:
    structure(
      c(
        conditions = paste0(
          "List of filter conditions, each with: ",
          "column (string), values (array of strings, even for numbers), ",
          "mode (\"include\" or \"exclude\")"
        ),
        preserve_order = "Boolean, whether to preserve selection order"
      ),
      examples = list(
        conditions = list(
          list(column = "Species", values = list("setosa"), mode = "include")
        ),
        preserve_order = FALSE
      ),
      prompt = "The values array must always contain strings, even for numeric columns."
    ),
    ...
  ),
  package = "blockr.dplyr",
  overwrite = TRUE
)
```

### Reading metadata

```r
# blockr.core/R/block-registry.R
registry_metadata(blocks, fields)
```

Returns a data frame (multiple blocks/fields) or a single value (one
block, one field). blockr.ai uses this to fetch `arguments` for the
system prompt.

## How blockr.ai Builds the System Prompt

`build_system_prompt()` in `blockr.ai/R/utils-llm.R` assembles context
from multiple sources:

```r
# blockr.ai/R/utils-llm.R
build_system_prompt <- function(var_names, block) {
  block_name <- class(block)[1]

  # 1. Block identity and description from registry
  reg_info <- get_block_registry_info(block_name)

  # 2. Raw parameter docs (with vector-level attributes) from registry
  param_docs_raw <- get_block_param_docs_raw(block_name)

  # 3. Example JSON from R-native examples attribute
  example <- generate_example_json(param_docs_raw)

  # 4. Block-specific prompt from prompt attribute
  block_prompt <- attr(param_docs_raw, "prompt")

  paste0(
    block_context,                    # "You are configuring a Filter Rows (filter_block)."
    "Return JSON with parameter values.\n\n",
    "Parameters: ", paste(var_names, collapse = ", "), "\n\n",
    param_text,                       # "conditions: List of filter conditions..."
    block_prompt_text,                # "The values array must always contain strings..."
    example_text,                     # "Example:\n```json\n{...}\n```"
    "After seeing the result, respond with just DONE if correct, or provide fixed JSON."
  )
}
```

### Arguments Structure

Arguments use `structure()` on a named character vector with two
optional vector-level attributes:

- **`examples`**: Named list of R values, converted to JSON by
  `generate_example_json()` via `jsonlite::toJSON(auto_unbox = TRUE, null = "null")`.
- **`prompt`**: Block-specific guidance text injected between parameter
  docs and the example JSON.

```r
structure(
  c(
    columns = "Array of column names",
    exclude = "If true, exclude listed columns",
    distinct = "If true, keep only distinct rows"
  ),
  examples = list(
    columns = list("mpg", "cyl"),
    exclude = FALSE,
    distinct = FALSE
  )
)
# generate_example_json() produces:
# {"columns":["mpg","cyl"],"exclude":false,"distinct":false}
```

R-native example values map to JSON naturally:

| R value | JSON output |
|---|---|
| `"text"` | `"text"` (scalar string) |
| `list("a", "b")` | `["a", "b"]` (array — use for single-element arrays too) |
| `TRUE` / `FALSE` | `true` / `false` |
| `10L` or `10` | `10` |
| `NULL` | `null` |
| `list(a = 1, b = 2)` | `{"a": 1, "b": 2}` (named list → object) |
| `list()` | `[]` (empty array) |

### System Prompt Assembly

The prompt is built from five pieces:

#### 1. Block context (from registry `name` + `description`)

```
You are configuring a Filter Rows (filter_block).
Keep only rows that match selected values. No coding required. (dplyr: filter)
```

Fetched via `get_block_registry_info()` which reads `name` and
`description` attributes from the registry entry.

#### 2. Parameter list

```
Parameters: conditions, preserve_order
```

Always present — derived from `block_ctor_inputs()`.

#### 3. Parameter documentation (from registry `arguments`)

```
conditions: List of filter conditions, each with: column (string), values (array of strings, even for numbers), mode ("include" or "exclude")
preserve_order: Boolean, whether to preserve selection order
```

Fetched via `get_block_param_docs_raw()` →
`registry_metadata(block_name, "arguments")`.

**If `arguments` is not provided at registration**, this section is
omitted and the LLM only sees parameter names.

#### 4. Block-specific prompt (from `prompt` attribute)

```
The values array must always contain strings, even for numeric columns (e.g. ["4"] not [4]). The operator field connects a condition to the previous one.
```

Optional. Injected between parameter docs and the example JSON.
Use for cross-parameter guidance that doesn't belong in any single
parameter's description.

#### 5. Example JSON (from `examples` attribute)

```
Example:
```json
{"conditions":[{"column":"Species","values":["setosa"],"mode":"include"}],"preserve_order":false}
```

Generated by `generate_example_json()` from the R-native `examples`
attribute on the arguments vector, converted via `jsonlite::toJSON()`.

**If no `examples` attribute is present**, a fallback is generated:

```
Return JSON like: {"conditions": <value>}
```

### Full Prompt Example (filter_block)

```
You are configuring a Filter Rows (filter_block).
Keep only rows that match selected values. No coding required. (dplyr: filter)

Return JSON with parameter values.

Parameters: conditions, preserve_order

conditions: List of filter conditions, each with: column (string), values (array of strings, even for numbers), mode ("include" or "exclude"), operator ("|" or "&", ...)
preserve_order: Boolean, whether to preserve selection order

The values array must always contain strings, even for numeric columns (e.g. ["4"] not [4]). The operator field connects a condition to the previous one.

Example:
```json
{"conditions":[{"column":"Species","values":["setosa"],"mode":"include"}],"preserve_order":false}
```

After seeing the result, respond with just DONE if correct, or provide fixed JSON.
```

## Data Preview (User Message)

The data context is not in the system prompt. It is prepended to the
first user message by `data_preview()`:

```r
# blockr.ai/R/utils-llm.R
msg <- paste0(
  data_preview(data),       # "# Input Data\n\n150 rows x 5 cols: ..."
  "# Task\n\n", prompt,     # "# Task\n\nsetosa only"
  "\n\nReturn JSON with parameter values."
)
```

`data_preview()` handles multiple input types:

| Input type | Preview format |
|---|---|
| `NULL` | Empty string (source blocks) |
| `data.frame` | `"150 rows x 5 cols: Sepal.Length (numeric), ..."` |
| `dm` | Per-table preview: `"dm object with N tables:\n## tbl1\n..."` |
| Named list | Per-item preview |

### Full User Message Example

```
# Input Data

150 rows x 5 cols: Sepal.Length (numeric), Sepal.Width (numeric), Petal.Length (numeric), Petal.Width (numeric), Species (factor)

# Task

setosa only

Return JSON with parameter values.
```

## Target: What Metadata Should Be Provided

For optimal AI control, every block registration should include:

| Field | Required? | Notes |
|---|---|---|
| `name` | Yes | Human-readable block name |
| `description` | Yes | What the block does, including the underlying R function |
| `arguments` | Yes (for AI) | Named character vector wrapped in `structure()`. Descriptions as values; `examples` attr with R-native list; optional `prompt` attr for block-specific guidance. |

### Good arguments example

```r
arguments = structure(
  c(
    conditions = paste0(
      "List of filter conditions, each with: ",
      "column (string), values (array of strings, even for numbers), ",
      "mode (\"include\" or \"exclude\")"
    ),
    preserve_order = "Boolean, whether to preserve selection order"
  ),
  examples = list(
    conditions = list(
      list(column = "Species", values = list("setosa"), mode = "include")
    ),
    preserve_order = FALSE
  ),
  prompt = "The values array must always contain strings, even for numeric columns."
)
```

### Completeness rule

`arguments` must document every param returned by `block_ctor_inputs(block)`.
Both `build_system_prompt()` and `discover_block_args()` use
`block_ctor_inputs()` for the LLM prompt's parameter list, so
undocumented params appear as bare names with no description — the LLM
is unlikely to set them correctly even if the user explicitly asks.

For blocks with `external_ctrl = TRUE` (all blockr.dplyr blocks), this
equals `block_external_ctrl()`. For blocks with specific `external_ctrl`
(e.g. dataset_block's `"dataset"`), `block_ctor_inputs()` may include
non-controllable params (like `package`) — documenting these is still
recommended since the LLM sees them, but only `block_external_ctrl()`
params are settable in live Shiny mode.

Audit with:

```r
block <- new_slice_block()
registered <- registry_metadata("slice_block", "arguments")
setdiff(block_ctor_inputs(block), names(registered))
# character(0) means complete
# e.g. slice_block was missing "rows" before fix
```

## Current Divergences from Target

1. **Most blockr.dplyr blocks now provide arguments with examples.**
   Main remaining risk is incomplete coverage *within* a block — e.g.
   slice_block's `rows` param was missing from registry.
   Audit with `block_ctor_inputs()` (see Completeness rule above).

2. **dataset_block has no explicit arguments.** It relies on the
   auto-detection fallback (`block_external_ctrl(obj)` → `c("dataset")`),
   which gives the LLM only the parameter name, not a description.

3. **`registry_metadata` unwrapping.** `get_block_param_docs_raw()` in
   blockr.ai must unwrap a `list(value)` wrapper from
   `registry_metadata()` when querying a single block + single field.
   This is handled but adds fragility.

## Related Specs

- [00-overview.md](00-overview.md) — Scope and supported blocks
- [02-block-requirements.md](02-block-requirements.md) — Full checklist for block authors
- [04-discover.md](04-discover.md) — How the prompt is used in the LLM loop
