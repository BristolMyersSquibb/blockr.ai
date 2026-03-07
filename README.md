# blockr.ai

AI-powered block configuration for the
[blockr.core](https://github.com/BristolMyersSquibb/blockr.core) framework.

## Overview

`blockr.ai` lets users configure blocks via natural language. Instead of
manually setting filter conditions, plot aesthetics, or summary functions,
describe what you want and an LLM figures out the right parameters.

The package provides two main capabilities:

- **`ai_ctrl_block()`** — A plugin that replaces the default block control
  panel with an AI chat interface. Works with any block that has
  `external_ctrl` enabled.
- **`discover_block_args()`** — Programmatic interface for LLM-driven block
  configuration, useful for testing and scripting.

## Installation

```r
# install.packages("remotes")
remotes::install_github("BristolMyersSquibb/blockr.ai")
```

## Usage

### AI control plugin

Add the AI chat interface to any board:

```r
library(blockr.core)
library(blockr.ai)

serve(
  new_board(
    blocks = blocks(
      a = new_dataset_block("iris"),
      b = new_filter_block()
    ),
    links = links("a", "b", "data")
  ),
  plugins = custom_plugins(ai_ctrl_block())
)
```

Users can then type prompts like "show only setosa" or "filter where
Sepal.Length > 5" in the chat panel.

### Programmatic discovery

```r
result <- discover_block_args(
  prompt = "setosa only",
  block = new_filter_block(),
  data = iris
)

result$success
result$args
```

### Data exploration

The LLM can optionally explore input data before configuring a block:

```r
result <- discover_block_args(
  prompt = "average sepal length by species",
  block = new_summarize_block(),
  data = iris,
  data_exploration = "manual"
)
```

See `?data_exploration_backend` for available strategies (`"none"`,
`"manual"`, `"tools"`).
