# Test discover_block_args() without Shiny
#
# This script demonstrates how to test the AI discovery loop
# from the R console without running a Shiny app.

library(blockr.core)
library(blockr.dplyr)
library(blockr.ai)

# Test 1: Filter block - "setosa only"
cat("=== Test 1: Filter block ===\n")
result <- discover_block_args(
  prompt = "setosa only",
  block = new_filter_block(),
  data = iris,
  verbose = TRUE
)

cat("\n--- Result ---\n")
cat("Success:", result$success, "\n")
cat("Args:", deparse(result$args), "\n")
if (!is.null(result$result)) {
  cat("Result rows:", nrow(result$result), "\n")
  print(head(result$result, 3))
}
if (!is.null(result$error)) {
  cat("Error:", result$error, "\n")
}


# Test 2: Summarize block
cat("\n\n=== Test 2: Summarize block ===\n")
result2 <- discover_block_args(
  prompt = "average sepal length by species",
  block = new_summarize_block(),
  data = iris,
  verbose = TRUE
)

cat("\n--- Result ---\n")
cat("Success:", result2$success, "\n")
if (!is.null(result2$result)) {
  print(result2$result)
}


# Test 3: Dataset block (no input data)
cat("\n\n=== Test 3: Dataset block ===\n")
result3 <- discover_block_args(
  prompt = "use mtcars",
  block = new_dataset_block(),
  verbose = TRUE
)

cat("\n--- Result ---\n")
cat("Success:", result3$success, "\n")
cat("Args:", deparse(result3$args), "\n")
