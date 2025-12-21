# Linear Regression Experiment
#
# Tests the complex linear model + ranking prompt that trips up gpt-4o-mini.
# The model struggles with:
# - stats::lm() namespace (keeps trying base::lm)
# - Group-wise model fitting
# - Multiple derived columns
#
# Usage:
#   source("dev/experiments/run-lm-regression-experiment.R")
#   run_lm_experiment()

library(blockr)
pkgload::load_all()
source("dev/harness.R")

# The complex prompt
LM_PROMPT <- '
For each cylinder group (cyl), fit a linear model predicting mpg from hp.

Add these columns to the original data:
- predicted_mpg: the fitted value from the group\'s linear model
- residual: actual mpg minus predicted mpg
- efficiency_rank: rank cars within each cyl group by residual (highest residual = rank 1, meaning better than predicted)

Keep columns: cyl, hp, mpg, predicted_mpg, residual, efficiency_rank
Sort by cyl, then by efficiency_rank.
'

# Data
LM_DATA <- mtcars


# --- Run A: Tool-based baseline (with preview) ---

run_A_baseline <- function(times = 5, model = "gpt-4o-mini") {

  cat("\n")
  cat(strrep("#", 70), "\n")
  cat("# TRIAL A: Tool-based baseline (with preview)\n")
  cat(strrep("#", 70), "\n\n")

  output_dir <- "dev/results/lm-regression/trial_A_baseline"

  run_experiment(
    run_fn = run_llm_ellmer_with_preview,
    prompt = LM_PROMPT,
    data = list(data = LM_DATA),
    output_dir = output_dir,
    model = model,
    times = times
  )

  invisible(output_dir)
}


# --- Run B: Tool-based with preview + validation ---

run_B_with_validation <- function(times = 5, model = "gpt-4o-mini") {

  cat("\n")
  cat(strrep("#", 70), "\n")
  cat("# TRIAL B: Tool-based with preview + validation\n")
  cat(strrep("#", 70), "\n\n")

  output_dir <- "dev/results/lm-regression/trial_B_preview_validation"

  run_experiment(
    run_fn = run_llm_ellmer_with_preview_and_validation,
    prompt = LM_PROMPT,
    data = list(data = LM_DATA),
    output_dir = output_dir,
    model = model,
    times = times
  )

  invisible(output_dir)
}


# --- Run C: Deterministic loop ---

run_C_deterministic <- function(times = 5, model = "gpt-4o-mini") {

  cat("\n")
  cat(strrep("#", 70), "\n")
  cat("# TRIAL C: Deterministic loop (system-controlled)\n")
  cat(strrep("#", 70), "\n\n")

  output_dir <- "dev/results/lm-regression/trial_C_deterministic"

  run_experiment(
    run_fn = run_llm_deterministic_loop,
    prompt = LM_PROMPT,
    data = list(data = LM_DATA),
    output_dir = output_dir,
    model = model,
    times = times
  )

  invisible(output_dir)
}


# --- Run full experiment ---

run_lm_experiment <- function(times = 3, model = "gpt-4o-mini") {

  cat("\n")
  cat(strrep("=", 70), "\n")
  cat("LINEAR MODEL REGRESSION EXPERIMENT\n")
  cat(strrep("=", 70), "\n")
  cat("\n")
  cat("Model:", model, "\n")
  cat("Runs per trial:", times, "\n")
  cat("\n")
  cat("Prompt:\n")
  cat(LM_PROMPT, "\n")
  cat("\n")
  cat("This prompt requires:\n")
  cat("  - stats::lm() for linear model (NOT base::lm!)\n")
  cat("  - Group-wise model fitting\n")
  cat("  - Multiple derived columns\n")
  cat("  - Ranking within groups\n")
  cat("\n")

  start_time <- Sys.time()

  # Run all trials
  run_A_baseline(times = times, model = model)
  run_B_with_validation(times = times, model = model)
  run_C_deterministic(times = times, model = model)

  total_time <- as.numeric(difftime(Sys.time(), start_time, units = "mins"))

  cat("\n")
  cat(strrep("=", 70), "\n")
  cat("EXPERIMENT COMPLETE\n")
  cat(strrep("=", 70), "\n")
  cat("\n")
  cat("Total time:", round(total_time, 1), "minutes\n")
  cat("\n")
  cat("To compare trials:\n")
  cat("  compare_trials('dev/results/lm-regression')\n")

  invisible("dev/results/lm-regression")
}


# Quick test (1 run each)
run_lm_quick <- function(model = "gpt-4o-mini") {
  run_lm_experiment(times = 1, model = model)
}
