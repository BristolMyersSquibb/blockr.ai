# Run all 4 variants (A, B, C, D) 10 times each
# This script tests the mtcars horsepower task

devtools::load_all()
source("dev/harness.R")

prompt <- "
Calculate the total horsepower (hp) by number of cylinders (cyl).
Add a column pct_of_total showing each group's percentage of total hp.
The percentages must sum to 1.0. Round to 2 decimals.
Sort by total_hp descending.
Output columns: cyl, total_hp, pct_of_total
"

N_RUNS <- 10
MODEL <- "gpt-4o-mini"

cat("\n")
cat(strrep("=", 70), "\n")
cat("RUNNING 4 VARIANTS x", N_RUNS, "RUNS =", 4 * N_RUNS, "TOTAL RUNS\n")
cat(strrep("=", 70), "\n\n")

# Variant A: baseline
cat("\n### VARIANT A: BASELINE ###\n")
run_experiment(
  run_fn = run_llm_ellmer,
  prompt = prompt,
  data = mtcars,
  output_dir = "dev/results/mtcars-hp/trial_A_baseline",
  model = MODEL,
  times = N_RUNS
)

# Variant B: preview
cat("\n### VARIANT B: PREVIEW ###\n")
run_experiment(
  run_fn = run_llm_ellmer_with_preview,
  prompt = prompt,
  data = mtcars,
  output_dir = "dev/results/mtcars-hp/trial_B_preview",
  model = MODEL,
  times = N_RUNS
)

# Variant C: validation
cat("\n### VARIANT C: VALIDATION ###\n")
run_experiment(
  run_fn = run_llm_ellmer_with_validation,
  prompt = prompt,
  data = mtcars,
  output_dir = "dev/results/mtcars-hp/trial_C_validation",
  model = MODEL,
  times = N_RUNS
)

# Variant D: preview + validation
cat("\n### VARIANT D: PREVIEW + VALIDATION ###\n")
run_experiment(
  run_fn = run_llm_ellmer_with_preview_and_validation,
  prompt = prompt,
  data = mtcars,
  output_dir = "dev/results/mtcars-hp/trial_D_preview_validation",
  model = MODEL,
  times = N_RUNS
)

cat("\n")
cat(strrep("=", 70), "\n")
cat("ALL RUNS COMPLETE\n")
cat(strrep("=", 70), "\n")

# Show comparison
compare_trials("dev/results/mtcars-hp")
