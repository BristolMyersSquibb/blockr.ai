# Demo: AI-Assisted Head Block
#
# This script demonstrates the head block with AI assistance.
# The AI can configure the block based on natural language descriptions.

library(blockr)
devtools::load_all()

cat("\n")
cat(strrep("=", 60), "\n")
cat("AI-Assisted Head Block Demo\n")
cat(strrep("=", 60), "\n\n")

cat("Example prompts to try:\n")
cat("  'show the last 10 rows'\n")
cat("  'first 5 rows'\n")
cat("  'tail 20'\n")
cat("  'show me the bottom 3 rows'\n\n")

run_app(
  blocks = c(
    data = new_dataset_block(dataset = "mtcars"),
    head = blockr.ai::new_head_block()
  ),
  links = c(
    new_link("data", "head", "data")
  )
)
