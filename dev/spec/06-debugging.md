# Debugging AI Control

> Three debugging levels for AI-controlled blocks, from cheapest to
> most expensive. Always prefer (a) over (b) over (c).

## (a) Standalone `discover_block_args` — LLM correctness

**Cost:** Low (one LLM round-trip, no Shiny session).

**Use when:** You want to verify that the LLM produces valid JSON args
for a given block and prompt.

```r
pkgload::load_all("../blockr.core")
pkgload::load_all("../blockr.dplyr")
pkgload::load_all(".")

result <- discover_block_args(
  prompt = "all vars mean by cyl",
  block = new_summarize_block(),
  data = mtcars,
  verbose = TRUE
)

cat("Success:", result$success, "\n")
print(result$result)
print_conversation(result)
```

**What it tests:**
- System prompt construction (registry metadata, block params)
- LLM → JSON extraction → `fromJSON` parsing
- Standalone validator: creates a fresh block with proposed args,
  evaluates it via `testServer`
- Does NOT test the live `eval_validator` or reactive state updates

**Common failures:**
- `extract_json()` returns NULL → LLM didn't produce a code block
- `fromJSON()` throws → malformed JSON
- Standalone validator throws → args are valid JSON but produce an
  R error (wrong column name, invalid function, etc.)


### Standardized test file

Every block with `external_ctrl` should have a `test-<block>-external-ctrl.R`
with two tests:

1. **State has reactiveVals** — verify `ctrl_names` contains expected params
2. **Setting vars updates expr** — call `holder$vars$param(value)`, flush,
   check `deparse(expr())` contains the new value

This catches the exact bug class where standalone discovery works (LLM returns
correct JSON) but the reactive chain doesn't propagate — e.g. slice_block
`prop` was set but `r_use_prop` stayed FALSE because no reverse sync observer
existed.


## (b) `testServer` with `block_server` — integration

**Cost:** Medium (boots a real `block_server` module, no browser).

**Use when:** Standalone discovery works but you suspect the live
reactive chain is broken — e.g. the block doesn't re-evaluate after
AI sets state.

```r
pkgload::load_all("../blockr.core")
pkgload::load_all("../blockr.dplyr")

library(shiny)

x <- new_summarize_block(
  summaries = list(avg_mpg = list(func = "mean", col = "mpg")),
  by = "cyl"
)

holder <- new.env(parent = emptyenv())

# Custom ctrl_block that programmatically sets state
test_ctrl_server <- function(id, x, vars, dat, expr) {
  moduleServer(id, function(input, output, session) {
    ctrl_names <- names(Filter(
      function(v) inherits(v, "reactiveVal"),
      vars
    ))
    cat("ctrl_names:", paste(ctrl_names, collapse = ", "), "\n")
    holder$ctrl_names <- ctrl_names
    holder$vars <- vars
    holder$expr <- expr

    gate <- reactiveVal(TRUE)

    # Trigger from test body via holder$trigger
    observeEvent(holder$trigger(), {
      gate(FALSE)
      on.exit(gate(TRUE))

      # Set state — replace with actual args from discover
      vars$summaries(list(
        mean_hp = list(func = "mean", col = "hp"),
        mean_wt = list(func = "mean", col = "wt")
      ))
      vars$by(c("cyl", "gear"))

      # Verify eval works
      result <- isolate(blockr.core:::eval_impl(x, expr(), dat()))
      cat("eval_impl cols:", paste(names(result), collapse = ", "), "\n")
      holder$ok <- TRUE
    }, ignoreInit = TRUE)

    reactive(gate())
  })
}

test_ctrl <- blockr.core::ctrl_block(
  server = test_ctrl_server,
  ui = function(id, x) tagList()
)

holder$trigger <- reactiveVal(0L)

shiny::testServer(
  app = blockr.core::block_server,
  args = list(
    x = x,
    data = list(data = reactive(mtcars)),
    ctrl_block = test_ctrl
  ),
  {
    session$flushReact()
    Sys.sleep(0.5)
    session$flushReact()

    cat("ctrl_names:", paste(holder$ctrl_names, collapse = ", "), "\n")
    # Expect: "summaries, by" (reactiveVals from external_ctrl)
    # If empty: block state doesn't contain reactiveVals

    # Trigger AI ctrl
    holder$trigger(1L)
    session$flushReact()
    Sys.sleep(0.3)
    session$flushReact()

    cat("Validator OK:", isTRUE(holder$ok), "\n")
  }
)
```

**What it tests:**
- `expr_server.block` creates ctrl reactiveVals via `block_ctrl()`
- `state` passed to ctrl_block contains reactiveVals (not plain
  reactives)
- Setting reactiveVals updates `expr()` and `lang()`
- `eval_impl` produces the correct result with new params
- `data_eval_observer` fires and the block output updates

**Common failures:**
- `ctrl_names` is empty → the block returns its own `state` that
  overrides the ctrl reactiveVals. Fix: remove `state` from the
  block server's return value so blockr.core auto-creates it from
  `block_ctrl()`.
- `expr()` is stale after setting state → the `expr` return value
  was a `reactiveVal` instead of a lazy `reactive(...)`. **Fixed:**
  all 4 expression blocks (filter_expr, summarize_expr, mutate_expr,
  rename) now return `expr = reactive(parse_*(...))` which recomputes
  on read from current reactiveVal dependencies.
- `eval_impl` throws → the expression is malformed or doesn't match
  the data.

**Key pattern:** The block's constructor params (e.g. `summaries`,
`by`) must flow through as reactiveVals in `state`:

```
block_ctrl(x) creates reactiveVals
  → injected into server env via list2env(ctrl, srv_env)
  → block server uses them directly (e.g. as_rv(summaries))
  → block does NOT return state → blockr.core auto-creates from ctrl
  → ctrl_block plugin sees reactiveVals in vars
```


## (c) Playwright E2E — full app testing

**Cost:** High (starts a Shiny app, launches a browser, interacts
with the UI).

**Use when:** (a) and (b) both pass but the live app still doesn't
work. Typical issues at this level:

- UI elements don't update after AI sets state (bidirectional sync)
- CSS/JS overlay blocks interaction
- Plugin resolution via the board system (vs. direct `ctrl_block` param)
- Timing issues with complex observer chains

See [05-playwright-e2e.md](05-playwright-e2e.md) for Playwright setup
and patterns.


## Decision flowchart

```
Does the LLM produce correct args?
  ├─ No  → Fix system prompt, registry metadata, or examples → (a)
  └─ Yes
      ↓
Does testServer show reactiveVals in ctrl_names?
  ├─ No  → Fix block: don't return state, use as_rv() → (b)
  └─ Yes
      ↓
Does eval_impl succeed after setting state?
  ├─ No  → Fix expr reactive to read ctrl reactiveVals directly → (b)
  └─ Yes
      ↓
Does test-*-external-ctrl.R pass? (setting vars → expr updates)
  ├─ No  → Fix reverse sync observers → (b)
  └─ Yes
      ↓
Does the live app update?
  ├─ No  → Playwright: check UI sync, plugin wiring, timing → (c)
  └─ Yes → Done!
```


## Related Specs

- [02-block-requirements.md](02-block-requirements.md) — What blocks need for `external_ctrl`
- [04-discover.md](04-discover.md) — The `discover_block_args` loop
- [05-playwright-e2e.md](05-playwright-e2e.md) — E2E test patterns
