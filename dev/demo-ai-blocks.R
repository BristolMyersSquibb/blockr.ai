# Demo: AI-Assisted Blocks Showcase
#
# This script demonstrates all 6 AI-assisted blocks in blockr.ai:
# - Filter: Select rows based on conditions
# - Mutate: Create/modify columns
# - Summarize: Aggregate data with grouping
# - Pivot Longer: Reshape wide to long
# - Pivot Wider: Reshape long to wide
# - Code: Write arbitrary R code

# Load packages
library(blockr)
devtools::load_all()

cat("\n")
cat(strrep("=", 70), "\n")
cat("AI-Assisted Blocks Demo - All 6 Blocks\n")
cat(strrep("=", 70), "\n\n")

cat("This demo shows all 6 AI-assisted blocks in one workflow.\n")
cat("Each block has a chat interface where you can describe what you want.\n\n")

cat("Example prompts to try:\n")
cat("  Filter:        'Keep only cars with 6 or 8 cylinders'\n")
cat("  Mutate:        'Create a column hp_per_cyl that is hp divided by cyl'\n")
cat("  Summarize:     'Calculate mean mpg and mean hp by cyl'\n")
cat("  Pivot Longer:  'Gather mpg, hp, and wt columns'\n")
cat("  Pivot Wider:   'Spread cyl into columns with mpg values'\n")
cat("  Code:          'Filter for 6 cyl cars and select mpg, hp, wt'\n\n")

cat("Starting demo with mtcars dataset...\n\n")

# Star topology: all blocks connect directly to the dataset
run_app(
  blocks = c(
    data = new_dataset_block(dataset = "mtcars"),
    filter = new_filter_block(),
    mutate = new_mutate_block(),
    summarize = new_summarize_block(),
    longer = new_pivot_longer_block(),
    wider = new_pivot_wider_block(),
    code = new_code_block()
  ),
  links = c(
    new_link("data", "filter", "data"),
    new_link("data", "mutate", "data"),
    new_link("data", "summarize", "data"),
    new_link("data", "longer", "data"),
    new_link("data", "wider", "data"),
    new_link("data", "code", "data")
  )
)
