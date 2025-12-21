# Demo: Running Blocks Headlessly
#
# This script demonstrates how to run blockr blocks without a Shiny UI.
# You can execute blocks directly and get results back as data frames.

# Load packages
library(blockr.dplyr)
devtools::load_all()  # Load blockr.ai


# -----------------------------------------------------------------------------
# Example 1: Summarize iris - count by Species
# -----------------------------------------------------------------------------

result <- run_block_headless(
  block_ctor = new_summarize_block,
  data = iris,
  summaries = list(
    count = list(func = "dplyr::n", col = "")
  ),
  by = "Species"
)

cat("Example 1: Count by Species\n")
print(result$result)
cat("\n")


# -----------------------------------------------------------------------------
# Example 2: Summarize iris - mean Sepal.Length by Species
# -----------------------------------------------------------------------------

result <- run_block_headless(
  block_ctor = new_summarize_block,
  data = iris,
  summaries = list(
    mean_sepal_length = list(func = "mean", col = "Sepal.Length"),
    mean_sepal_width = list(func = "mean", col = "Sepal.Width")
  ),
  by = "Species"
)

cat("Example 2: Mean Sepal dimensions by Species\n")
print(result$result)
cat("\n")


# -----------------------------------------------------------------------------
# Example 3: Summarize mtcars - multiple aggregations by cylinder
# -----------------------------------------------------------------------------

result <- run_block_headless(
  block_ctor = new_summarize_block,
  data = mtcars,
  summaries = list(
    mean_hp = list(func = "mean", col = "hp"),
    mean_mpg = list(func = "mean", col = "mpg"),
    count = list(func = "dplyr::n", col = "")
  ),
  by = "cyl"
)

cat("Example 3: Mean hp, mpg and count by cylinder\n")
print(result$result)
cat("\n")


# -----------------------------------------------------------------------------
# Example 4a: Filter block (value-based) - keep only setosa
# -----------------------------------------------------------------------------

result <- run_block_headless(
  block_ctor = new_filter_block,
  data = iris,
  conditions = list(
    list(column = "Species", values = "setosa", mode = "include")
  )
)

cat("Example 4a: Filter to setosa only (value-based)\n")
cat("Rows:", nrow(result$result), "\n")
print(head(result$result))
cat("\n")


# -----------------------------------------------------------------------------
# Example 4b: Filter expression block - using R expressions
# -----------------------------------------------------------------------------

result <- run_block_headless(
  block_ctor = new_filter_expr_block,
  data = iris,
  exprs = 'Species == "setosa"'
)

cat("Example 4b: Filter to setosa only (expression-based)\n")
cat("Rows:", nrow(result$result), "\n")
print(head(result$result))
cat("\n")


# -----------------------------------------------------------------------------
# Example 5: Select block - keep only specific columns
# -----------------------------------------------------------------------------

result <- run_block_headless(
  block_ctor = new_select_block,
  data = iris,
  columns = c("Sepal.Length", "Sepal.Width", "Species"),
  exclude = FALSE
)

cat("Example 5: Select Sepal columns + Species\n")
print(head(result$result))
cat("\n")


# -----------------------------------------------------------------------------
# Example 6: Arrange block - sort by column
# -----------------------------------------------------------------------------

result <- run_block_headless(
  block_ctor = new_arrange_block,
  data = mtcars,
  columns = list(list(column = "mpg", direction = "desc"))
)

cat("Example 6: Sort mtcars by mpg descending\n")
print(head(result$result))
cat("\n")


# -----------------------------------------------------------------------------
# Example 7: Error handling - what happens with bad arguments?
# -----------------------------------------------------------------------------

result <- run_block_headless(
  block_ctor = new_summarize_block,
  data = iris,
  summaries = list(
    mean_nonexistent = list(func = "mean", col = "nonexistent_column")
  ),
  by = "Species"
)

cat("Example 7: Error handling (nonexistent column)\n")
cat("Success:", result$success, "\n")
if (!result$success) {
  cat("Result is NULL - block execution failed\n")
  if (!is.null(result$error)) {
    cat("Error message:", result$error, "\n")
  }
} else {
  print(result$result)
}
cat("\n")
