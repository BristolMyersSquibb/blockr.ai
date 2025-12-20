# Experiment: Do Skills Improve LLM Success Rate?

## Hypothesis

Adding domain-specific skills to the system prompt will increase the success rate
on complex tasks, even when using our best approach (preview + validation).

## Design

### Comparison

| Trial | Variant | Skills | Description |
|-------|---------|--------|-------------|
| E1 | D (preview+validation) | None | Baseline - current best |
| E2 | D (preview+validation) | Yes | With skills injected |

### Task: Time-Series Lag Calculation

A complex task that requires:
1. Date parsing (lubridate pitfall)
2. Group-wise lag calculation (dplyr::lag within groups)
3. Percentage change calculation (division, rounding)
4. Handling NA values from lag

This task has multiple failure modes that a skill can address.

### Prompt

```
Using the data (sales_data), perform these steps:

1. Parse the 'date' column as a Date (format: "YYYY-MM-DD")
2. For each 'region', calculate the previous month's 'revenue' as 'prev_revenue'
   (use lag, ordered by date within each region)
3. Calculate 'revenue_change' as: (revenue - prev_revenue) / prev_revenue
   - Express as decimal (0-1 range for positive, negative for decline)
   - Round to 3 decimal places
4. Replace NA values in 'revenue_change' with 0 (first month has no previous)
5. Add a 'growth' column: "up" if revenue_change > 0, "down" if < 0, "flat" if = 0

Final columns: region, date, revenue, prev_revenue, revenue_change, growth
Sort by region, then by date ascending.
```

### Test Data

```r
sales_data <- data.frame(
  region = rep(c("North", "South"), each = 4),
  date = rep(c("2024-01-15", "2024-02-15", "2024-03-15", "2024-04-15"), 2),
  revenue = c(1000, 1200, 1100, 1400,  # North
              800, 750, 900, 850)       # South
)
```

### Expected Output

```
  region       date revenue prev_revenue revenue_change growth
1  North 2024-01-15    1000           NA          0.000   flat
2  North 2024-02-15    1200         1000          0.200     up
3  North 2024-03-15    1100         1200         -0.083   down
4  North 2024-04-15    1400         1100          0.273     up
5  South 2024-01-15     800           NA          0.000   flat
6  South 2024-02-15     750          800         -0.063   down
7  South 2024-03-15     900          750          0.200     up
8  South 2024-04-15     850          900         -0.056   down
```

### Known Pitfalls (that skill addresses)

1. **Date parsing**: Must use `lubridate::ymd()` or `as.Date()` with format
2. **Lag within groups**: Must `group_by()` before `lag()`, then `ungroup()`
3. **Lag ordering**: Must `arrange()` by date first, or use `order_by` argument
4. **NA handling**: First row per group has NA, must replace
5. **Division by zero**: If prev_revenue is 0 (not in this data, but good practice)

---

## Skill: time-series-lag

```yaml
---
name: time-series-lag
description: Calculate lagged values, period-over-period changes, and growth rates
  within groups. Use when user asks for previous period values, lag calculations,
  month-over-month or year-over-year comparisons, or growth rates.
---

# Time-Series Lag Calculations in R

## Critical Rules

1. **Group before lag**: Always `dplyr::group_by()` before using `dplyr::lag()`
2. **Sort before lag**: Data must be sorted by time within groups
3. **Ungroup after**: Always `dplyr::ungroup()` after grouped operations
4. **Handle first-row NA**: `dplyr::lag()` returns NA for first row in each group

## Standard Pattern

```r
data |>
  dplyr::arrange(group_col, date_col) |>
  dplyr::group_by(group_col) |>
  dplyr::mutate(
    prev_value = dplyr::lag(value_col, n = 1),
    change = (value_col - prev_value) / prev_value,
    change = round(change, 3),
    change = dplyr::coalesce(change, 0)  # Replace NA with 0
  ) |>
  dplyr::ungroup()
```

## Common Errors

### Wrong: Lag without grouping
```r
# WRONG - lags across all rows, not within groups
data |>
  dplyr::mutate(prev = dplyr::lag(value))

# CORRECT - lag within each group
data |>
  dplyr::group_by(region) |>
  dplyr::mutate(prev = dplyr::lag(value)) |>
  dplyr::ungroup()
```

### Wrong: Lag without sorting
```r
# WRONG - lag based on row order, not time order
data |>
  dplyr::group_by(region) |>
  dplyr::mutate(prev = dplyr::lag(value))

# CORRECT - sort first
data |>
  dplyr::arrange(region, date) |>
  dplyr::group_by(region) |>
  dplyr::mutate(prev = dplyr::lag(value))
```

### Wrong: Forgetting NA handling
```r
# WRONG - first row has NA, division produces NA
data |>
  dplyr::mutate(change = (value - prev) / prev)

# CORRECT - handle NA explicitly
data |>
  dplyr::mutate(
    change = dplyr::if_else(is.na(prev), 0, (value - prev) / prev)
  )
# OR
data |>
  dplyr::mutate(
    change = (value - prev) / prev,
    change = dplyr::coalesce(change, 0)
  )
```

## Date Parsing

If dates are strings, parse first:

```r
data |>
  dplyr::mutate(date = lubridate::ymd(date))
# OR
data |>
  dplyr::mutate(date = as.Date(date, format = "%Y-%m-%d"))
```

## Growth Labels

```r
data |>
  dplyr::mutate(
    growth = dplyr::case_when(
      change > 0 ~ "up",
      change < 0 ~ "down",
      TRUE ~ "flat"
    )
  )
```
```

---

## Implementation Steps

### 1. Create the skill file

```bash
mkdir -p .blockr/skills/time-series-lag
# Write SKILL.md with content above
```

### 2. Add skill loading to harness

```r
# In harness.R, add function to load and inject skills
load_skills <- function(skills_dir = ".blockr/skills") {
  skill_dirs <- list.dirs(skills_dir, recursive = FALSE, full.names = TRUE)

  skills <- list()
  for (dir in skill_dirs) {
    skill_file <- file.path(dir, "SKILL.md")
    if (file.exists(skill_file)) {
      content <- paste(readLines(skill_file, warn = FALSE), collapse = "\n")
      # Remove YAML frontmatter for injection
      content <- sub("^---.*?---\n*", "", content, perl = TRUE)
      skills[[basename(dir)]] <- content
    }
  }
  skills
}

inject_skills <- function(base_prompt, skills) {
  if (length(skills) == 0) return(base_prompt)

  skill_section <- paste(
    "\n\n# Reference Skills\n",
    "Follow these patterns when applicable:\n\n",
    paste(names(skills), skills, sep = "\n\n", collapse = "\n\n---\n\n"),
    sep = ""
  )

  paste0(base_prompt, skill_section)
}
```

### 3. Create variant with skills

```r
run_llm_ellmer_with_skills <- function(prompt, data, config,
                                        skills_dir = ".blockr/skills",
                                        max_validation_retries = 3) {
  # Same as run_llm_ellmer_with_preview_and_validation
  # but inject skills into system prompt

  # Load skills
  skills <- load_skills(skills_dir)

  # ... existing setup ...

  # Modify system prompt
  sys_prompt <- system_prompt(proxy, datasets, tools)
  sys_prompt <- inject_skills(sys_prompt, skills)

  # ... rest of function ...
}
```

### 4. Run experiment

```r
# Test data
sales_data <- data.frame(
  region = rep(c("North", "South"), each = 4),
  date = rep(c("2024-01-15", "2024-02-15", "2024-03-15", "2024-04-15"), 2),
  revenue = c(1000, 1200, 1100, 1400, 800, 750, 900, 850)
)

prompt <- "
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

# Trial E1: Without skills (baseline)
run_experiment(
  run_fn = run_llm_ellmer_with_preview_and_validation,
  prompt = prompt,
  data = sales_data,
  output_dir = "dev/results/skills-test/trial_E1_no_skills",
  model = "gpt-4o-mini",
  times = 5
)

# Trial E2: With skills
run_experiment(
  run_fn = run_llm_ellmer_with_skills,
  prompt = prompt,
  data = sales_data,
  output_dir = "dev/results/skills-test/trial_E2_with_skills",
  model = "gpt-4o-mini",
  times = 5
)
```

---

## Skill Tracking

### What to Track

1. **Skills injected**: Which skills were added to system prompt
2. **Skill patterns used**: Did the code follow skill guidance?
3. **Errors avoided**: Did skill prevent known pitfalls?

### Pattern Detection

For each run, check if the generated code follows skill patterns:

```r
detect_skill_usage <- function(code, skill_name) {
  patterns <- list(
    "time-series-lag" = list(
      "group_before_lag" = "group_by.*\\n.*lag\\(",
      "arrange_before_lag" = "arrange.*\\n.*group_by.*\\n.*lag\\(|arrange.*\\n.*lag\\(",
      "ungroup_after" = "lag\\(.*\\n.*ungroup\\(",
      "na_handling" = "coalesce|if_else.*is\\.na|replace_na",
      "case_when_growth" = "case_when.*up.*down|case_when.*down.*up"
    ),
    "pivot-table" = list(
      "tidyr_pivot" = "tidyr::pivot_wider",
      "values_fill" = "values_fill",
      "backtick_cols" = "`[0-9]+`"
    ),
    "percentage-calc" = list(
      "round_pct" = "round\\(.*,\\s*[23]\\)",
      "division_guard" = "if_else.*==\\s*0|coalesce"
    )
  )

  skill_patterns <- patterns[[skill_name]]
  if (is.null(skill_patterns)) return(NULL)

  results <- sapply(skill_patterns, function(pattern) {
    grepl(pattern, code, perl = TRUE)
  })

  list(
    skill = skill_name,
    patterns_checked = names(skill_patterns),
    patterns_found = names(skill_patterns)[results],
    usage_score = sum(results) / length(results)
  )
}
```

### Enhanced YAML Output

Add skill tracking to run YAML:

```yaml
# Skill tracking (added for skills experiment)
skills:
  injected:
    - time-series-lag
    - percentage-calc
  detected_usage:
    time-series-lag:
      group_before_lag: true
      arrange_before_lag: true
      ungroup_after: false      # <-- Missed this!
      na_handling: true
      case_when_growth: true
      usage_score: 0.8
```

### Metrics to Compare

| Metric | E1 (no skills) | E2 (with skills) |
|--------|----------------|------------------|
| has_result | ?/5 | ?/5 |
| correct | ?/5 | ?/5 |
| **skill_usage_score** | N/A | ?/1.0 |
| **patterns_followed** | N/A | ?/5 |
| avg_tool_calls | ? | ? |
| avg_duration | ? | ? |

### Compare E1 vs E2 Pattern Usage

Run pattern detection on BOTH trials to see if skills change behavior:

```yaml
# E1 (no skills) - run_003.yaml
skills:
  injected: []
  detected_usage:
    time-series-lag:
      group_before_lag: false    # Forgot to group!
      arrange_before_lag: false  # Wrong order
      ungroup_after: false
      na_handling: false         # NA error
      case_when_growth: true
      usage_score: 0.2           # Low - made mistakes

# E2 (with skills) - run_003.yaml
skills:
  injected: [time-series-lag, percentage-calc]
  detected_usage:
    time-series-lag:
      group_before_lag: true     # Followed skill!
      arrange_before_lag: true   # Followed skill!
      ungroup_after: true
      na_handling: true          # Followed skill!
      case_when_growth: true
      usage_score: 1.0           # High - followed all patterns
```

### Analysis Questions

1. **Does skill injection help?** Compare E1 vs E2 correctness
2. **Are skills actually followed?** Check usage_score in E2
3. **Does skill change behavior?** Compare usage_score E1 vs E2
4. **Which patterns matter most?** Correlate pattern usage with correctness
5. **Failure modes**: When E2 fails, which patterns were missed?

### Expected Outcome

| Metric | E1 (no skills) | E2 (with skills) |
|--------|----------------|------------------|
| correct | ~2/5 (40%) | ~4/5 (80%) |
| usage_score | ~0.3 | ~0.8 |
| common_errors | group/arrange order, NA | fewer errors |

**Hypothesis confirmed if**:
- E2 correct rate > E1 correct rate
- E2 usage_score > E1 usage_score
- Higher usage_score correlates with correctness

---

## Evaluation Criteria

A run is **correct** if:
1. All 8 rows present
2. Columns: region, date, revenue, prev_revenue, revenue_change, growth
3. prev_revenue is NA (or 0) for first row per region, correct value for others
4. revenue_change calculated correctly, rounded to 3 decimals
5. growth labels correct ("up"/"down"/"flat")
6. Sorted by region, then date
