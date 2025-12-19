# LLM Harness Workflow

## Overview

The harness tests LLM tool call chains by running trials and saving results
for evaluation. Claude evaluates the results and writes judgment back to the
meta.yaml file.

## Running a Trial

```bash
Rscript dev/trial-multi-run.R
```

This saves results to `dev/results/trial_<name>_<model>_<timestamp>/`:
- `prompt.txt` - the original prompt
- `run_01_a.yaml`, `run_01_b.yaml` - full run details (prompt, steps, code, result)
- `meta.yaml` - timing, tool calls, and Claude's evaluation (added later)

## YAML Run Files (the key debugging resource)

Each `run_XX_Y.yaml` file contains the full story:

```yaml
meta:
  model: "gpt-4o-mini"
  variant: "b"
  run_number: 1

metrics:
  has_result: false
  duration_secs: 7
  tool_calls: 1

prompt: |
  Calculate mean of Sepal.Length by Species...

# Each step shows exactly what happened
steps:
  - step: 1
    tool: data_tool          # <-- Used wrong tool!
    code: |
      data |> dplyr::group_by(Species) |> ...
    status: success
    response: |
      # A tibble: 3 x 2
      Species    mean_sepal
      ...

final_code: |
  # no code captured        # <-- Never called eval_tool

result: |
  NULL

error: null
```

This makes it easy to see:
- Which tools were called and in what order
- The exact code submitted at each step
- The response from each tool
- Why a run failed (e.g., used data_tool instead of eval_tool)

## Evaluating Results

Ask Claude:

> "Evaluate results in dev/results/trial_pct-sales_gpt-4o-mini_20251219_173816"

### What Claude Does

1. **Read the prompt** (`prompt.txt`) to understand requirements
2. **Read each CSV** to see actual results
3. **Evaluate each run** against prompt requirements:
   - Does the output have the required columns?
   - Do numeric constraints hold? (e.g., "pct_of_total must sum to 1.0")
   - Is data sorted correctly?
   - Are edge cases handled? (e.g., NA -> Unknown)
4. **Update meta.yaml** with evaluation section:

```yaml
evaluation:
  run_01_a:
    correct: true
    pct_sum: 1.01
    reason: "All requirements met."
  run_01_b:
    correct: false
    pct_sum: 5.00
    reason: "BUG: pct_of_total computed per-group, not overall."

summary:
  variant_a: "3/3 correct"
  variant_b: "1/3 correct"
  notes: |
    Brief analysis of what went wrong and patterns observed.
```

## Key Files

- `dev/harness.R` - Core functions for running LLM trials
  - `run_llm_ellmer()` - Run LLM with tools (no preview)
  - `run_llm_ellmer_with_preview()` - Run LLM with result preview
  - `save_experiment()` - Save results to folder
  - `list_experiments()` - List saved experiments

- `dev/trial-multi-run.R` - Example trial script

## Why This Approach Works

- **No hardcoded scoring**: The harness just saves results, Claude evaluates
- **Semantic evaluation**: Claude understands natural language requirements
- **Explainable**: Reasons are recorded in yaml for later review
- **Flexible**: Works with any prompt, any validation criteria
