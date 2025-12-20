# Skills Experiment - EXTREME MODE
#
# A task specifically designed to trigger common LLM failures:
# 1. dplyr::pivot_wider (WRONG) vs tidyr::pivot_wider (CORRECT)
# 2. Backtick column names after pivoting on numeric values
# 3. Lag without proper grouping/sorting
# 4. NA handling in division
#
# Without skills, gpt-4o-mini should fail most of the time.
#
# Usage:
#   source("dev/experiments/run-skills-experiment-hard.R")
#   run_skills_experiment_hard()

source("dev/harness.R")

# Data with NUMERIC values that become column names after pivot
# This triggers the backtick requirement
QUARTERLY_DATA <- data.frame(
  store = rep(c("Store1", "Store2"), each = 8),
  quarter = rep(c(1, 2, 3, 4), times = 4),  # NUMERIC - becomes column names `1`, `2`, `3`, `4`
  year = rep(c(2023, 2024), each = 4, times = 2),
  revenue = c(
    # Store1: 2023 Q1-Q4, 2024 Q1-Q4
    100, 120, 110, 130,  # 2023
    140, 150, 145, 160,  # 2024
    # Store2: 2023 Q1-Q4, 2024 Q1-Q4
    80, 90, 85, 95,      # 2023
    100, 110, 105, 120   # 2024
  ),
  stringsAsFactors = FALSE
)

# This prompt is DESIGNED to trigger specific failures
EXTREME_PROMPT <- '
Using quarterly_data, create a year-over-year comparison table:

1. For each store+quarter combination, calculate the previous year revenue:
   - Group by store and quarter
   - Sort by year within each group
   - Use lag to get prev_year_revenue (the same quarter from previous year)
   - Calculate yoy_growth: (revenue - prev_year_revenue) / prev_year_revenue
   - Round yoy_growth to 2 decimal places
   - Replace NA values in yoy_growth with 0

2. Filter to keep only 2024 data (since 2023 has no previous year to compare)

3. Pivot the data so quarters become columns:
   - Rows: store
   - Columns: one column per quarter showing yoy_growth
   - Column names should be: q1_growth, q2_growth, q3_growth, q4_growth
   - Fill missing values with 0

4. Add a column "avg_growth": the average of all four quarter growth values, rounded to 2 decimals

5. Add a column "best_quarter": the quarter number (1, 2, 3, or 4) with highest growth
   Use case_when to determine which quarter had the max growth.

Final columns: store, q1_growth, q2_growth, q3_growth, q4_growth, avg_growth, best_quarter
Sort by store alphabetically.
'

# KNOWN FAILURE MODES THIS TRIGGERS:
#
# 1. PIVOT PACKAGE ERROR (very common):
#    LLM writes: dplyr::pivot_wider(...)
#    Should be:  tidyr::pivot_wider(...)
#
# 2. BACKTICK COLUMN NAMES (very common):
#    After pivot on quarter (1,2,3,4), columns are `1`, `2`, `3`, `4`
#    LLM writes: mutate(avg = (1 + 2 + 3 + 4) / 4)  # WRONG - adds numbers
#    Should be:  mutate(avg = (`1` + `2` + `3` + `4`) / 4)
#
# 3. LAG WITHOUT PROPER GROUPING:
#    Must group_by(store, quarter) before lag
#    Must arrange(year) within groups
#
# 4. RENAME TIMING:
#    Must rename columns from `1` to q1_growth AFTER calculations
#    Or use names_prefix/names_glue in pivot_wider
#
# 5. BEST_QUARTER LOGIC:
#    Complex case_when with backtick columns


# --- Run E1: No skills (baseline) ---

run_E1_hard_no_skills <- function(times = 5, model = "gpt-4o-mini") {

  cat("\n")
  cat(strrep("#", 70), "\n")
  cat("# EXTREME TRIAL E1: No skills (baseline)\n")
  cat(strrep("#", 70), "\n\n")

  output_dir <- "dev/results/skills-test-hard/trial_E1_no_skills"

  run_experiment(
    run_fn = run_llm_ellmer_with_preview_and_validation,
    prompt = EXTREME_PROMPT,
    data = list(quarterly_data = QUARTERLY_DATA),
    output_dir = output_dir,
    model = model,
    times = times
  )

  invisible(output_dir)
}


# --- Run E2: With skills ---

run_E2_hard_with_skills <- function(times = 5, model = "gpt-4o-mini") {

  cat("\n")
  cat(strrep("#", 70), "\n")
  cat("# EXTREME TRIAL E2: With skills\n")
  cat(strrep("#", 70), "\n\n")

  output_dir <- "dev/results/skills-test-hard/trial_E2_with_skills"

  run_experiment(
    run_fn = run_llm_ellmer_with_skills,
    prompt = EXTREME_PROMPT,
    data = list(quarterly_data = QUARTERLY_DATA),
    output_dir = output_dir,
    model = model,
    times = times
  )

  invisible(output_dir)
}


# --- Run full experiment ---

run_skills_experiment_hard <- function(times = 5, model = "gpt-4o-mini") {

  cat("\n")
  cat(strrep("=", 70), "\n")
  cat("SKILLS EXPERIMENT - EXTREME MODE\n")
  cat(strrep("=", 70), "\n")
  cat("\n")
  cat("Model:", model, "\n")
  cat("Runs per trial:", times, "\n")
  cat("\n")
  cat("This task is DESIGNED to trigger common LLM failures:\n")
  cat("  1. dplyr::pivot_wider vs tidyr::pivot_wider\n")
  cat("  2. Backtick column names after numeric pivot\n")
  cat("  3. Lag without grouping/sorting\n")
  cat("  4. Complex case_when with pivoted columns\n")
  cat("\n")
  cat("Expected: E1 should fail often, E2 should succeed more\n")
  cat("\n")

  start_time <- Sys.time()

  # Run E1 (no skills)
  e1_dir <- run_E1_hard_no_skills(times = times, model = model)

  # Run E2 (with skills)
  e2_dir <- run_E2_hard_with_skills(times = times, model = model)

  total_time <- as.numeric(difftime(Sys.time(), start_time, units = "mins"))

  cat("\n")
  cat(strrep("=", 70), "\n")
  cat("EXPERIMENT COMPLETE\n")
  cat(strrep("=", 70), "\n")
  cat("\n")
  cat("Total time:", round(total_time, 1), "minutes\n")
  cat("\n")
  cat("Results saved to:\n")
  cat("  E1 (no skills):", e1_dir, "\n")
  cat("  E2 (with skills):", e2_dir, "\n")
  cat("\n")
  cat("To analyze results:\n")
  cat("  compare_trials('dev/results/skills-test-hard')\n")

  invisible(list(e1 = e1_dir, e2 = e2_dir))
}


# --- Expected correct output ---
#
# The LLM should produce:
#
#    store q1_growth q2_growth q3_growth q4_growth avg_growth best_quarter
# 1 Store1       0.4      0.25      0.32      0.23       0.30            1
# 2 Store2      0.25      0.22      0.24      0.26       0.24            4
#
# Calculations for Store1:
#   Q1: (140-100)/100 = 0.40
#   Q2: (150-120)/120 = 0.25
#   Q3: (145-110)/110 = 0.318 -> 0.32
#   Q4: (160-130)/130 = 0.231 -> 0.23
#   avg: (0.40 + 0.25 + 0.32 + 0.23) / 4 = 0.30
#   best: Q1 (0.40 is highest)
#
# Calculations for Store2:
#   Q1: (100-80)/80 = 0.25
#   Q2: (110-90)/90 = 0.222 -> 0.22
#   Q3: (105-85)/85 = 0.235 -> 0.24
#   Q4: (120-95)/95 = 0.263 -> 0.26
#   avg: (0.25 + 0.22 + 0.24 + 0.26) / 4 = 0.24 (rounded)
#   best: Q4 (0.26 is highest)


compare_skills_experiment_hard <- function() {
  compare_trials("dev/results/skills-test-hard")
}
