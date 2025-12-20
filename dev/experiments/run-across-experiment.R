# Across Experiment - Targeted Skill Test
#
# Tests a SPECIFIC trap that LLMs consistently fail:
# Using tidyselect helpers (starts_with, ends_with) inside summarize/mutate
#
# WRONG (common LLM error):
#   data |> summarize(total = sum(starts_with("x")))
#
# CORRECT (requires across):
#   data |> summarize(across(starts_with("x"), sum))
#
# This trap is:
# 1. Very common (LLMs make this mistake frequently)
# 2. Has a non-obvious fix (need to know about across())
# 3. Clear success/failure criteria
#
# Usage:
#   source("dev/experiments/run-across-experiment.R")
#   run_across_experiment()

source("dev/harness.R")

# Data with multiple value columns that need aggregation
WIDE_DATA <- data.frame(
  category = c("A", "A", "B", "B", "C", "C"),
  subcategory = c("x", "y", "x", "y", "x", "y"),
  value_jan = c(10, 20, 30, 40, 50, 60),
  value_feb = c(15, 25, 35, 45, 55, 65),
  value_mar = c(12, 22, 32, 42, 52, 62),
  count_jan = c(1, 2, 3, 4, 5, 6),
  count_feb = c(2, 3, 4, 5, 6, 7),
  stringsAsFactors = FALSE
)

# Prompt designed to trigger the across() trap
ACROSS_PROMPT <- '
Using wide_data, calculate summary statistics by category:

1. For each category, sum all columns that start with "value_"
   (value_jan, value_feb, value_mar should each be summed within category)

2. The result should have:
   - One row per category (A, B, C)
   - Columns: category, value_jan, value_feb, value_mar
   - Each value column contains the sum for that category

3. Sort by category alphabetically.

Expected output shape: 3 rows x 4 columns
'

# KNOWN FAILURE MODE:
#
# LLM writes:
#   wide_data |>
#     group_by(category) |>
#     summarize(
#       value_jan = sum(value_jan),
#       value_feb = sum(value_feb),
#       value_mar = sum(value_mar)
#     )
#
# This WORKS but is verbose. The trap comes when trying to be "smart":
#
# WRONG:
#   summarize(across(starts_with("value_"), ~sum(.)))  # Wrong syntax
#   summarize(sum(starts_with("value_")))              # Doesn't work
#
# CORRECT:
#   summarize(across(starts_with("value_"), sum))      # Correct syntax


# --- Run A1: No skills (baseline) ---

run_A1_no_skills <- function(times = 5, model = "gpt-4o-mini") {

  cat("\n")
  cat(strrep("#", 70), "\n")
  cat("# ACROSS TRIAL A1: No skills (baseline)\n")
  cat(strrep("#", 70), "\n\n")

  output_dir <- "dev/results/across-test/trial_A1_no_skills"

  run_experiment(
    run_fn = run_llm_ellmer_with_preview_and_validation,
    prompt = ACROSS_PROMPT,
    data = list(wide_data = WIDE_DATA),
    output_dir = output_dir,
    model = model,
    times = times
  )

  invisible(output_dir)
}


# --- Run A2: With across skill ---

run_A2_with_skills <- function(times = 5, model = "gpt-4o-mini") {

  cat("\n")
  cat(strrep("#", 70), "\n")
  cat("# ACROSS TRIAL A2: With across skill\n")
  cat(strrep("#", 70), "\n\n")

  output_dir <- "dev/results/across-test/trial_A2_with_skills"

  run_experiment(
    run_fn = run_llm_ellmer_with_skills,
    prompt = ACROSS_PROMPT,
    data = list(wide_data = WIDE_DATA),
    output_dir = output_dir,
    model = model,
    times = times
  )

  invisible(output_dir)
}


# --- Run full experiment ---

run_across_experiment <- function(times = 5, model = "gpt-4o-mini") {

  cat("\n")
  cat(strrep("=", 70), "\n")
  cat("ACROSS EXPERIMENT - Tidyselect in Summarize\n")
  cat(strrep("=", 70), "\n")
  cat("\n")
  cat("Model:", model, "\n")
  cat("Runs per trial:", times, "\n")
  cat("\n")
  cat("This tests the across() pattern for summarizing multiple columns.\n")
  cat("Common LLM error: sum(starts_with(...)) instead of across(..., sum)\n")
  cat("\n")

  start_time <- Sys.time()

  a1_dir <- run_A1_no_skills(times = times, model = model)
  a2_dir <- run_A2_with_skills(times = times, model = model)

  total_time <- as.numeric(difftime(Sys.time(), start_time, units = "mins"))

  cat("\n")
  cat(strrep("=", 70), "\n")
  cat("EXPERIMENT COMPLETE\n")
  cat(strrep("=", 70), "\n")
  cat("\n")
  cat("Total time:", round(total_time, 1), "minutes\n")
  cat("\n")
  cat("Results saved to:\n")
  cat("  A1 (no skills):", a1_dir, "\n")
  cat("  A2 (with skills):", a2_dir, "\n")
  cat("\n")
  cat("To analyze results:\n")
  cat("  compare_trials('dev/results/across-test')\n")

  invisible(list(a1 = a1_dir, a2 = a2_dir))
}


# --- Expected correct output ---
#
# The LLM should produce:
#
#   category value_jan value_feb value_mar
# 1        A        30        40        34
# 2        B        70        80        74
# 3        C       110       120       114
#
# Calculations:
#   A: jan=10+20=30, feb=15+25=40, mar=12+22=34
#   B: jan=30+40=70, feb=35+45=80, mar=32+42=74
#   C: jan=50+60=110, feb=55+65=120, mar=52+62=114


compare_across_experiment <- function() {
  compare_trials("dev/results/across-test")
}
