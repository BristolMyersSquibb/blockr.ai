# LLM Evaluation Harness

A modular framework for testing LLM tool-calling with R code generation.

## Quick Start

```r
source("dev/harness.R")

# 1. Define your test (using mtcars - a standard R dataset)
prompt <- "
Calculate the total horsepower (hp) by number of cylinders (cyl).
Add a column pct_of_total showing each group's percentage of total hp.
The percentages must sum to 1.0. Round to 2 decimals.
Sort by total_hp descending.
Output columns: cyl, total_hp, pct_of_total
"

# 2. Run experiment (3 runs with baseline function)
run_experiment(
  run_fn = run_llm_ellmer,
  prompt = prompt,
  data = mtcars,
  output_dir = "dev/results/mtcars-hp/trial_baseline_gpt4omini",
  model = "gpt-4o-mini",
  times = 3
)

# 3. Run another trial with validation
run_experiment(
  run_fn = run_llm_ellmer_with_validation,
  prompt = prompt,
  data = mtcars,
  output_dir = "dev/results/mtcars-hp/trial_validation_gpt4omini",
  model = "gpt-4o-mini",
  times = 3
)

# 4. Compare trials
compare_trials("dev/results/mtcars-hp")
```

### Expected Output

```
#>   cyl total_hp pct_of_total
#> 1   8     2929         0.62
#> 2   6      856         0.18
#> 3   4      909         0.19
```

## Core Functions

### `run_experiment()`

Run an experiment and save results as YAML files.

```r
run_experiment(
  run_fn,      # The run function (see below)
  prompt,      # The prompt to send to the LLM
  data,        # The data to use (data.frame or named list)
  output_dir,  # Directory for YAML files (e.g., "dev/results/exp/trial_A")
  model = "gpt-4o-mini",
  times = 1    # Number of runs
)
```

**Returns**: Paths to saved YAML files (invisibly)

### Run Functions

| Function | Description |
|----------|-------------|
| `run_llm_ellmer` | Baseline: LLM uses tools, no special feedback |
| `run_llm_ellmer_with_preview` | LLM sees result preview from data_tool |
| `run_llm_ellmer_with_validation` | Retry loop if no valid data.frame |

You can also create custom run functions following the same signature:
```r
my_run_fn <- function(prompt, data, config, ...) {
  # ... your implementation ...
  list(
    code = "...",
    result = data.frame(...),
    turns = client$get_turns(),
    duration_secs = 10,
    error = NULL,
    config = config,
    prompt = prompt
  )
}
```

### `judge_runs()`

List runs in a trial directory (evaluation done by Claude).

```r
judge_runs("dev/results/my-experiment/trial_baseline_gpt4omini")
```

To evaluate, use the `/judge-runs` skill in Claude Code.

### `compare_trials()`

Compare results across trials in an experiment.

```r
compare_trials("dev/results/my-experiment")
#>                              trial n_runs has_result correct avg_duration avg_tool_calls
#> trial_baseline_gpt4omini         3    2/3     0/3        13.0           1.0
#> trial_validation_gpt4o           3    3/3     3/3        15.2           1.3
```

## Folder Structure

```
dev/results/
└── my-experiment/                    # Experiment
    ├── trial_baseline_gpt4omini/     # Trial A
    │   ├── run_001.yaml
    │   ├── run_002.yaml
    │   └── run_003.yaml
    ├── trial_validation_gpt4omini/   # Trial B
    │   ├── run_001.yaml
    │   └── run_002.yaml
    └── trial_validation_gpt4o/       # Trial C (added later)
        ├── run_001.yaml
        ├── run_002.yaml
        └── run_003.yaml
```

## YAML File Format

Each run produces one YAML file with complete details:

```yaml
meta:
  timestamp: "2025-12-19 18:30:00"
  run_number: 1
  run_fn: "run_llm_ellmer_with_validation"
  model: "gpt-4o-mini"

metrics:
  has_result: true
  duration_secs: 15.8
  tool_calls: 3

prompt: |
  Calculate percentage of sales by region...

steps:
  - step: 1
    tool: eval_tool
    code: |
      data |> dplyr::group_by(region) |> ...
    status: success
    response: |
      Code executed successfully...

final_code: |
  data |> dplyr::group_by(region) |> ...

result: |
  # A tibble: 5 x 3
  region  total_revenue  pct_of_total
  ...

error: null

# Added by Claude via /judge-runs
evaluation:
  correct: true
  reason: "All requirements met."
```

## Workflow

1. **Run experiments**: Use `run_experiment()` to create trials
2. **Evaluate**: Use `/judge-runs <trial_dir>` to have Claude evaluate
3. **Compare**: Use `compare_trials()` to see summary

## Adding New Trials

Just call `run_experiment()` with a new `output_dir`:

```r
# Add a new trial anytime
run_experiment(
  run_fn = my_new_run_fn,
  prompt = prompt,
  data = data,
  output_dir = "dev/results/my-experiment/trial_new_approach",
  times = 5
)

# Compare all trials
compare_trials("dev/results/my-experiment")
```

## Claude Skills

- `/judge-runs <trial_dir>` - Evaluate all runs in a trial directory

## Related Files

- `dev/harness.R` - Core functions
- `dev/HARNESS-WORKFLOW.md` - Detailed workflow documentation
- `dev/TUNING-VARIABLES.md` - Tuning variables and experiment ideas
- `dev/PRESENTATION-DRAFT.md` - Presentation slides
