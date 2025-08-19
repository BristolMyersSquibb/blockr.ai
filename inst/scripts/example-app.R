#!/usr/bin/env Rscript

# Demo script to test the new table summary block functionality
library(blockr.core)
pkgload::load_all()

# Configure Azure OpenAI with debug output
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

# Demo to test table summary block
demo_table_summary <- function() {
  

  
  serve(
    new_board(
      blocks = blocks(
        # Clinical data source
        data_src = new_dataset_block("iris"),
        
        # Create a gtsummary table
        summary = new_llm_gtsummary_block(
          question = "Create a summary table comparing groups"
        ),
        
        # Test the new table insights block
        insights = new_llm_table_insights_block(
          question = "Summarize the key findings"
        )
      ),
      links = list(
        from = c("data_src", "summary"),
        to = c("summary", "insights"),
        input = c("data", "data")
      )
    )
  )
}

# Run the demo
demo_table_summary()