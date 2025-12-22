# Demo: AI-Assisted Pivot Blocks
#
# This script demonstrates the pivot blocks with AI assistants.

# Load packages
library(blockr)
devtools::load_all()

cat("\n")
cat(strrep("=", 70), "\n")
cat("Pivot Blocks with AI Demo\n")
cat(strrep("=", 70), "\n\n")

# Create sample data for pivot operations
wide_data <- data.frame(
  id = 1:5,
  name = c("Alice", "Bob", "Carol", "Dave", "Eve"),
  jan_sales = c(100, 150, 200, 120, 180),
  feb_sales = c(110, 140, 210, 130, 190),
  mar_sales = c(105, 160, 195, 125, 200)
)

cat("Wide data format:\n")
print(wide_data)
cat("\n")

cat("Try these prompts:\n")
cat("  Pivot Longer: 'Gather the sales columns into month and value'\n")
cat("  Pivot Wider:  'Spread name into columns with the sales value'\n\n")

# Demo 1: Pivot Longer
cat("Demo 1: Pivot Longer (wide to long)\n")
cat(strrep("-", 50), "\n\n")

run_app(
  blocks = c(
    data = new_data_block(wide_data, name = "wide_data"),
    pivot = new_pivot_longer_block()
  ),
  links = c(
    new_link("data", "pivot", "data")
  )
)
