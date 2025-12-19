# Run pivot experiment - a harder task where preview should help
# This tests pivot operations which are commonly done incorrectly

devtools::load_all()
source("dev/harness.R")

prompt <- "
Using the data, create a pivot table showing:
- Rows: number of gears (gear)
- Columns: number of cylinders (cyl)
- Values: average mpg, rounded to 1 decimal

The result should have columns: gear, cyl_4, cyl_6, cyl_8
Fill missing combinations with 0.
Sort by gear ascending.
"

N_RUNS <- 10
MODEL <- "gpt-4o-mini"

cat("\n")
cat(strrep("=", 70), "\n")
cat("PIVOT EXPERIMENT: 4 VARIANTS x", N_RUNS, "RUNS\n")
cat(strrep("=", 70), "\n\n")

# Variant A: baseline
cat("\n### VARIANT A: BASELINE ###\n")
run_experiment(
  run_fn = run_llm_ellmer,
  prompt = prompt,
  data = mtcars,
  output_dir = "dev/results/mtcars-pivot/trial_A_baseline",
  model = MODEL,
  times = N_RUNS
)

# Variant B: preview
cat("\n### VARIANT B: PREVIEW ###\n")
run_experiment(
  run_fn = run_llm_ellmer_with_preview,
  prompt = prompt,
  data = mtcars,
  output_dir = "dev/results/mtcars-pivot/trial_B_preview",
  model = MODEL,
  times = N_RUNS
)

# Variant C: validation
cat("\n### VARIANT C: VALIDATION ###\n")
run_experiment(
  run_fn = run_llm_ellmer_with_validation,
  prompt = prompt,
  data = mtcars,
  output_dir = "dev/results/mtcars-pivot/trial_C_validation",
  model = MODEL,
  times = N_RUNS
)

# Variant D: preview + validation
cat("\n### VARIANT D: PREVIEW + VALIDATION ###\n")
run_experiment(
  run_fn = run_llm_ellmer_with_preview_and_validation,
  prompt = prompt,
  data = mtcars,
  output_dir = "dev/results/mtcars-pivot/trial_D_preview_validation",
  model = MODEL,
  times = N_RUNS
)

cat("\n")
cat(strrep("=", 70), "\n")
cat("ALL RUNS COMPLETE\n")
cat(strrep("=", 70), "\n")

# Show comparison
compare_trials("dev/results/mtcars-pivot")
