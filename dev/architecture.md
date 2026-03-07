# Architecture

How blockr.ai plugs into blockr.core's plugin system to provide
AI-powered block control.

## Vision

Each block on a blockr board gets a chat input. The user types a natural
language instruction -- "filter to setosa", "use mtcars", "average by
species" -- and the block reconfigures itself. No code, no dropdowns, no
guessing which parameter does what.

The chat is powered by an LLM that knows the block's parameters, the
current input data, and example JSON. It proposes a parameter set, blockr
validates it in-place, and the result appears instantly.

## Scope

**Single-block AI control.** The user talks to one block at a time.
Multi-block orchestration (e.g. "build me a pipeline that loads iris,
filters to setosa, and plots sepal length") is out of scope.

### Supported blocks

Any block with `external_ctrl` enabled works with `ai_ctrl_block()`.
See [external-ctrl-guide.md](external-ctrl-guide.md) for how to add
support to a block.

## End-User Experience

1. The user opens a board and sees blocks with a chat input at the
   top (inside the ctrl_block area).
2. They type, e.g., *"only show rows where Species is setosa"*.
3. The chat shows a brief "Done!" or an error message.
4. The block's UI and output update to reflect the new parameters.
5. The user can refine: *"also exclude rows with Sepal.Length < 5"*.

The chat is per-block. Each block maintains its own conversation context
within the session (not persisted across page reloads).

## How It Works

blockr.core has a **plugin system** for extending block behavior.
`ai_ctrl_block()` is a `ctrl_block` plugin -- it replaces the default
control panel (text inputs) with a shinychat chat widget.

The plugin receives the block's **state as writable `reactiveVal`
objects** (for blocks with `external_ctrl` enabled). When the user sends
a chat message, the plugin runs `discover_block_args()`, which queries
an LLM for JSON parameter values, validates them by writing to the
reactiveVals, and confirms the result. If validation fails, it rolls
back and lets the LLM retry.

A **gate** (`reactiveVal(TRUE/FALSE)`) pauses downstream rendering
while the LLM loop runs, so intermediate states don't flicker.

For details on the `external_ctrl` mechanism and how to add support to
a block, see [external-ctrl-guide.md](external-ctrl-guide.md). For
the LLM loop itself, see [discovery.md](discovery.md).

## Glossary

| Term | Definition |
|---|---|
| **block** | A unit of computation in blockr (data source, transform, or plot). |
| **board** | A collection of blocks connected by links, rendered as a Shiny app via `serve()`. |
| **ctrl_block** | A plugin slot in blockr.core for controlling a block externally. `ai_ctrl_block()` replaces the default with a chat interface. |
| **external_ctrl** | A block attribute declaring which constructor parameters can be set externally (by the ctrl_block plugin). |
| **discover_block_args** | The core function in blockr.ai: prompt -> LLM -> JSON -> validate -> DONE/retry. |

## See Also

- [external-ctrl-guide.md](external-ctrl-guide.md) -- Making blocks AI-controllable
- [discovery.md](discovery.md) -- The LLM loop and prompt assembly
- [debugging.md](debugging.md) -- Debugging AI control
