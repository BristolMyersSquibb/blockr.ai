# AI Control: Block Requirements

> How to make a block AI-controllable. Step-by-step guide with code
> examples from existing implementations.

## Overview

For a block to be controllable via `ai_ctrl_block()`, it needs:

1. `external_ctrl` declared in the constructor
2. Bidirectional sync between reactiveVals and UI inputs
3. Registry metadata (`arguments`, `examples`) so the LLM knows what to produce

## The external_ctrl Parameter

Set in the block constructor call to `new_block()` / `new_data_block()` /
`new_transform_block()`:

### Option A: Character vector (specific params)

```r
# blockr.core/R/data-dataset.R
new_data_block(
  ...,
  external_ctrl = "dataset",   # only 'dataset' is controllable
  ...
)
```

Use this when only some constructor params should be externally settable.

### Option B: TRUE (all params)

```r
# blockr.dplyr/R/filter.R
new_transform_block(
  ...,
  external_ctrl = TRUE,   # all constructor params are controllable
  ...
)
```

Use this when every constructor parameter should be available.

### Option C: FALSE / omitted (default)

The block has no external control. The `ai_ctrl_ui` renders nothing, and
`ai_ctrl_server` returns a no-op `reactive(TRUE)`.

### How it resolves

`block_external_ctrl(x)` always returns a character vector:

| `external_ctrl` value | Result |
|---|---|
| `TRUE` | All constructor param names (via `block_ctor_inputs(x)`) |
| `"dataset"` | `c("dataset")` |
| `c("conditions", "preserve_order")` | `c("conditions", "preserve_order")` |
| `FALSE` or omitted | `character(0)` |

## Bidirectional Sync

When `external_ctrl` is enabled, the block's closure variables become
`reactiveVal` objects. The block server must handle both directions:

### UI → reactiveVal (user interacts with the block's own widgets)

```r
observeEvent(req(input$dataset), dataset(input$dataset))
```

### reactiveVal → UI (AI or external controller sets a new value)

```r
observeEvent(req(dataset()), {
  if (!identical(dataset(), input$dataset)) {
    updateSelectInput(session, "dataset",
      choices = list_datasets(package), selected = dataset())
  }
})
```

The `!identical()` guard prevents infinite observer loops.

### Derived internal state

If a block has internal state derived from a constructor param (e.g.
`r_use_prop <- reactiveVal(!is.null(r_prop()))` in slice_block), the
reverse sync observer for that param must also update the derived state.
Otherwise, external_ctrl sets the param but the block still behaves as
if the old derived value is active.

Note: the canonical dataset_block doesn't need this pattern (it has a
simple 1:1 mapping: one param → one input, with an `!identical()` guard).
Derived state sync arises in more complex blocks where one param affects
multiple UI elements or internal flags.

Two guard patterns:

1. **Direct sync** (dataset_block style): `!identical(val, input)` —
   prevents loops when the value already matches the UI.
2. **State-based guard** (slice_block style): `!is.null(val) && !derived_state()` —
   checks whether derived state needs updating, not just value equality.

```r
# slice_block: when AI sets prop = 0.05, also switch to prop mode
# (from blockr.dplyr/R/slice.R lines 186-199)
observeEvent(r_prop(), {
  prop_val <- r_prop()
  if (!is.null(prop_val) && !r_use_prop()) {
    r_use_prop(TRUE)
    updateCheckboxInput(session, "use_prop", value = TRUE)
    updateNumericInput(session, "n",
      min = 0, max = 1, step = 0.1, value = prop_val
    )
    shinyjs::html("n_label", "Proportion (0 to 1)")
  } else if (!is.null(prop_val) && r_use_prop() &&
             !identical(input$n, prop_val)) {
    updateNumericInput(session, "n", value = prop_val)
  }
}, ignoreInit = TRUE)
```

### Reference: dataset_block

```r
# blockr.core/R/data-dataset.R (simplified)
new_data_block(
  function(id) {
    moduleServer(id, function(input, output, session) {
      # UI → state
      observeEvent(req(input$dataset), dataset(input$dataset))

      # state → UI (for external updates)
      observeEvent(req(dataset()), {
        if (!identical(dataset(), input$dataset)) {
          updateSelectInput(session, "dataset",
            choices = list_datasets(package), selected = dataset())
        }
      })

      reactive(
        eval(bquote(
          as.call(c(as.symbol("::"), quote(.(pkg)), quote(.(dat)))),
          list(pkg = as.name(package), dat = as.name(dataset()))
        ))
      )
    })
  },
  function(id) {
    selectInput(NS(id, "dataset"), "Dataset",
      choices = list_datasets(package), selected = dataset)
  },
  class = "dataset_block",
  external_ctrl = "dataset"
)
```

### Reference: filter_block

```r
# blockr.dplyr/R/filter.R (simplified)
new_transform_block(
  function(id, data) {
    moduleServer(id, function(input, output, session) {
      # conditions and preserve_order are reactiveVals
      # (injected by external_ctrl mechanism)
      mod_value_filter_server(
        id = "vf", conditions = conditions,
        get_data = data, preserve_order = preserve_order
      )

      r_expr <- reactive({
        parse_value_filter(conditions(), preserve_order = preserve_order())
      })

      list(
        expr = r_expr,
        state = list(
          conditions = conditions,
          preserve_order = preserve_order
        )
      )
    })
  },
  function(id) { ... },
  class = "filter_block",
  external_ctrl = TRUE   # both 'conditions' and 'preserve_order'
)
```

The filter_block delegates bidirectional sync to `mod_value_filter_server`,
which handles the `conditions` ↔ UI sync internally.

### Reference: crossfilter_block (internal reactiveVals + format translation)

The crossfilter block reveals two patterns not covered by the simpler
`dataset_block` / `filter_block` examples:

**Pattern 1: `as_rv()` — reuse injected reactiveVals**

When a block's server creates its own reactiveVals from constructor args
(e.g. `shiny::reactiveVal(filters)`), and `external_ctrl` injects a
reactiveVal for `filters`, you get a reactiveVal wrapping a reactiveVal.
The `as_rv()` helper detects and reuses injected reactiveVals:

```r
# blockr.dm/R/dm-crossfilter-block.R (dm_crossfilter_server_factory)
as_rv <- function(x, default = x) {
  if (inherits(x, "reactiveVal")) x else shiny::reactiveVal(default)
}
r_active_dims <- as_rv(active_dims)
r_filters <- as_rv(filters)
```

Any block that creates internal reactiveVals from constructor args needs
this pattern. Consider moving `as_rv()` to blockr.core as a utility.

**Pattern 2: format translation with bidirectional sync**

The crossfilter_block stores filters in flat format
(`list(Species = "setosa")`) but the dm engine needs per-table format
(`list(.tbl = list(Species = "setosa"))`). This requires a second level
of sync — flat↔per-table — with its own `observeEvent` pairs:

```r
# blockr.dm/R/crossfilter-block.R (server function)
# Flat → per-table (AI sets flat filters → dm engine gets per-table)
shiny::observeEvent(filters(), {
  val <- if (length(filters()) > 0) list(.tbl = filters()) else list()
  if (!identical(dm_rv_filters(), val)) dm_rv_filters(val)
})
# Per-table → flat (user UI changes → flat reactiveVals)
shiny::observeEvent(dm_rv_filters(), {
  flat <- dm_rv_filters()[[".tbl"]] %||% list()
  if (!identical(filters(), flat)) filters(flat)
})
```

**Pattern 3: move server-side setup into the server function**

The `crossfilter_block` originally created `dm_server` at construction
time (before `external_ctrl` injection). This had to be moved into the
server function body so it runs after injection and can detect/use the
injected reactiveVals.

### Return value

Blocks with `external_ctrl` must return a **list** from their server
function:

```r
list(
  expr = r_expr,       # reactive returning the block expression
  state = list(        # named list of reactiveVals
    conditions = conditions,
    preserve_order = preserve_order
  )
)
```

**Important:** `expr` must be a `reactive()` (lazy computation), not a
`reactiveVal`. When the eval_validator calls `isolate(expr())`,
a `reactive()` forces recomputation from its current dependencies
(fresh value), whereas a `reactiveVal` just reads whatever was last
set by an observer (stale if the observer hasn't fired yet).

```r
# CORRECT: reactive recomputes from current state
expr = reactive(parse_filter_expr(r_exprs_rv()))

# WRONG: reactiveVal is only updated when an observer fires
expr = r_expr_validated  # a reactiveVal
```

If `state` is not returned, `expr_server.block()` will construct it
automatically from the injected reactiveVals. But explicitly returning
it is recommended for clarity.

## Registry Metadata

For the LLM to produce correct JSON, the block needs `arguments` and
`examples` in its registry entry. See [03-registry.md](03-registry.md)
for full details.

### arguments

A named character vector describing each parameter:

```r
arguments = c(
  conditions = paste0(
    "List of filter conditions, each with: ",
    "column (string), values (array of strings, even for numbers), ",
    "mode (\"include\" or \"exclude\")"
  ),
  preserve_order = "Boolean, whether to preserve selection order"
)
```

### examples

A string with example JSON that the LLM uses as a template:

```r
examples = paste0(
  'Include: {"conditions": [{"column": "Species", ',
  '"values": ["setosa"], "mode": "include"}]}\n',
  'Exclude: {"conditions": [{"column": "Species", ',
  '"values": ["setosa"], "mode": "exclude"}]}'
)
```

## Checklist for Block Authors

- [ ] Set `external_ctrl` in the constructor (`TRUE` or character vector)
- [ ] Implement bidirectional sync: input → reactiveVal AND reactiveVal → updateInput
- [ ] If the block creates its own reactiveVals from constructor args, use `as_rv()` to detect and reuse injected reactiveVals (see crossfilter_block reference)
- [ ] If the block's internal format differs from its external API, add format translation sync with `!identical` guards (see crossfilter_block reference)
- [ ] If server-side setup depends on constructor args, move it into the server function body (runs after injection)
- [ ] Ensure the server returns `list(expr = ..., state = ...)` (or just `expr` if state auto-detection is acceptable)
- [ ] Use `register_block()` / `register_blocks()` with:
  - [ ] `arguments`: named character vector describing each parameter
  - [ ] `examples`: example JSON string showing valid parameter values
- [ ] Registry `arguments` documents ALL constructor params visible to the LLM
      (audit with `block_ctor_inputs()` — this matches what `build_system_prompt()` uses;
      note: only `block_external_ctrl()` params are settable in live Shiny mode)
- [ ] Write `test-<block>-external-ctrl.R` with testServer + mock ctrl_block (see [06-debugging.md](06-debugging.md))
- [ ] If internal state is derived from constructor params, reverse sync updates derived state too
- [ ] Test standalone: `discover_block_args(prompt, block, data)` should succeed
- [ ] Test in Shiny: serve a board with `ai_ctrl_block()` plugin and verify:
  - AI can set parameters via chat
  - Block UI updates to reflect AI-set values
  - User can still interact with block UI normally after AI update

## Current Divergences from Target

1. **`block_supports_external_ctrl()` bug:** Always returns `TRUE` due to
   missing `(x)` in `length(block_external_ctrl) > 0L`. Env cloning
   happens for all blocks. Harmless in practice but should be fixed.

2. **Most blockr.dplyr blocks now have `external_ctrl = TRUE`** (per
   commit 433b16a). `external_ctrl = TRUE` is the standard pattern for
   blocks where all constructor params should be controllable.
   `dataset_block`'s `external_ctrl = "dataset"` is the exception (only
   one of its params is externally settable). Main remaining risk is
   incomplete coverage *within* a block — e.g. slice_block's `prop` param
   was missing reverse sync for derived state `r_use_prop`.

3. **Most blocks now provide registry metadata** (per 433b16a). Main
   remaining risk is incomplete `arguments` within a block — e.g.
   slice_block was missing a description for `rows`. Audit with
   `block_ctor_inputs()` (see [03-registry.md](03-registry.md)).

## Related Specs

- [01-architecture.md](01-architecture.md) — How external_ctrl is implemented in blockr.core
- [03-registry.md](03-registry.md) — Registry metadata for LLM context
- [04-discover.md](04-discover.md) — How the LLM uses arguments/examples
