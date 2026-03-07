# Debugging AI Control

Three levels, cheapest first. Always start at (a).

## (a) Standalone discovery -- does the LLM produce valid args?

```r
result <- discover_block_args(
  prompt = "all vars mean by cyl",
  block = new_summarize_block(),
  data = mtcars,
  verbose = TRUE
)
result$success
print_conversation(result)
```

If this fails, the issue is in the system prompt or registry metadata
(missing `arguments`, bad `examples`).

## (b) testServer -- does the reactive chain work?

Use when standalone discovery succeeds but the block doesn't update in a
live app. Write a test that injects a mock `ctrl_block`, sets
reactiveVals programmatically, and checks that `eval()` produces the
right result.

Two things to verify:

1. `ctrl_names` contains the expected params (they're `reactiveVal`s)
2. Setting a var and flushing reactives updates the block expression

Common causes when this fails:
- Block's `state` doesn't contain `reactiveVal` objects
- `expr` is a `reactiveVal` instead of a lazy `reactive()`
- Derived internal state not updated by reverse sync

## (c) Playwright E2E -- does the live app work?

Use when (a) and (b) pass but the UI doesn't update. Launch the app,
use the Playwright MCP to navigate, type a prompt, wait, and verify
via snapshots/screenshots. Typical issues: missing bidirectional sync,
CSS overlays, or timing.

## Decision flowchart

```
LLM produces correct args?
  No  -> fix registry metadata / examples         -> (a)
  Yes -> reactiveVals in ctrl_names?
           No  -> fix block state (use reactiveVal) -> (b)
           Yes -> eval works after setting state?
                    No  -> fix expr reactive        -> (b)
                    Yes -> live app updates?
                             No  -> check UI sync   -> (c)
                             Yes -> done
```

## See Also

- [discovery.md](discovery.md) -- The discovery process
- [external-ctrl-guide.md](external-ctrl-guide.md) -- Block requirements
