# Demo: Tool-based vs Deterministic Comparison
#
# This demo shows a prompt where the deterministic approach excels
# through error iteration, while baseline often fails.
#
# Usage:
#   source("dev/demo-trap-comparison.R")

library(blockr)
pkgload::load_all()

# Set model to gpt-4o-mini
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

# Tricky prompt - requires using OVERALL mean but ranking within GROUPS
# Baseline: ~60% correct (can't verify output)
# Deterministic: ~100% correct (sees output, can iterate)
# Common failure: Using group mean instead of overall mean
DEMO_PROMPT <- '
Calculate a "relative_efficiency" score for each car:

1. First, calculate each car mpg relative to overall mean mpg (not group mean!)
   relative_mpg = (mpg - overall_mean_mpg) / overall_mean_mpg * 100

2. Then, for each cyl group separately:
   - Rank cars by this relative_mpg (highest = rank 1)
   - Calculate "pct_rank": what percentile is this car within its cyl group?
     (rank 1 = 100th percentile, last rank = ~0th percentile)

Keep: cyl, mpg, hp, relative_mpg, rank_in_group, pct_rank
Sort by cyl, then rank_in_group.
Round to 1 decimal place.

Note: relative_mpg uses OVERALL mean, but ranking is within GROUPS.
'

cat("\n")
cat(strrep("=", 60), "\n")
cat("DEMO: Tool-based vs Deterministic\n")
cat(strrep("=", 60), "\n")
cat("\n")
cat("Prompt (pre-filled in both blocks):\n")
cat(DEMO_PROMPT, "\n")
cat("\n")
cat("This requires:\n")
cat("- Using OVERALL mean for relative_mpg calculation\n")
cat("- Ranking within GROUPS (not overall)\n")
cat("- Percentile calculation within groups\n")
cat("\n")
cat("Common trap: Using group mean instead of overall mean.\n")
cat("Baseline can't see output, so can't verify. Deterministic can.\n")
cat("Expected: Baseline ~60%, Deterministic ~100%\n")
cat(strrep("=", 60), "\n")
cat("\n")

# Side-by-side comparison
run_app(
  blocks = c(
    # mtcars data
    data = new_dataset_block(dataset = "mtcars"),

    # Tool-based approach (with prompt pre-filled)
    tool_based = new_llm_transform_block(
      messages = list(list(role = "user", content = trimws(DEMO_PROMPT)))
    ),

    # Deterministic approach (with prompt pre-filled)
    deterministic = new_llm_transform_block_det(
      messages = list(list(role = "user", content = trimws(DEMO_PROMPT)))
    )
  ),
  links = c(
    new_link("data", "tool_based", "data"),
    new_link("data", "deterministic", "data")
  )
)
