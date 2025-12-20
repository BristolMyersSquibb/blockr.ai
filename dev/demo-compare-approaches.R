# Demo: Compare Tool-based vs Deterministic LLM Blocks
#
# This demo shows both approaches side-by-side so you can compare:
# - Speed (deterministic is ~4x faster)
# - Behavior (both should produce correct results)
#
# Usage:
#   source("dev/demo-compare-approaches.R")

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

# Side-by-side comparison
run_app(
  blocks = c(
    # Source dataset
    data = new_dataset_block(dataset = "mtcars"),

    # Tool-based approach (current production)
    tool_based = new_llm_transform_block(),

    # Deterministic approach (new, faster)
    deterministic = new_llm_transform_block_det()
  ),
  links = c(
    # Both blocks receive the same data
    new_link("data", "tool_based", "data"),
    new_link("data", "deterministic", "data")
  )
)


# Try this prompt in both blocks to compare:
# "Group by cyl, calculate mean mpg and count, add pct_of_total"
