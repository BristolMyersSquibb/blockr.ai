# Medium Difficulty Experiment
#
# Tests a prompt that's challenging but not impossible for gpt-4o-mini.
# The prompt requires:
# - Group-by operations
# - Multiple derived columns
# - Percentage calculations (tricky for namespace)
# - Ranking within groups
#
# This should be hard enough that baseline sometimes fails on namespace,
# but simple enough that deterministic can iterate to success.
#
# Usage:
#   source("dev/experiments/run-medium-experiment.R")
#   run_medium_experiment()

library(blockr)
pkgload::load_all()
source("dev/harness.R")

# TRICKY prompt - requires getting calculation order right
# Easy to mess up by doing operations in wrong order
#
MEDIUM_PROMPT <- '
Calculate a "relative_efficiency" score for each car:

1. First, calculate each car mpg relative to overall mean mpg (not group mean!)
   relative_mpg = (mpg - overall_mean_mpg) / overall_mean_mpg * 100

2. Then, for each cyl group separately:
   - Rank cars by this relative_mpg (highest = rank 1)
   - Calculate "pct_rank": what percentile is this car within its cyl group?
     (rank 1 = 100th percentile, last rank = ~0th percentile)

Keep: cyl, mpg, hp, relative_mpg, rank_in_group, pct_rank
Sort by cyl, then rank_in_group.
Round to 1 decimal place.

Note: relative_mpg uses OVERALL mean, but ranking is within GROUPS.
'

# Data
MEDIUM_DATA <- mtcars


# --- Run A: Tool-based baseline ---

run_A_baseline <- function(times = 5, model = "gpt-4o-mini") {

  cat("\n")
  cat(strrep("#", 70), "\n")
  cat("# TRIAL A: Tool-based baseline\n")
  cat(strrep("#", 70), "\n\n")

  output_dir <- "dev/results/medium-test/trial_A_baseline"

  run_experiment(
    run_fn = run_llm_ellmer_with_preview,
    prompt = MEDIUM_PROMPT,
    data = list(data = MEDIUM_DATA),
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
  cat("# TRIAL C: Deterministic loop\n")
  cat(strrep("#", 70), "\n\n")

  output_dir <- "dev/results/medium-test/trial_C_deterministic"

  run_experiment(
    run_fn = run_llm_deterministic_loop,
    prompt = MEDIUM_PROMPT,
    data = list(data = MEDIUM_DATA),
    output_dir = output_dir,
    model = model,
    times = times
  )

  invisible(output_dir)
}


# --- Run full experiment ---

run_medium_experiment <- function(times = 7, model = "gpt-4o-mini") {

  cat("\n")
  cat(strrep("=", 70), "\n")
  cat("MEDIUM DIFFICULTY EXPERIMENT\n")
  cat(strrep("=", 70), "\n")
  cat("\n")
  cat("Model:", model, "\n")
  cat("Runs per trial:", times, "\n")
  cat("\n")
  cat("Prompt:\n")
  cat(MEDIUM_PROMPT, "\n")
  cat("\n")
  cat("This prompt requires:\n")
  cat("  - Group-by + summarize\n")
  cat("  - Percentage of total calculation\n")
  cat("  - Ratio calculation\n")
  cat("  - Rounding\n")
  cat("  - Sorting\n")
  cat("\n")

  start_time <- Sys.time()

  # Run both trials
  run_A_baseline(times = times, model = model)
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
  cat("  compare_trials('dev/results/medium-test')\n")

  invisible("dev/results/medium-test")
}


# Quick test
run_medium_quick <- function(model = "gpt-4o-mini") {
  run_medium_experiment(times = 1, model = model)
}
