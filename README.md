
<!-- README.md is generated from README.Rmd. Please edit that file -->

# blockr.ai

<!-- badges: start -->

<!-- badges: end -->

## Overview

`blockr.ai` provides AI-powered blocks for the `blockr.core` framework.
It enables integration with various AI services and models to enhance
data analysis workflows through natural language interactions.

## Features

- Natural language powered plot creation through `new_llm_plot_block()`.
- AI-assisted data transformations through `new_llm_transform_block()`.
- Integration with many LLM APIs via the ellmer package.
- Interactive blocks that can be composed with other blockr components.

## Installation

You can install the development version of blockr.ai from GitHub with:

``` r
# install.packages("remotes")
remotes::install_github("BristolMyersSquibb/blockr.ai")
```

## Usage

`blockr.ai` extends the `blockr.core` framework with AI capabilities.

### Examples

``` r
library(blockr.core)
library(blockr.ai)

serve(
  new_llm_plot_block(),
  data = list(data = iris)
)

serve(
  new_llm_transform_block(),
  data = list(data = iris)
)

serve(
  new_board(
    blocks = blocks(
      a = new_dataset_block("mtcars"),
      b = new_llm_plot_block("Plot mpg vs hp")
    ),
    links = links("a", "b", "data")
  )
)
```
