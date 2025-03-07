
<!-- README.md is generated from README.Rmd. Please edit that file -->

# blockr.ai

<!-- badges: start -->
<!-- badges: end -->

## Overview

`blockr.ai` provides AI-powered blocks for the `blockr.core` framework.
It enables integration with various AI services and models to enhance
data analysis workflows through natural language interactions.

## Features

- Natural language powered plot creation through `new_llm_plot_block()`
- AI-assisted data transformations through `new_llm_transform_block()`
- Integration with OpenAI’s GPT models
- Interactive blocks that can be composed with other blockr components

## Installation

You can install the development version of blockr.ai from GitHub with:

``` r
# install.packages("remotes")
remotes::install_github("cynkra/blockr.ai")
```

## Usage

`blockr.ai` extends the `blockr.core` framework with AI capabilities.

### Examples

``` r
library(blockr.ai)

blockr.core::serve(
  blockr.ai::new_llm_plot_block(),
  data = list(`1` = iris)
)

blockr.core::serve(
  blockr.ai::new_llm_transform_block(),
  data = list(`1` = iris)
)
```

## License

GPL (\>= 3)
