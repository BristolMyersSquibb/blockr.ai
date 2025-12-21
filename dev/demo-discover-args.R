# Demo: Discover Block Arguments using LLM
#
# This script demonstrates how to use an LLM to discover the correct
# arguments for a blockr block based on natural language.

# Load packages
library(blockr.dplyr)
devtools::load_all()


# -----------------------------------------------------------------------------
# Example 1: Summarize iris - mean by Species
# -----------------------------------------------------------------------------

cat("\n")
cat(strrep("#", 70), "\n")
cat("# Example 1: Summarize iris by Species\n")
cat(strrep("#", 70), "\n")

result <- discover_block_args(
  prompt = "Calculate the mean of Sepal.Length and Sepal.Width, grouped by Species",
  data = iris,
  block_ctor = new_summarize_block,
  block_name = "new_summarize_block"
)

if (result$success) {
  cat("\nDiscovered arguments:\n")
  print(result$args)
  cat("\nResult:\n")
  print(result$result)
} else {
  cat("\nFailed to discover arguments\n")
}


# -----------------------------------------------------------------------------
# Example 2: Filter mtcars
# -----------------------------------------------------------------------------

cat("\n")
cat(strrep("#", 70), "\n")
cat("# Example 2: Filter mtcars to 6-cylinder cars\n")
cat(strrep("#", 70), "\n")

result <- discover_block_args(
  prompt = "Keep only cars with 6 cylinders",
  data = mtcars,
  block_ctor = new_filter_block,
  block_name = "new_filter_block"
)

if (result$success) {
  cat("\nDiscovered arguments:\n")
  print(result$args)
  cat("\nResult (first 5 rows):\n")
  print(head(result$result, 5))
} else {
  cat("\nFailed to discover arguments\n")
}


# -----------------------------------------------------------------------------
# Example 3: Summarize mtcars with multiple aggregations
# -----------------------------------------------------------------------------

cat("\n")
cat(strrep("#", 70), "\n")
cat("# Example 3: Complex summarize on mtcars\n")
cat(strrep("#", 70), "\n")

result <- discover_block_args(
  prompt = "Group by cylinder, calculate mean hp, mean mpg, and count of cars",
  data = mtcars,
  block_ctor = new_summarize_block,
  block_name = "new_summarize_block"
)

if (result$success) {
  cat("\nDiscovered arguments:\n")
  print(result$args)
  cat("\nResult:\n")
  print(result$result)
} else {
  cat("\nFailed to discover arguments\n")
}


# -----------------------------------------------------------------------------
# Using the discovered args
# -----------------------------------------------------------------------------

cat("\n")
cat(strrep("#", 70), "\n")
cat("# Bonus: Using discovered args\n")
cat(strrep("#", 70), "\n")

if (result$success) {
  cat("\nThe discovered args can be used to:\n")
  cat("  1. Run the block headlessly (as we already did)\n")
  cat("  2. Create a block in a Shiny app\n")
  cat("  3. Store for later use\n\n")

  cat("Re-running with discovered args:\n")
  check <- do.call(run_block_headless, c(
    list(block_ctor = new_summarize_block, data = mtcars),
    result$args
  ))
  print(check$result)
}
