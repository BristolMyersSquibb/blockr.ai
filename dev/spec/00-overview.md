# AI Control: Overview and Goals

> Spec for the `ai_ctrl` system in blockr.ai. Describes the target state;
> notes where the current implementation diverges.

## Vision

Each block on a blockr board gets a chat input. The user types a natural
language instruction — "filter to setosa", "use mtcars", "average by
species" — and the block reconfigures itself. No code, no dropdowns, no
guessing which parameter does what.

The chat is powered by an LLM that knows the block's parameters, the
current input data, and example JSON. It proposes a parameter set, blockr
validates it in-place, and the result appears instantly.

## Scope

**Single-block AI control.** The user talks to one block at a time.
Multi-block orchestration (e.g. "build me a pipeline that loads iris,
filters to setosa, and plots sepal length") is out of scope for now.

### Supported blocks today

16 blocks have `external_ctrl` enabled:

| Block | Package | `external_ctrl` |
|---|---|---|
| `dataset_block` | blockr.core | `"dataset"` (single param) |
| `subset_block` | blockr.core | `TRUE` |
| `filter_block` | blockr.dplyr | `TRUE` |
| `filter_expr_block` | blockr.dplyr | `TRUE` |
| `select_block` | blockr.dplyr | `TRUE` |
| `arrange_block` | blockr.dplyr | `TRUE` |
| `mutate_expr_block` | blockr.dplyr | `TRUE` |
| `summarize_block` | blockr.dplyr | `TRUE` |
| `summarize_expr_block` | blockr.dplyr | `TRUE` |
| `slice_block` | blockr.dplyr | `TRUE` |
| `rename_block` | blockr.dplyr | `TRUE` |
| `pivot_longer_block` | blockr.dplyr | `TRUE` |
| `pivot_wider_block` | blockr.dplyr | `TRUE` |
| `separate_block` | blockr.dplyr | `TRUE` |
| `unite_block` | blockr.dplyr | `TRUE` |
| `crossfilter_block` | blockr.dm | `TRUE` |
| `dm_crossfilter_block` | blockr.dm | `TRUE` |

Any block can be made AI-controllable by adding `external_ctrl` support
(see [02-block-requirements.md](02-block-requirements.md)).

## End-User Experience

1. The user opens a board and sees blocks with a small chat input at the
   bottom (inside the ctrl_block area).
2. They type, e.g., *"only show rows where Species is setosa"*.
3. The chat shows a brief "Done!" or an error message.
4. The block's UI and output update to reflect the new parameters.
5. The user can refine: *"also exclude rows with Sepal.Length < 5"*.

The chat is per-block. Each block maintains its own conversation context
within the session (currently not persisted across page reloads).

## How It Works (Summary)

```
User prompt
  → ai_ctrl_server (blockr.ai plugin)
    → discover_block_args()
      → LLM proposes JSON parameters
      → Validator applies them (sets reactiveVals or uses testServer)
      → If valid → DONE; if error → retry with error context
    → On success: reactiveVals updated → block re-evaluates → UI syncs
```

See [01-architecture.md](01-architecture.md) for the full data flow.

## Non-Goals

- **llm_blocks (code generation).** The legacy `llm_block` system in
  blockr.ai generates R code via LLM. It is being retired. `ai_ctrl`
  takes a fundamentally different approach: the LLM produces *parameter
  values* (JSON), not code.

- **Multi-block orchestration.** Building entire pipelines from a single
  prompt is deferred. The current system operates on one block at a time.

- **Conversation persistence.** Chat history is session-scoped. There is
  no plan to persist conversations across page reloads.

- **Undo/redo.** The user can re-prompt to change parameters, but there
  is no explicit undo mechanism beyond the LLM conversation.

## Glossary

| Term | Definition |
|---|---|
| **block** | A single unit of computation in blockr (data source, transform, or plot). Has a server function, UI, and an expression that produces a result. |
| **board** | A collection of blocks connected by links. Rendered as a Shiny app via `serve()`. |
| **ctrl_block** | A plugin slot in blockr.core that provides a UI and server for controlling a block externally. The default implementation provides text inputs; `ai_ctrl_block()` replaces it with a chat interface. |
| **external_ctrl** | A block attribute (`TRUE`, character vector, or `FALSE`) that declares which constructor parameters can be set from outside the block (e.g. by the ctrl_block plugin). |
| **reactiveVal** | A Shiny primitive for mutable reactive state. When `external_ctrl` is enabled, closure variables become `reactiveVal` objects that can be read and written from outside the block. |
| **discover_block_args** | The core function in blockr.ai that runs the LLM loop: prompt → JSON → validate → DONE/retry. |
| **validator** | A function that takes a list of proposed args and either returns a result (success) or throws an error. Two modes: standalone (testServer) and Shiny (reactiveVal + eval_impl). |
| **registry** | An environment in blockr.core (`block_registry`) that maps block class names to metadata: constructor, name, description, arguments, examples, etc. |

## Related Specs

- [01-architecture.md](01-architecture.md) — Plugin system and data flow
- [02-block-requirements.md](02-block-requirements.md) — Making a block AI-controllable
- [03-registry.md](03-registry.md) — Registry and LLM context
- [04-discover.md](04-discover.md) — The discover_block_args loop
