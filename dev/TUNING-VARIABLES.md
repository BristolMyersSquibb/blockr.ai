# LLM Tool-Calling: Tuning Variables & Experiments

This document outlines the key tuning variables in the blockr.ai LLM system
and proposes experiments to understand their impact.

## System Overview

```
┌─────────────────────────────────────────────────────────────────┐
│                        USER PROMPT                              │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                      SYSTEM PROMPT                              │
│  ┌───────────────┐  ┌───────────────┐  ┌───────────────┐       │
│  │ Instructions  │  │ Data Schema   │  │ Examples      │       │
│  └───────────────┘  └───────────────┘  └───────────────┘       │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                         MODEL                                   │
│         (gpt-4o-mini, gpt-4o, claude-3.5-sonnet, ...)          │
│                    temperature, max_tokens                      │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                         TOOLS                                   │
│  ┌───────────────┐  ┌───────────────┐                          │
│  │   eval_tool   │  │   data_tool   │  ◄── Tool design         │
│  │  (validate)   │  │  (preview)    │                          │
│  └───────────────┘  └───────────────┘                          │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                    FEEDBACK LOOP                                │
│         Preview? Validation? Retries? Error format?             │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                    EVAL ENVIRONMENT                             │
│              Allowed packages, base functions                   │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                        RESULT                                   │
└─────────────────────────────────────────────────────────────────┘
```

---

## 1. Model Selection

### Variables

| Variable | Current | Options |
|----------|---------|---------|
| Model | gpt-4o-mini | gpt-4o-mini, gpt-4o, claude-3.5-sonnet, claude-3-haiku |
| Temperature | 1.0 (default) | 0.0 - 2.0 |
| Max tokens | default | 1024, 2048, 4096 |

### Trade-offs

- **Smarter models**: Better reasoning, fewer bugs, but higher cost & latency
- **Lower temperature**: More deterministic, but possibly less creative solutions
- **Token limits**: Affects verbosity of explanations (not usually the bottleneck)

### Proposed Experiment: Model Comparison

```
Task: pct-sales (current benchmark)
Variants: A, B, C (all three)
Models: gpt-4o-mini, gpt-4o, claude-3.5-sonnet
Runs: n=10 per model per variant (90 total runs)

Measure:
- Accuracy (correct result)
- Cost ($ per run)
- Latency (seconds)
- Tool calls (efficiency)
```

---

## 2. Tool Design

### Variables

| Variable | Current | Options |
|----------|---------|---------|
| Tool count | 2 (eval + data) | 1 (eval only), 2, or more |
| Tool names | `eval_tool`, `data_tool` | `submit_code`, `validate_r_code`, `preview_data` |
| Tool descriptions | ~100 words each | Minimal (1 sentence) vs verbose (with examples) |
| Return truncation | 500 chars | 100, 500, 1000, full |

### Trade-offs

- **More tools**: Flexibility, but LLM may use wrong tool or get confused
- **Better names**: May guide LLM behavior (e.g., "submit" implies finality)
- **Verbose descriptions**: More guidance, but longer context
- **Return truncation**: More info helps, but costs tokens

### Proposed Experiment: Single Tool vs Two Tools

```
Task: pct-sales
Compare:
  - Single tool: eval_tool only (must validate to get result)
  - Two tools: eval_tool + data_tool (can preview first)

Hypothesis: data_tool may distract LLM from calling eval_tool
Counter-hypothesis: data_tool helps LLM iterate before committing

Runs: n=10 per condition
Measure: Accuracy, tool call patterns
```

### Proposed Experiment: Tool Naming

```
Task: pct-sales
Compare tool names:
  - eval_tool / data_tool (current)
  - submit_code / preview_code (action-oriented)
  - validate_and_save / explore_data (descriptive)

Hypothesis: "submit" implies finality, may increase validation rate
Runs: n=10 per condition
```

---

## 3. System Prompt

### Variables

| Variable | Current | Options |
|----------|---------|---------|
| Length | ~2300 chars | Minimal (~500), Standard (~2000), Comprehensive (~4000) |
| Data description | Column names + types | Names only, +head(), +summary stats |
| Examples | 0 | 0, 1, 3 few-shot examples |
| Constraint style | Mixed | Soft ("prefer") vs Hard ("MUST") |
| Package guidance | "Use dplyr::" | None, namespace required, specific functions listed |

### Trade-offs

- **Longer prompts**: More guidance, but more tokens, possible confusion
- **More data context**: Helps LLM understand data, but may overwhelm
- **Few-shot examples**: Powerful, but task-specific and expensive
- **Hard constraints**: Higher compliance, but may cause failures if impossible

### Proposed Experiment: Few-Shot Examples

```
Task: pct-sales
Compare:
  - 0 examples (current)
  - 1 example (simple group_by + summarize)
  - 3 examples (simple, medium, complex)

Hypothesis: Examples improve first-try success rate
Risk: Examples may cause overfitting to example style

Runs: n=10 per condition
Measure: First-try success, accuracy
```

### Proposed Experiment: Data Description Richness

```
Task: pct-sales
Compare:
  - Minimal: column names only
  - Standard: names + types (current)
  - Rich: names + types + head(3) + summary stats

Hypothesis: More context helps, but diminishing returns
Runs: n=10 per condition
```

---

## 4. Feedback Loop

### Variables

| Variable | Current | Options |
|----------|---------|---------|
| Preview mode | A/B/C variants | None, preview, validation, preview+validation |
| Max retries | 3 (variant C) | 1, 3, 5, 10 |
| Error verbosity | Full error message | Minimal, full, full + hint |
| Success message | "Code executed successfully" | Minimal, +result preview, +verification prompt |

### Trade-offs

- **More retries**: Higher eventual success, but more cost/latency
- **Error verbosity**: Helps debugging, but may overwhelm
- **Verification prompts**: May catch bugs, but adds latency

### Current Experiment Results (n=3)

| Variant | Has Result | Correct |
|---------|------------|---------|
| A (baseline) | 2/3 | 0/3 |
| B (preview) | 2/3 | 2/3 |
| C (validation) | 3/3 | 2/3 |

### Proposed Experiment: Retry Count

```
Task: deliberately difficult prompt (e.g., complex pivot)
Variant C only
Compare: max_retries = 1, 3, 5, 10

Hypothesis: Diminishing returns after 3 retries
Measure: Success rate at each retry count, total cost
```

### Proposed Experiment: Variant D (Preview + Validation)

```
Task: pct-sales
New variant D: Combine B (preview) + C (validation loop)
  - LLM can use data_tool to preview
  - But must validate with eval_tool
  - If no valid result, retry

Hypothesis: Best of both worlds - preview for iteration, validation for guarantee
```

---

## 5. Evaluation Environment

### Variables

| Variable | Current | Options |
|----------|---------|---------|
| Parent environment | baseenv() | baseenv(), globalenv(), custom |
| Allowed packages | dplyr (via namespace) | dplyr only, tidyverse, any |
| Base functions | Restricted | stats::, utils::, base:: |
| Timeout | None | 5s, 30s, 60s |

### Trade-offs

- **Restricted env**: Forces namespace prefixes, prevents ambiguity
- **More packages**: Flexibility, but LLM may use unfamiliar functions
- **Timeout**: Prevents infinite loops, but may kill legitimate long operations

### Proposed Experiment: Environment Restrictions

```
Task: pct-sales
Compare:
  - Strict: baseenv() parent, namespace required
  - Loose: globalenv() with tidyverse loaded

Hypothesis: Strict env causes more errors but more predictable code
Measure: Error rate, code style consistency
```

---

## Summary: Priority Experiments

| Priority | Experiment | Key Question |
|----------|------------|--------------|
| 1 | Model comparison | Does gpt-4o fix the correctness issues? |
| 2 | Variant D (B+C) | Can we get reliability AND correctness? |
| 3 | Few-shot examples | Do examples improve first-try success? |
| 4 | Single vs two tools | Does data_tool help or distract? |
| 5 | Retry count | Where are diminishing returns? |

---

## Metrics to Track

For all experiments, track:

1. **Accuracy**: Did the result meet all requirements?
2. **Has Result**: Did we get a valid data.frame?
3. **First-Try Success**: Did it work without retries?
4. **Tool Calls**: How many calls to reach result?
5. **Duration**: Total time (seconds)
6. **Cost**: Estimated token cost ($)
7. **Error Types**: Categorize failures (syntax, logic, wrong tool, etc.)

---

## Running Experiments

Use the existing harness:

```r
# In dev/trial-multi-run.R, modify:
N_RUNS <- 10  # Increase for statistical power
MODEL <- "gpt-4o"  # Test different models

# Run and evaluate:
Rscript dev/trial-multi-run.R
# Then ask Claude to evaluate results
```

See `dev/HARNESS-WORKFLOW.md` for full workflow documentation.
