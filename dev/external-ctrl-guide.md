# Making Blocks External-Control Ready

The blockr framework can read and write block state at runtime through a mechanism called **external control**. Serialization already handles initial values — you just pass them to the constructor. External control goes further: it lets an external caller mutate a block's state *after* it is already running, bypassing the UI. This is what powers chat-driven parameter changes in blockr.ai. Blocks opt in to this system by following three rules.

## The Three Rules

### 1. Set `external_ctrl` on the constructor

Pass `external_ctrl` when creating the block. It accepts two forms:

- **`TRUE`** — all constructor parameters are externally controllable
- **A character vector** — only the named parameters are controllable

```r
# All params controllable
new_transform_block(server, ui, class = "my_block", external_ctrl = TRUE, ...)

# Only "dataset" is controllable ("package" is not)
new_data_block(server, ui, class = "dataset_block", external_ctrl = "dataset", ...)
```

The framework resolves this in `block_external_ctrl_vars()` (`blockr.core/R/block-class.R:673`): `TRUE` expands to all constructor inputs, `FALSE` or omitted means none, and a character vector is validated against the constructor formals.

### 2. Wrap each controllable param in `reactiveVal()`

Inside your server function, every parameter named in `external_ctrl` must be stored as a `reactiveVal`. This is what allows the external system to inject values — it replaces the constructor argument with a pre-seeded `reactiveVal` before your server runs.

```r
# In the server function:
r_dataset <- reactiveVal(dataset)   # "dataset" is controllable
```

### 3. Return those `reactiveVal`s in the `state` list

The server must return a `state` list whose **names match the constructor parameter names exactly**. Each controllable entry must be the `reactiveVal` itself (not its current value).

```r
list(
  expr = r_expr,
  state = list(
    dataset = r_dataset,   # reactiveVal — name matches constructor param
    package = package       # plain value — not externally controlled
  )
)
```

At startup, the framework checks this contract (`blockr.core/R/block-server.R:126-136`): for every `external_ctrl` variable, the corresponding `state` entry must `inherits(x, "reactiveVal")`. If not, it throws `unsupported_external_ctrl_variable`.

## Minimal Before/After Example

### Before — no external control

```r
new_dataset_block <- function(dataset = character(), package = "datasets", ...) {
  new_data_block(
    function(id) {
      moduleServer(id, function(input, output, session) {
        dat <- character()  # plain value — can't be written externally
        observeEvent(req(input$dataset), dat <<- input$dataset)

        list(
          expr = reactive(...),
          state = list(dataset = dat, package = package)
        )
      })
    },
    function(id) {
      selectInput(NS(id, "dataset"), "Dataset", choices = ..., selected = dataset)
    },
    class = "dataset_block",
    ...
  )
}
```

### After — external-control ready

```r
new_dataset_block <- function(dataset = character(), package = "datasets", ...) {
  new_data_block(
    function(id) {
      moduleServer(id, function(input, output, session) {
        dat <- reactiveVal(dataset)                         # Rule 2: reactiveVal
        observeEvent(req(input$dataset), dat(input$dataset))

        list(
          expr = reactive(...),
          state = list(
            dataset = dat,       # Rule 3: reactiveVal in state, name matches param
            package = package
          )
        )
      })
    },
    function(id) {
      selectInput(NS(id, "dataset"), "Dataset", choices = ..., selected = dataset)
    },
    class = "dataset_block",
    external_ctrl = "dataset",  # Rule 1: declare controllable params
    ...
  )
}
```

(See the real implementation in `blockr.core/R/data-dataset.R:14-86`.)

## Reverse Sync: Updating UI When State Changes Externally

When the external system writes to a `reactiveVal`, the Shiny input widget doesn't update automatically — the reactive drives the computation, but the UI still shows the old value. There are two patterns for reverse sync, depending on whether the block has static or dynamic UI.

### Pattern A: Static UI — `observeEvent` + `update*Input()`

For blocks where all inputs are created once in the `ui` function, add an `observeEvent` on the `reactiveVal` that calls the appropriate `update*Input()`.

From `dataset_block` (`blockr.core/R/data-dataset.R:43-54`):

```r
observeEvent(
  req(dat()),
  {
    if (!identical(dat(), input$dataset)) {
      updateSelectInput(
        session, "dataset",
        choices = list_datasets(package),
        selected = dat()
      )
    }
  }
)
```

For blocks with multiple controllable params, add one observer per param. From `select_block` (`blockr.dplyr/R/select.R:116-128`):

```r
# Reverse sync: external_ctrl -> UI
observeEvent(r_columns(), {
  if (r_initialized()) {
    updateSelectizeInput(session, "columns",
      choices = colnames(data()), selected = r_columns())
  }
}, ignoreInit = TRUE)

observeEvent(r_exclude(), {
  if (!identical(input$exclude, r_exclude())) {
    updateCheckboxInput(session, "exclude", value = r_exclude())
  }
}, ignoreInit = TRUE)
```

Key points:

- **Guard against loops** — check `!identical(current_input, new_value)` or use a flag like `r_initialized()` to avoid the observer re-triggering itself.
- **Use `ignoreInit = TRUE`** — the initial value is already set by the UI definition; firing on init would be redundant.

### Pattern B: Dynamic UI — guarding the input sync observer

Some blocks use `renderUI` to create inputs dynamically (e.g. the filter block adds/removes condition rows). These blocks typically have an **input sync observer** — an `observe()` that reads input values and writes them back to the state `reactiveVal`:

```r
# Input sync: reads UI inputs, writes to r_conditions
observe({
  indices <- r_condition_indices()
  for (i in indices) {
    input[[paste0("condition_", i, "_column")]]
    input[[paste0("condition_", i, "_values")]]
  }
  # ... read inputs and write back to state
  write_conditions_from_ui(get_current_conditions())
})
```

This pattern is necessary for dynamic UI (the framework needs to know what the user selected), but it creates a **race condition with external writes**.

#### The race condition

When the external system writes to `r_conditions()`:

1. The sync observer re-fires (spurious invalidation from Shiny's reactive graph)
2. It reads the **old** input values (UI hasn't been rebuilt yet)
3. It writes them back to `r_conditions()`, **overwriting the external value**
4. The external-update observer sees the self-write flag and skips
5. The UI never updates — the external write is silently lost

The `self_write` flag and `!identical()` guards from Pattern A do not prevent this, because the sync observer runs before the UI can rebuild.

#### The fix: track last UI write

Guard the sync observer so it only writes when the UI actually changed — not when it re-fires with stale values:

```r
# Track what the sync observer last wrote
last_ui_write <- new.env(parent = emptyenv())
last_ui_write$conditions <- NULL

write_conditions_from_ui <- function(new_conds) {
  last_ui_write$conditions <- new_conds
  if (!identical(new_conds, isolate(r_conditions()))) {
    self_write$active <- TRUE
    r_conditions(new_conds)
  }
}

# Input sync observer with guard
observe({
  # ... take dependencies on indices and inputs ...
  if (has_inputs) {
    current <- get_current_conditions()
    # Only write if the UI-derived conditions actually changed.
    # Prevents overwriting externally-set conditions during the
    # window between external write and UI rebuild.
    if (!identical(current, last_ui_write$conditions)) {
      write_conditions_from_ui(current)
    }
  }
})
```

This works because after an external write, the sync observer re-fires but reads the same old UI values it wrote last time. The `identical()` check against `last_ui_write` catches this and skips the write, allowing the external-update observer to fire next and rebuild the UI with fresh indices.

#### When does this apply?

Use Pattern B whenever your block has **all three** of:

1. Dynamic UI via `renderUI` (inputs are created/destroyed at runtime)
2. An input sync observer (reads inputs → writes state reactiveVal)
3. `external_ctrl` enabled

Blocks with static UI and simple `observeEvent(input$x, r_x(input$x))` wiring only need Pattern A.

See the full implementation in `blockr.dplyr/R/mod_value_filter.R`.

