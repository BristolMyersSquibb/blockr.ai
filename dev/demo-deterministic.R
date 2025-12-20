# Demo: Deterministic LLM Transform Block
#
# This demo compares the deterministic approach with the tool-based approach.
# The deterministic block is ~4x faster while maintaining the same reliability.
#
# Usage:
#   source("dev/demo-deterministic.R")

library(blockr)
pkgload::load_all()

# Set model to gpt-4o-mini (fast and cheap)
# Function must have exact signature: (system_prompt = NULL, params = NULL)
options(
  blockr.chat_function = list(
    "gpt-4o-mini" = function(system_prompt = NULL, params = NULL) {
      ellmer::chat_openai(
        model = "gpt-4o-mini",
        system_prompt = system_prompt,
        params = params
      )
    }
  )
)

# Simple demo with just the deterministic block
run_app(
  blocks = c(
    # Source dataset
    data = new_dataset_block(dataset = "mtcars"),

    # Deterministic LLM transform block (no tools, system-controlled)
    transform = new_llm_transform_block_det()
  ),
  links = c(
    new_link("data", "transform", "data")
  )
)
