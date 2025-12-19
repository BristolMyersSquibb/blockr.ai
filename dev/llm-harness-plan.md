# LLM Evaluation Harness: Implementation Plan

## Phase 1: Minimal Ellmer Driver

**Files to create:**
- `dev/harness.R` - core functions
- `dev/trial-simple.R` - test script with simple prompt
- `dev/trial-demographics.R` - test script with complex prompt

**Functions:**

```r
run_llm_ellmer(prompt, data, config)
```
- Takes prompt string, data frame, config list
- Verbose output during execution
- Returns list with: code, result, turns, duration_secs, error

```r
summarize_run(run)
```
- Pretty-prints key metrics
- Shows generated code
- Returns run invisibly

**Config structure:**
```r
config <- list(
  chat_fn = function() ellmer::chat_openai(model = "o4-mini")
)
```

**Dependencies from blockr.ai:**
- `new_eval_tool()`, `new_data_tool()`
- `system_prompt()`
- `get_tool()`
- Need to understand proxy setup

## Phase 2: Blockr Driver

**Add function:**
```r
run_llm_blockr(prompt, data, config)
```
- Same signature as ellmer driver
- Uses testServer internally
- Same return structure

**Enables comparison:**
```r
res_ellmer <- run_llm_ellmer(prompt, data, config)
res_blockr <- run_llm_blockr(prompt, data, config)
# Compare: is difference in LLM or in Shiny integration?
```

## Phase 3: Enhanced Summary

**Extend `summarize_run()`:**
- Count tool calls by type
- Show conversation flow (tool call sequence)
- Optionally show full turns

**Add:**
```r
compare_runs(run1, run2, ...)
```
- Side-by-side comparison table
- Highlight differences

## Phase 4: Test Cases Library

**Create reusable test cases:**
```r
# dev/test-cases.R
tc_filter_setosa <- list(
  name = "filter_setosa",
  prompt = "Filter the data to only include setosa species",
  data = iris
)

tc_demographics <- list(
  name = "demographics",
  prompt = "Create a demographics summary table...",
  data = ADSL
)
```

## Implementation Order

1. [ ] Create `dev/harness.R` with `run_llm_ellmer()` skeleton
2. [ ] Implement tool setup (extract from test-ellmer-direct.R on llm-tweaks)
3. [ ] Implement LLM call + code extraction
4. [ ] Add `summarize_run()`
5. [ ] Create `dev/trial-simple.R` - test with iris/setosa
6. [ ] Verify it works end-to-end
7. [ ] Create `dev/trial-demographics.R` - test with ADSL
8. [ ] Add `run_llm_blockr()` (Phase 2)

## Open Questions

- Where does `new_proxy()` come from? Need to extract/simplify from block code?
- How to extract code from eval_tool after run?
- What helper functions from blockr.ai can we reuse vs. need to duplicate?
- Is max 5 iterations enough? Probably not for complex prompts.

## Test Prompt Selection

Avoid trivial prompts like "filter iris for setosa" - the LLM gets these
right without iteration. Use prompts that:
- Require the LLM to inspect results and iterate
- Have specific output format requirements
- Exercise the full eval-inspect-revise loop

See `llm-harness-concept.md` for candidate prompts.

## Success Criteria for Phase 1

A successful run should show:
1. Multiple eval_tool calls (LLM iterating)
2. Final code that evaluates without error
3. Result that is a data.frame with reasonable content
4. Verbose output showing the conversation flow
