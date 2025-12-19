# Trial: Multi-run comparison
#
# Run N trials each for preview vs no-preview
# Save results for later evaluation by Claude
#
# Run with: Rscript dev/trial-multi-run.R

pkgload::load_all()
source("dev/harness.R")

# --- Config ---

N_RUNS <- 3
MODEL <- "gpt-4o-mini"
EXPERIMENT_NAME <- "pct-sales"

config <- list(
  model = MODEL,
  chat_fn = function() ellmer::chat_openai(model = MODEL)
)

# --- Test data ---

make_test_data <- function() {
  set.seed(sample(1:10000, 1))
  data.frame(
    region = sample(c("North", "South", "East", "West", NA), 50, replace = TRUE),
    revenue = round(runif(50, 100, 1000), 2)
  )
}

# --- Prompt ---

prompt <- "
Analyze sales by region. Handle NA as Unknown.
Calculate total_revenue and pct_of_total (must sum to 1.0).
Round to 2 decimals. Sort by total_revenue desc.
Output: region, total_revenue, pct_of_total
"

# --- Run trials ---

cat("\n")
cat(strrep("=", 70), "\n")
cat("MULTI-RUN TRIAL: ", MODEL, " (", N_RUNS, " runs per variant)\n", sep = "")
cat(strrep("=", 70), "\n\n")

results_a <- list()  # No preview
results_b <- list()  # With preview

for (i in seq_len(N_RUNS)) {
  cat("\n--- Run ", i, "/", N_RUNS, " ---\n", sep = "")

  # Use same data for both variants in this run
  test_data <- make_test_data()

  cat("\nVariant A (no preview):\n")
  results_a[[i]] <- run_llm_ellmer(prompt, test_data, config)
  cat("  Duration:", round(results_a[[i]]$duration_secs, 1), "s",
      "| Tool calls:", count_tool_calls(results_a[[i]]$turns)$total, "\n")

  cat("\nVariant B (with preview):\n")
  results_b[[i]] <- run_llm_ellmer_with_preview(prompt, test_data, config)
  cat("  Duration:", round(results_b[[i]]$duration_secs, 1), "s",
      "| Tool calls:", count_tool_calls(results_b[[i]]$turns)$total, "\n")
}

# --- Save results ---

cat("\n")
cat(strrep("=", 70), "\n")
cat("SAVING RESULTS\n")
cat(strrep("=", 70), "\n\n")

save_experiment(results_a, results_b, config, prompt, name = EXPERIMENT_NAME)

cat("\nDone. Ask Claude to evaluate the results.\n")
