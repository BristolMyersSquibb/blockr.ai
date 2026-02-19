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

When the external system writes to a `reactiveVal`, the Shiny input widget doesn't update automatically — the reactive drives the computation, but the UI still shows the old value. You need an `observeEvent` on the `reactiveVal` that calls the appropriate `update*Input()` function.

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

