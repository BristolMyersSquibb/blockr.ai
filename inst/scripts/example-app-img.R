#!/usr/bin/env Rscript

# Test script to demonstrate image upload functionality
library(blockr.core)
pkgload::load_all()

# Configure Azure OpenAI with debug output
# Not necessary for outside of BMS
options(blockr.chat_function = function(system_prompt) {
  cat("==== SYSTEM PROMPT BEING SENT TO LLM ====\n")
  cat(system_prompt)
  cat("\n==== END SYSTEM PROMPT ====\n")

  ellmer::chat_azure_openai(
    system_prompt = system_prompt,
    endpoint = Sys.getenv("AZURE_OPENAI_ENDPOINT"),
    deployment_id = Sys.getenv("AZURE_OPENAI_DEPLOYMENT_ID"),
    api_key = Sys.getenv("AZURE_OPENAI_API_KEY"),
    api_version = Sys.getenv("AZURE_OPENAI_API_VERSION")
  )
})

# Create a combined demo with both plot and table blocks for recreating outputs
demo_app <- function() {

  # Create a board with connected plot and table blocks using iris data
  serve(
    new_board(
      blocks = blocks(
        data_src = new_dataset_block("iris"),
        visualize = new_llm_plot_block(
          question = "Recreate the plot shown in the uploaded image"
        ),
        table = new_llm_gt_block(
          question = "Recreate the table format shown in the uploaded image"
        )
      ),
      links = list(
        from = c("data_src", "data_src"),
        to = c("visualize", "table"),
        input = c("data", "data")
      )
    )
  )
}

# Run the demo
if (interactive()) {

  # upload inst/data/iris_scatter to plot
  # upload inst/data/iris_table to table
  demo_app()
}
