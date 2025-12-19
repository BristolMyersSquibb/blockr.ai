# Run complex experiment - combining multiple tricky operations
# Pivot + percentage + filtering + renaming - lots of places to go wrong

devtools::load_all()
source("dev/harness.R")

prompt <- "
Using the data (mtcars), perform these steps:

1. Filter to cars with mpg > 15
2. Create a pivot table:
   - Rows: number of gears (gear)
   - Columns: number of cylinders (cyl)
   - Values: count of cars
3. Add a 'total' column summing across cyl columns
4. Add a 'pct_8cyl' column: percentage of 8-cylinder cars out of total for each gear (as decimal, must be between 0 and 1)
5. Rename cyl columns to: n_4cyl, n_6cyl, n_8cyl

Final columns: gear, n_4cyl, n_6cyl, n_8cyl, total, pct_8cyl
Fill missing values with 0.
Sort by gear ascending.
Round pct_8cyl to 2 decimals.
"

N_RUNS <- 5
MODEL <- "gpt-4o-mini"

cat("\n")
cat(strrep("=", 70), "\n")
cat("COMPLEX EXPERIMENT: 4 VARIANTS x", N_RUNS, "RUNS\n")
cat(strrep("=", 70), "\n\n")

# Variant A: baseline
cat("\n### VARIANT A: BASELINE ###\n")
run_experiment(
  run_fn = run_llm_ellmer,
  prompt = prompt,
  data = mtcars,
  output_dir = "dev/results/mtcars-complex/trial_A_baseline",
  model = MODEL,
  times = N_RUNS
)

# Variant B: preview
cat("\n### VARIANT B: PREVIEW ###\n")
run_experiment(
  run_fn = run_llm_ellmer_with_preview,
  prompt = prompt,
  data = mtcars,
  output_dir = "dev/results/mtcars-complex/trial_B_preview",
  model = MODEL,
  times = N_RUNS
)

# Variant C: validation
cat("\n### VARIANT C: VALIDATION ###\n")
run_experiment(
  run_fn = run_llm_ellmer_with_validation,
  prompt = prompt,
  data = mtcars,
  output_dir = "dev/results/mtcars-complex/trial_C_validation",
  model = MODEL,
  times = N_RUNS
)

# Variant D: preview + validation
cat("\n### VARIANT D: PREVIEW + VALIDATION ###\n")
run_experiment(
  run_fn = run_llm_ellmer_with_preview_and_validation,
  prompt = prompt,
  data = mtcars,
  output_dir = "dev/results/mtcars-complex/trial_D_preview_validation",
  model = MODEL,
  times = N_RUNS
)

cat("\n")
cat(strrep("=", 70), "\n")
cat("ALL RUNS COMPLETE\n")
cat(strrep("=", 70), "\n")

# Show comparison
compare_trials("dev/results/mtcars-complex")
