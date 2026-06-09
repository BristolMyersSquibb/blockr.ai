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
a chat message, the plugin runs `discover_block_args()`, which drives an
LLM **tool-calling** loop: the model explores the input data with a
read-only `data_tool` and applies a configuration by calling a
`validate_config` tool. `validate_config` writes the parameters to the
reactiveVals and returns whether it was valid, **what changed** (the
effect), and a preview. If validation fails the model sees the error and
retries; it stops once the effect matches the request.

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
| **discover_block_args** | The core function in blockr.ai: drives an ellmer tool-calling loop (`data_tool` + `validate_config`) that proposes, validates, and applies a block configuration. |
| **validate_config** | The tool the model calls to apply a config; returns `{ok, effect, preview}` or an error. The last valid call is the apply. |

## See Also

- [external-ctrl-guide.md](external-ctrl-guide.md) -- Making blocks AI-controllable
- [discovery.md](discovery.md) -- The LLM loop and prompt assembly
- [debugging.md](debugging.md) -- Debugging AI control
