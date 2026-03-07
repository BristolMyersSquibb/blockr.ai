# AI Control: Architecture

> How blockr.core's plugin system enables AI control and how blockr.ai
> plugs into it.

## The Plugin System

blockr.core has a plugin mechanism for extending block behavior. Plugins
are registered at board level and injected into each block's server at
render time. The `ctrl_block` plugin is the hook that `ai_ctrl_block()`
uses.

### ctrl_block factory

```r
# blockr.core/R/plugin-control.R
ctrl_block <- function(server = ctrl_block_server, ui = ctrl_block_ui) {
  new_plugin(server, ui, validate_ctrl, class = "ctrl_block")
}
```

The plugin takes a `server` and `ui` function. `ai_ctrl_block()` simply
provides its own implementations:

```r
# blockr.ai/R/ai-ctrl-block.R
ai_ctrl_block <- function() {
  blockr.core::ctrl_block(
    server = ai_ctrl_server,
    ui = ai_ctrl_ui
  )
}
```

### Server Signature

Both the default `ctrl_block_server` and `ai_ctrl_server` share the same
signature:

```r
function(id, x, vars, data, eval)
```

| Argument | Type | Description |
|---|---|---|
| `id` | character | Shiny module namespace ID |
| `x` | block | The block object (read-only, class info, metadata) |
| `vars` | named list | Block state. For `external_ctrl` blocks, contains `reactiveVal` objects. For blocks without, contains plain `reactive()` values (read-only). |
| `data` | reactive | Reactive returning the block's input data (list of reactives) |
| `eval` | reactive | Reactive that evaluates the block expression against input data |

**The key insight:** `vars` contains *writable* `reactiveVal` objects for
blocks with `external_ctrl`. Writing to these reactiveVals changes the
block's parameters, which triggers re-evaluation.

### UI Signature

```r
function(id, x)
```

The UI function receives the namespace `id` and the block object `x`. It
renders into the `.blockr-ctrl-body` area of each block.

## How ai_ctrl_block Replaces the Default

Usage at board level:

```r
serve(
  new_board(new_dataset_block("iris")),
  plugins = custom_plugins(ai_ctrl_block())
)
```

This tells blockr.core: for every block, use `ai_ctrl_ui` instead of
`ctrl_block_ui` and `ai_ctrl_server` instead of `ctrl_block_server`.

### Default vs AI ctrl

| | Default `ctrl_block` | `ai_ctrl_block` |
|---|---|---|
| **UI** | Text inputs per external_ctrl param | shinychat chat widget |
| **Server** | `observe_ctrl_input()` — syncs text input → reactiveVal | `discover_block_args()` — LLM loop that sets reactiveVals |
| **Scope** | Any block with external_ctrl | Same, but only useful when registry has `arguments`/`examples` metadata |

## The external_ctrl Mechanism

This is the bridge between the plugin system and the block's internal
state. It has three parts:

### 1. Block declaration

In the block constructor, set `external_ctrl`:

```r
# blockr.core/R/data-dataset.R — character vector (specific params)
new_data_block(
  ...,
  external_ctrl = "dataset",
  ...
)

# blockr.dplyr/R/filter.R — TRUE (all constructor params)
new_transform_block(
  ...,
  external_ctrl = TRUE,
  ...
)
```

`block_external_ctrl(x)` resolves this to a character vector:

```r
# blockr.core/R/block-class.R
block_external_ctrl <- function(x) {
  stopifnot(is_block(x))
  res <- attr(x, "external_ctrl")
  if (isTRUE(res)) {
    return(block_ctor_inputs(x))   # all constructor params
  }
  if (isFALSE(res)) {
    return(character())
  }
  stopifnot(is.character(res), all(res %in% block_ctor_inputs(x)))
  res
}
```

### 2. Environment cloning and reactiveVal injection

When `expr_server.block()` runs, it checks `block_supports_external_ctrl(x)`.
If true, it clones the server function's closure environment and replaces
the declared variables with `reactiveVal` objects:

```r
# blockr.core/R/block-server.R
expr_server.block <- function(x, data, ...) {
  has_external_ctrl <- block_supports_external_ctrl(x)
  srv_fun <- block_expr_server(x)
  srv_env <- environment(srv_fun)

  if (has_external_ctrl) {
    srv_env <- rlang::env_clone(srv_env)         # clone to avoid mutating original
    ctrl <- block_ctrl(x)                         # creates reactiveVal per param
    on.exit(`environment<-`(srv_fun, srv_env))
    environment(srv_fun) <- list2env(ctrl, srv_env)  # inject reactiveVals
  }

  res <- do.call(srv_fun, c(list(id = "expr"), data))
  ...
}
```

`block_ctrl()` creates the reactiveVals:

```r
# blockr.core/R/block-class.R
block_ctrl <- function(x) {
  inps <- block_external_ctrl(x)
  vals <- mget(inps, environment(block_expr_server(x)))
  lapply(vals, reactiveVal)   # initial values from closure
}
```

After injection, the block's server function sees `dataset` (or
`conditions`, `preserve_order`, etc.) as `reactiveVal` objects instead of
plain values. The block reads them with `dataset()` and the plugin
writes them with `dataset(new_value)`.

### 3. Bidirectional sync (block ↔ UI)

For the block's own UI to stay in sync with external changes, the block
server must implement bidirectional observers:

```r
# blockr.core/R/data-dataset.R — dataset_block example
# UI → reactiveVal
observeEvent(req(input$dataset), dataset(input$dataset))

# reactiveVal → UI
observeEvent(req(dataset()), {
  if (!identical(dataset(), input$dataset)) {
    updateSelectInput(session, "dataset",
      choices = list_datasets(package), selected = dataset())
  }
})
```

Without this, external changes (from the AI) would not reflect in the
block's own UI widgets.

## Data Flow

```
Board (serve)
  │
  ├─ block_server(id, x, data, plugins)
  │    │
  │    ├─ expr_server(x, data)
  │    │    ├─ Clone closure env (if external_ctrl)
  │    │    ├─ Inject reactiveVals via block_ctrl()
  │    │    └─ Call block's server function → returns expr + state
  │    │
  │    ├─ state_check_observer() — verify state values initialized
  │    ├─ data_eval_observer() — evaluate expr when inputs change
  │    │
  │    └─ ctrl_block plugin:
  │         ├─ ai_ctrl_ui(id, x) → shinychat widget
  │         └─ ai_ctrl_server(id, x, vars, data, eval)
  │              │
  │              ├─ Identify reactiveVal names in vars
  │              ├─ On user chat input:
  │              │    ├─ Snapshot data()
  │              │    ├─ Create reporter_shiny for live progress
  │              │    ├─ Create eval_validator (sets vars, calls eval)
  │              │    └─ discover_block_args(prompt, block, data, validate, reporter)
  │              │         ├─ LLM proposes JSON
  │              │         ├─ Reporter shows phase progress in chat
  │              │         ├─ Validator applies → success or error
  │              │         └─ Loop until DONE or max_iter
  │              │
  │              └─ Return reactive gate (TRUE/FALSE)
  │
  └─ output_render_observer() — render block result
```

## The eval_validator (Shiny Mode)

When running inside a live Shiny session, `ai_ctrl_server` provides a
custom validator to `discover_block_args`:

```r
# blockr.ai/R/ai-ctrl-block.R
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
```

This writes the proposed args into the block's reactiveVals, then
evaluates the block via `isolate(eval())`. The `eval` reactive
(provided by blockr.core) re-evaluates the block expression against
its input data. Because the expression blocks return
`expr = reactive(parse_*(state_rv()))`, `isolate()` forces lazy
recomputation from the just-updated reactiveVals — no observer needs
to fire.

If evaluation succeeds, the result is returned and the block's state
stays updated. If it throws, the validator **rolls back** all
reactiveVals to their previous values so the block's state (and thus
`expr()`) reverts to the last valid configuration. `discover_block_args`
catches the error and asks the LLM to fix its JSON.

## The Gate

`ai_ctrl_server` returns a reactive that acts as a gate:

```r
gate <- reactiveVal(TRUE)
# ...
observeEvent(input$chat_user_input, {
  gate(FALSE)     # pause downstream evaluation
  on.exit(gate(TRUE))   # resume when done
  # ... run discover_block_args ...
})
reactive(gate())
```

While the LLM loop is running, the gate is `FALSE`, which prevents the
block from re-rendering intermediate states. Once done, the gate opens
and the block renders the final result.

## Related Specs

- [00-overview.md](00-overview.md) — UX goals and scope
- [02-block-requirements.md](02-block-requirements.md) — How to add external_ctrl to a block
- [04-discover.md](04-discover.md) — The LLM loop in detail
