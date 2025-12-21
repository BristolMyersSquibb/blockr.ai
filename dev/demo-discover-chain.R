# Demo: Discover Block Chain using LLM
#
# This script demonstrates how to use an LLM to discover a chain of blocks
# to solve a complex multi-step task.

# Load packages
library(blockr.dplyr)
devtools::load_all()


# -----------------------------------------------------------------------------
# Example 1: Simple 2-block chain
# Filter + Summarize
# -----------------------------------------------------------------------------

cat("\n")
cat(strrep("#", 70), "\n")
cat("# Example 1: Filter iris to setosa, then calculate mean Sepal.Length\n")
cat(strrep("#", 70), "\n\n")

result <- discover_block_chain(

  prompt = "Filter iris to setosa, then calculate mean Sepal.Length",
  data = iris,
  max_steps = 3,
  verbose = TRUE
)

if (result$success) {
  cat("\n\nFinal Result:\n")
  print(result$result)

  cat("\nChain Summary:\n")
  for (i in seq_along(result$chain)) {
    step <- result$chain[[i]]
    cat("  Step ", i, ": ", step$block, "\n", sep = "")
    cat("    Subtask: ", step$subtask, "\n", sep = "")
  }
}


# -----------------------------------------------------------------------------
# Example 2: More complex chain
# Filter + Mutate + Summarize
# -----------------------------------------------------------------------------

cat("\n\n")
cat(strrep("#", 70), "\n")
cat("# Example 2: Filter mtcars to 6+ cylinders, add hp_per_cyl, summarize\n")
cat(strrep("#", 70), "\n\n")

result2 <- discover_block_chain(
  prompt = "Filter mtcars to cars with 6 or more cylinders, add a new column hp_per_cyl = hp/cyl, then calculate mean hp_per_cyl grouped by cyl",
  data = mtcars,
  max_steps = 5,
  verbose = TRUE
)

if (result2$success) {
  cat("\n\nFinal Result:\n")
  print(result2$result)

  cat("\nChain Summary:\n")
  for (i in seq_along(result2$chain)) {
    step <- result2$chain[[i]]
    cat("  Step ", i, ": ", step$block, "\n", sep = "")
    cat("    Subtask: ", step$subtask, "\n", sep = "")
  }
}
