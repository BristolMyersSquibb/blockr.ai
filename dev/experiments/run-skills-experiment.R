# Skills Experiment Runner
#
# Tests whether skills improve LLM success rate on complex tasks.
#
# Experiment design:
#   E1: preview+validation (baseline) - no skills
#   E2: preview+validation + skills - skills injected
#
# Task: Time-series lag calculation with multiple pitfalls
#
# Usage:
#   source("dev/experiments/run-skills-experiment.R")
#   run_skills_experiment()  # runs both trials
#
# Results saved to:
#   dev/results/skills-test/trial_E1_no_skills/
#   dev/results/skills-test/trial_E2_with_skills/

# Load harness
source("dev/harness.R")

# Test data
SALES_DATA <- data.frame(
  region = rep(c("North", "South"), each = 4),
  date = rep(c("2024-01-15", "2024-02-15", "2024-03-15", "2024-04-15"), 2),
  revenue = c(1000, 1200, 1100, 1400,  # North
              800, 750, 900, 850)       # South
)

# Prompt with multiple pitfalls
SKILLS_PROMPT <- "
Using the data (sales_data), perform these steps:

1. Parse the 'date' column as a Date (format: \"YYYY-MM-DD\")
2. For each 'region', calculate the previous month's 'revenue' as 'prev_revenue'
   (use lag, ordered by date within each region)
3. Calculate 'revenue_change' as: (revenue - prev_revenue) / prev_revenue
   - Express as decimal (0-1 range for positive, negative for decline)
   - Round to 3 decimal places
4. Replace NA values in 'revenue_change' with 0 (first month has no previous)
5. Add a 'growth' column: \"up\" if revenue_change > 0, \"down\" if < 0, \"flat\" if = 0

Final columns: region, date, revenue, prev_revenue, revenue_change, growth
Sort by region, then by date ascending.
"

# Expected output for validation
EXPECTED_OUTPUT <- data.frame(
  region = c("North", "North", "North", "North", "South", "South", "South", "South"),
  date = as.Date(c("2024-01-15", "2024-02-15", "2024-03-15", "2024-04-15",
                   "2024-01-15", "2024-02-15", "2024-03-15", "2024-04-15")),
  revenue = c(1000, 1200, 1100, 1400, 800, 750, 900, 850),
  prev_revenue = c(NA, 1000, 1200, 1100, NA, 800, 750, 900),
  revenue_change = c(0.000, 0.200, -0.083, 0.273, 0.000, -0.063, 0.200, -0.056),
  growth = c("flat", "up", "down", "up", "flat", "down", "up", "down"),
  stringsAsFactors = FALSE
)


# --- Run E1: No skills (baseline) ---

run_E1_no_skills <- function(times = 5, model = "gpt-4o-mini") {

  cat("\n")
  cat(strrep("#", 70), "\n")
  cat("# TRIAL E1: No skills (baseline)\n")
  cat(strrep("#", 70), "\n\n")

  output_dir <- "dev/results/skills-test/trial_E1_no_skills"

  run_experiment(
    run_fn = run_llm_ellmer_with_preview_and_validation,
    prompt = SKILLS_PROMPT,
    data = list(sales_data = SALES_DATA),
    output_dir = output_dir,
    model = model,
    times = times
  )

  invisible(output_dir)
}


# --- Run E2: With skills ---

run_E2_with_skills <- function(times = 5, model = "gpt-4o-mini") {

  cat("\n")
  cat(strrep("#", 70), "\n")
  cat("# TRIAL E2: With skills\n")
  cat(strrep("#", 70), "\n\n")

  output_dir <- "dev/results/skills-test/trial_E2_with_skills"

  run_experiment(
    run_fn = run_llm_ellmer_with_skills,
    prompt = SKILLS_PROMPT,
    data = list(sales_data = SALES_DATA),
    output_dir = output_dir,
    model = model,
    times = times
  )

  invisible(output_dir)
}


# --- Run full experiment ---

run_skills_experiment <- function(times = 5, model = "gpt-4o-mini") {

  cat("\n")
  cat(strrep("=", 70), "\n")
  cat("SKILLS EXPERIMENT\n")
  cat(strrep("=", 70), "\n")
  cat("\n")
  cat("Model:", model, "\n")
  cat("Runs per trial:", times, "\n")
  cat("\n")

  start_time <- Sys.time()

  # Run E1 (no skills)
  e1_dir <- run_E1_no_skills(times = times, model = model)

  # Run E2 (with skills)
  e2_dir <- run_E2_with_skills(times = times, model = model)

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
  cat("  compare_trials('dev/results/skills-test')\n")
  cat("\n")
  cat("Or ask Claude:\n")
  cat("  'Evaluate the runs in dev/results/skills-test'\n")

  invisible(list(e1 = e1_dir, e2 = e2_dir))
}


# --- Quick comparison helper ---

compare_skills_experiment <- function() {
  compare_trials("dev/results/skills-test")
}


# --- Analyze skill usage across runs ---

analyze_skill_usage <- function(trial_dir) {

  yaml_files <- list.files(trial_dir, pattern = "^run_\\d{3}\\.yaml$", full.names = TRUE)

  if (length(yaml_files) == 0) {
    cat("No run files found in:", trial_dir, "\n")
    return(invisible(NULL))
  }

  cat("Analyzing skill usage in", length(yaml_files), "runs...\n\n")

  results <- list()

  for (f in yaml_files) {
    content <- paste(readLines(f, warn = FALSE), collapse = "\n")

    # Check if skills were injected
    has_skills <- grepl("skills:", content)

    # Extract usage scores
    usage_scores <- list()
    if (has_skills) {
      # Parse time-series-lag usage score
      ts_match <- regmatches(content, regexpr("time-series-lag:[\\s\\S]*?usage_score: ([0-9.]+)", content, perl = TRUE))
      if (length(ts_match) > 0) {
        score <- as.numeric(gsub(".*usage_score: ([0-9.]+).*", "\\1", ts_match, perl = TRUE))
        usage_scores[["time-series-lag"]] <- score
      }
    }

    # Check if result is correct
    has_result <- grepl("has_result: true", content)

    results[[basename(f)]] <- list(
      file = basename(f),
      has_skills = has_skills,
      has_result = has_result,
      usage_scores = usage_scores
    )
  }

  # Print summary
  cat("Run Summary:\n")
  cat(strrep("-", 50), "\n")

  for (r in results) {
    skills_str <- if (r$has_skills) "yes" else "no"
    result_str <- if (r$has_result) "OK" else "FAIL"

    score_str <- if (length(r$usage_scores) > 0) {
      paste(names(r$usage_scores), "=", unlist(r$usage_scores), collapse = ", ")
    } else {
      "N/A"
    }

    cat(sprintf("  %s: skills=%s result=%s usage=%s\n",
                r$file, skills_str, result_str, score_str))
  }

  invisible(results)
}
