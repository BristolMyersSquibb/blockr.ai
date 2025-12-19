# LLM Evaluation Harness: Concept

## Goal

Test and compare LLM tool call chains across different configurations:
- **Prompts**: How does phrasing affect results?
- **Models**: gpt-o4-mini vs claude-opus vs gemini-2.5
- **Implementations**: blockr.ai (Shiny) vs pure ellmer (direct)
- **System prompts**: Different tool descriptions, instructions

## The Core Loop

blockr.ai's LLM integration follows an iterative refinement loop:

```
┌─────────────────────────────────────────────────────────────┐
│  1. LLM receives prompt + data description                  │
│  2. LLM writes R code intended to produce a data.frame      │
│  3. eval_tool executes the code                             │
│  4. LLM inspects: Did it run? Does result match the task?   │
│  5. If NOT satisfied → revise code, go to step 3            │
│  6. If satisfied → stop, return final code                  │
└─────────────────────────────────────────────────────────────┘
```

**Key insight**: The LLM is not just generating code - it's iterating until
the output fulfills the user's request. This requires:
- Code that evaluates without error
- A result that is a data.frame (usually)
- Content that matches what was asked for

**Current limitation**: Max 5 iterations may not be enough for complex tasks.

## Tools Available

| Tool | Purpose |
|------|---------|
| `eval_tool` | Execute R code, return result or error |
| `data_tool` | Inspect available datasets (names, columns, head) |
| (future) | Could add: schema_tool, sample_tool, help_tool, etc. |

The LLM can use tools creatively - e.g., call data_tool to understand
column types before writing code, or call eval_tool multiple times
to debug incrementally.

## Core Vocabulary

| Term | Definition |
|------|------------|
| **Run** | A single execution of a prompt through an LLM with tools |
| **Trial** | Multiple runs of the same test case (manual, for now) |
| **Configuration** | Combination of model + system prompt + tool setup |
| **Harness** | The testing infrastructure that executes runs |
| **Driver** | Implementation variant (ellmer direct vs blockr.ai) |

## What We Measure

### Trajectory Metrics (the "how")
- `duration_secs` - wall clock time
- `n_tool_calls` - total tool invocations
- `n_tool_calls_by_type` - breakdown by tool (eval_tool: 3, data_tool: 1)
- `n_turns` - conversation turns

### Outcome Metrics (the "what")
- `has_code` - was code generated?
- `code_evaluates` - does the code run without error?
- `result_is_dataframe` - is output a data.frame?
- `result_nrow` - rows in result
- `result_ncol` - columns in result

### Quality Metrics (future)
- `llm_judge_score` - another LLM rates the result
- `assertion_pass` - custom assertions (e.g., "ARM column exists")

## Architecture

```
run_llm_ellmer(prompt, data, config)
       │
       ▼
┌─────────────────────────────────────┐
│  1. Setup client + tools            │
│  2. Call LLM (synchronous)          │
│  3. Extract code from eval_tool     │
│  4. Evaluate code against data      │
│  5. Return structured result        │
└─────────────────────────────────────┘
       │
       ▼
summarize_run(result)
       │
       ▼
┌─────────────────────────────────────┐
│  - Duration                         │
│  - Has code? Evaluates?             │
│  - Result dimensions                │
│  - Tool call counts                 │
└─────────────────────────────────────┘
```

## Driver Comparison

| Aspect | ellmer direct | blockr.ai |
|--------|---------------|-----------|
| Execution | Synchronous | Async (Shiny) |
| Setup | Manual tool wiring | Block infrastructure |
| Use case | Isolate LLM behavior | Test full integration |
| Overhead | Minimal | Shiny + reactivity |

The harness allows running the **same prompt + data** through both drivers
to identify whether issues come from the LLM or the Shiny integration.

## Test Prompts: Complexity Matters

Simple prompts like "filter iris for setosa" are **too easy** - the LLM gets
them right without needing the iterative loop. Good test prompts should:

- Require multiple steps or transformations
- Have specific output format requirements
- Benefit from inspecting intermediate results
- Be realistic tasks users would actually request

### Good Test Prompts

**1. Demographics Table (ADSL)**
```
Create a demographics summary table by treatment arm (ARM).
Summarize: AGE (median, Q1-Q3), SEX (n, %), RACE (n, %).
Output: data.frame with 'Characteristic' column + one column per ARM.
```
Why good: Requires aggregation, reshaping, specific formatting.

**2. Pivot + Aggregate (mtcars)**
```
Create a table showing mean mpg by number of cylinders (cyl) and
transmission type (am). Rows = cyl, Columns = am values.
Add a 'Total' row with overall means.
```
Why good: Pivot operation, row binding, multiple aggregations.

**3. Time-based Filtering + Summary**
```
From this dataset, find all records from the last 30 days.
Group by category and show: count, mean value, min, max.
Sort by count descending.
```
Why good: Date manipulation, multi-column summary, sorting.

**4. Data Quality Check**
```
Create a data quality report showing:
- Number of missing values per column
- Percentage missing
- Number of unique values
Only include columns with >0 missing values.
```
Why good: Meta-analysis of data, conditional filtering of results.

**5. Top-N per Group**
```
For each Species in iris, find the 2 observations with highest Sepal.Length.
Return all columns plus a rank column.
```
Why good: Window functions or split-apply-combine pattern.

## Non-Goals (for now)

- Automated multi-run statistics (manual trials first)
- LLM-as-judge evaluation
- CI integration
- Cost/token tracking
