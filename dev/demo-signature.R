# Demo: Block Signature Analysis
#
# This script demonstrates how to introspect block constructors
# to understand their parameters for LLM prompts.

# Load packages
library(blockr.dplyr)
devtools::load_all()


# -----------------------------------------------------------------------------
# Get raw signature info
# -----------------------------------------------------------------------------

sig <- get_block_signature(new_summarize_block, name = "new_summarize_block")

cat("=== Raw Signature Info ===\n")
cat("Name:", sig$name, "\n")
cat("Parameters:", paste(sig$param_names, collapse = ", "), "\n")
cat("\n")


# -----------------------------------------------------------------------------
# Format signature for LLM prompt
# -----------------------------------------------------------------------------

cat("=== Formatted Signatures for LLM ===\n\n")

blocks <- list(
  summarize = list(ctor = new_summarize_block, name = "new_summarize_block"),
  filter = list(ctor = new_filter_block, name = "new_filter_block"),
  filter_expr = list(ctor = new_filter_expr_block, name = "new_filter_expr_block"),
  select = list(ctor = new_select_block, name = "new_select_block"),
  mutate = list(ctor = new_mutate_block, name = "new_mutate_block"),
  arrange = list(ctor = new_arrange_block, name = "new_arrange_block")
)

for (block_info in blocks) {
  cat(format_block_signature(block_info$ctor, name = block_info$name))
  cat("\n\n---\n\n")
}


# -----------------------------------------------------------------------------
# Combining signature with data preview for a complete LLM prompt
# -----------------------------------------------------------------------------

cat("=== Complete Prompt Example ===\n\n")

# Get block signature
sig_text <- format_block_signature(new_summarize_block, name = "new_summarize_block")

# Get data preview (reusing utility from utils-det.R)
data_preview <- create_data_preview(list(data = iris))

# Build a prompt
prompt <- paste(
  "You are setting up a blockr block. Generate R code to create the arguments.",
  "",
  sig_text,
  "",
  "Available Data:",
  data_preview,
  "",
  "User Task: Calculate the mean of all numeric columns, grouped by Species",
  "",
  "Output R code that creates a list called `args` with the block parameters.",
  sep = "\n"
)

cat(prompt)
cat("\n")
