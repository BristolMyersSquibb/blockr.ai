# Deterministic Loop Experiment
#
# Compares three approaches:
# - A: Tool-based baseline (no validation)
# - D: Tool-based with preview + validation
# - E: Deterministic loop (system-controlled, no tools)
#
# The deterministic loop (E) is simpler:
# 1. Data preview shown upfront (not a tool)
# 2. LLM writes code as plain text
# 3. System runs code automatically
# 4. On error: show error, iterate
# 5. On success: show result, LLM says DONE or fixes
#
# Expected outcomes:
# - E should be faster (no tool call overhead)
# - E should be more reliable (can't skip validation)
# - E should use fewer tokens (no tool schemas)
#
# Usage:
#   source("dev/experiments/run-deterministic-experiment.R")
#   run_deterministic_experiment()

source("dev/harness.R")

# Use the same mtcars-complex task from original experiment
MTCARS_DATA <- mtcars

MTCARS_PROMPT <- '
Using data, group by cyl and calculate:
1. mean hp
2. mean mpg
3. count of cars
Then calculate pct_of_total as count divided by total cars.
Sort by cyl ascending.
'

# Expected output:
#   cyl  mean_hp  mean_mpg  count  pct_of_total
# 1   4     82.6     26.7     11         0.344
# 2   6    122.3     19.7      7         0.219
# 3   8    209.2     15.1     14         0.438


# --- Run A: Tool-based baseline (no validation) ---

run_A_baseline <- function(times = 5, model = "gpt-4o-mini") {

  cat("\n")
  cat(strrep("#", 70), "\n")
  cat("# TRIAL A: Tool-based baseline (no validation)\n")
  cat(strrep("#", 70), "\n\n")

  output_dir <- "dev/results/deterministic-test/trial_A_baseline"

  run_experiment(
    run_fn = run_llm_ellmer_with_preview,
    prompt = MTCARS_PROMPT,
    data = list(data = MTCARS_DATA),
    output_dir = output_dir,
    model = model,
    times = times
  )

  invisible(output_dir)
}


# --- Run D: Tool-based with preview + validation ---

run_D_with_validation <- function(times = 5, model = "gpt-4o-mini") {

  cat("\n")
  cat(strrep("#", 70), "\n")
  cat("# TRIAL D: Tool-based with preview + validation\n")
  cat(strrep("#", 70), "\n\n")

  output_dir <- "dev/results/deterministic-test/trial_D_preview_validation"

  run_experiment(
    run_fn = run_llm_ellmer_with_preview_and_validation,
    prompt = MTCARS_PROMPT,
    data = list(data = MTCARS_DATA),
    output_dir = output_dir,
    model = model,
    times = times
  )

  invisible(output_dir)
}


# --- Run E: Deterministic loop (system-controlled) ---

run_E_deterministic <- function(times = 5, model = "gpt-4o-mini") {

  cat("\n")
  cat(strrep("#", 70), "\n")
  cat("# TRIAL E: Deterministic loop (system-controlled)\n")
  cat(strrep("#", 70), "\n\n")

  output_dir <- "dev/results/deterministic-test/trial_E_deterministic"

  run_experiment(
    run_fn = run_llm_deterministic_loop,
    prompt = MTCARS_PROMPT,
    data = list(data = MTCARS_DATA),
    output_dir = output_dir,
    model = model,
    times = times
  )

  invisible(output_dir)
}


# --- Run full experiment (just E, compare to existing A/D results) ---

run_deterministic_experiment <- function(times = 5, model = "gpt-4o-mini") {

  cat("\n")
  cat(strrep("=", 70), "\n")
  cat("DETERMINISTIC LOOP EXPERIMENT\n")
  cat(strrep("=", 70), "\n")
  cat("\n")
  cat("Model:", model, "\n")
  cat("Runs per trial:", times, "\n")
  cat("\n")
  cat("Running trial E (deterministic loop).\n")
  cat("Compare results against existing mtcars-complex A/D:\n")
  cat("  A (baseline): 40% correct, 24.5s avg\n")
  cat("  D (preview+validation): 100% correct, 39.0s avg\n")
  cat("\n")

  start_time <- Sys.time()

  e_dir <- run_E_deterministic(times = times, model = model)

  total_time <- as.numeric(difftime(Sys.time(), start_time, units = "mins"))

  cat("\n")
  cat(strrep("=", 70), "\n")
  cat("EXPERIMENT COMPLETE\n")
  cat(strrep("=", 70), "\n")
  cat("\n")
  cat("Total time:", round(total_time, 1), "minutes\n")
  cat("\n")
  cat("Results saved to:", e_dir, "\n")
  cat("\n")
  cat("To analyze:\n")
  cat("  compare_trials('dev/results/deterministic-test')\n")

  invisible(e_dir)
}


compare_deterministic_experiment <- function() {
  compare_trials("dev/results/deterministic-test")
}
