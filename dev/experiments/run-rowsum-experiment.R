# Row-wise Sum Experiment
#
# Tests a CONSISTENT failure pattern:
# Using rowSums with dplyr::select(., ...) inside mutate() with native pipe
#
# WRONG (LLM always tries this):
#   data |> mutate(total = rowSums(dplyr::select(., -store)))
#   Error: object '.' not found
#
# CORRECT (skill teaches this):
#   data |> mutate(total = rowSums(dplyr::across(where(is.numeric))))
#
# This trap is:
# 1. Very consistent - LLM makes this mistake every time
# 2. Non-obvious fix - requires knowing across() pattern
# 3. Skill clearly helps - tested interactively
#
# Three trials:
# R1: No skills (baseline)
# R2: All skills in prompt (naive approach)
# R3: Skills via tool (progressive disclosure - Claude Code style)
#
# Usage:
#   source("dev/experiments/run-rowsum-experiment.R")
#   run_rowsum_experiment()

source("dev/harness.R")

# Data for pivot + rowsum
ROWSUM_DATA <- data.frame(
 store = rep(c("Store1", "Store2"), each = 4),
 quarter = rep(1:4, times = 2),
 sales = c(100, 120, 110, 130, 80, 90, 85, 95),
 stringsAsFactors = FALSE
)

# Prompt that triggers the failure
ROWSUM_PROMPT <- '
Using data, pivot so quarters become columns (1, 2, 3, 4).
Then add a total column that is the row-wise sum of all four quarter columns.
Do not list columns individually - use a pattern or function approach.
'

# Expected output:
#   store    `1`   `2`   `3`   `4` total
# 1 Store1   100   120   110   130   460
# 2 Store2    80    90    85    95   350


# --- Run R1: No skills (baseline) ---

run_R1_no_skills <- function(times = 5, model = "gpt-4o-mini") {

 cat("\n")
 cat(strrep("#", 70), "\n")
 cat("# ROWSUM TRIAL R1: No skills (baseline)\n")
 cat(strrep("#", 70), "\n\n")

 output_dir <- "dev/results/rowsum-test/trial_R1_no_skills"

 run_experiment(
   run_fn = run_llm_ellmer_with_preview_and_validation,
   prompt = ROWSUM_PROMPT,
   data = list(data = ROWSUM_DATA),
   output_dir = output_dir,
   model = model,
   times = times
 )

 invisible(output_dir)
}


# --- Run R2: With all skills in prompt (naive approach) ---

run_R2_with_skills <- function(times = 5, model = "gpt-4o-mini") {

 cat("\n")
 cat(strrep("#", 70), "\n")
 cat("# ROWSUM TRIAL R2: All skills in prompt (naive)\n")
 cat(strrep("#", 70), "\n\n")

 output_dir <- "dev/results/rowsum-test/trial_R2_skills_in_prompt"

 run_experiment(
   run_fn = run_llm_ellmer_with_skills,
   prompt = ROWSUM_PROMPT,
   data = list(data = ROWSUM_DATA),
   output_dir = output_dir,
   model = model,
   times = times
 )

 invisible(output_dir)
}


# --- Run R3: With skill_tool (progressive disclosure) ---

run_R3_with_skill_tool <- function(times = 5, model = "gpt-4o-mini") {

 cat("\n")
 cat(strrep("#", 70), "\n")
 cat("# ROWSUM TRIAL R3: Skills via tool (progressive disclosure)\n")
 cat(strrep("#", 70), "\n\n")

 output_dir <- "dev/results/rowsum-test/trial_R3_skill_tool"

 run_experiment(
   run_fn = run_llm_ellmer_with_skill_tool,
   prompt = ROWSUM_PROMPT,
   data = list(data = ROWSUM_DATA),
   output_dir = output_dir,
   model = model,
   times = times
 )

 invisible(output_dir)
}


# --- Run full experiment ---

run_rowsum_experiment <- function(times = 5, model = "gpt-4o-mini") {

 cat("\n")
 cat(strrep("=", 70), "\n")
 cat("ROWSUM EXPERIMENT - Native Pipe + rowSums Trap\n")
 cat(strrep("=", 70), "\n")
 cat("\n")
 cat("Model:", model, "\n")
 cat("Runs per trial:", times, "\n")
 cat("\n")
 cat("This tests the rowSums + native pipe pattern.\n")
 cat("Common LLM error: rowSums(dplyr::select(., ...)) - '.' not found\n")
 cat("Correct pattern: rowSums(dplyr::across(where(is.numeric)))\n")
 cat("\n")
 cat("Trials:\n")
 cat("  R1: No skills (baseline)\n")
 cat("  R2: All skills in prompt (naive - 10k+ tokens)\n")
 cat("  R3: Skills via tool (progressive disclosure - ~200 tokens)\n")
 cat("\n")

 start_time <- Sys.time()

 r1_dir <- run_R1_no_skills(times = times, model = model)
 r2_dir <- run_R2_with_skills(times = times, model = model)
 r3_dir <- run_R3_with_skill_tool(times = times, model = model)

 total_time <- as.numeric(difftime(Sys.time(), start_time, units = "mins"))

 cat("\n")
 cat(strrep("=", 70), "\n")
 cat("EXPERIMENT COMPLETE\n")
 cat(strrep("=", 70), "\n")
 cat("\n")
 cat("Total time:", round(total_time, 1), "minutes\n")
 cat("\n")
 cat("Results saved to:\n")
 cat("  R1 (no skills):", r1_dir, "\n")
 cat("  R2 (skills in prompt):", r2_dir, "\n")
 cat("  R3 (skill tool):", r3_dir, "\n")
 cat("\n")
 cat("To analyze results:\n")
 cat("  compare_trials('dev/results/rowsum-test')\n")

 invisible(list(r1 = r1_dir, r2 = r2_dir, r3 = r3_dir))
}


compare_rowsum_experiment <- function() {
 compare_trials("dev/results/rowsum-test")
}
