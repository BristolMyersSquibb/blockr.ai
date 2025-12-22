# Demo: Filter Block with AI Assistant
#
# This script demonstrates the new filter block that has an integrated
# AI assistant for configuring filter conditions using natural language.

# Load packages
library(blockr)
devtools::load_all()

# Basic demo: Filter block with iris dataset
cat("\n")
cat(strrep("=", 60), "\n")
cat("Filter Block with AI Assistant - Demo\n")
cat(strrep("=", 60), "\n\n")

cat("This demo shows the new filter block with integrated AI assistant.\n")
cat("The AI assistant lets users describe what they want in natural language.\n\n")

cat("Try typing in the AI assistant:\n")
cat("  - 'Keep only setosa species'\n")
cat("  - 'Filter to rows where Sepal.Length is 5.1'\n\n")

# Connected blocks example (dataset -> filter)
cat("Starting Shiny app with dataset -> filter blocks...\n\n")

run_app(
  blocks = c(
    data = new_dataset_block(dataset = "iris"),
    filter = new_filter_block()
  ),
  links = c(
    new_link("data", "filter", "data")
  )
)
