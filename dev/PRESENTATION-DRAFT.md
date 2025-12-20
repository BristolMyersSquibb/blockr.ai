# Tuning LLM Tool-Calling for R Code Generation
## A Systematic Approach to Optimizing blockr.ai

---

# Slide 1: The Problem

**Goal**: Have an LLM generate correct R code from natural language

**Challenge**: Many moving parts to tune:
- Which model?
- What instructions?
- How to give feedback?
- When to retry?

**Question**: How do we systematically find the best configuration?

---

# Slide 2: Terminology - What is a "Harness"?

## Test Harness (noun)
> A framework that runs code under controlled conditions and measures results

**In our context**:
- Sends prompts to the LLM
- Captures tool calls and responses
- Records timing, errors, results
- Saves everything for later analysis

**Analogy**: Like a lab bench for experiments
- Same setup each time
- Controlled variables
- Measurable outcomes

---

# Slide 3: Terminology - Key Concepts

| Term | Meaning |
|------|---------|
| **Tool calling** | LLM invokes external functions (like `eval_tool(code="...")`) |
| **Variant** | A specific configuration to test (A, B, C) |
| **Run** | One execution of a prompt with a variant |
| **Trial** | Multiple runs across variants |
| **Pass@k** | Success rate: does at least 1 of k attempts work? |

---

# Slide 4: How Does the Literature Do This?

## Major Benchmarks

| Benchmark | Focus | Scale |
|-----------|-------|-------|
| [HumanEval](https://deepgram.com/learn/humaneval-llm-benchmark) | Code generation | 164 tasks |
| [BigCodeBench](https://huggingface.co/blog/leaderboard-bigcodebench) | Practical programming | 1,140 tasks |
| [BFCL](https://gorilla.cs.berkeley.edu/leaderboard.html) | Function/tool calling | 1000s of functions |
| [AgentBench](https://github.com/THUDM/AgentBench) | LLM-as-agent | 8 environments |

## Standard Methodology
1. Fixed test set (100s-1000s of tasks)
2. Run each model N times per task
3. Measure **Pass@1** (first try) or **Pass@k** (best of k)
4. Report accuracy, cost, latency

---

# Slide 5: How We Compare to Literature

| Aspect | Literature | Our Approach |
|--------|------------|--------------|
| **Scale** | 100s-1000s tasks | Few tasks, deep analysis |
| **Metric** | Pass@k (binary) | Semantic correctness |
| **Evaluation** | Unit tests | Claude-as-judge |
| **Focus** | Model comparison | Configuration tuning |
| **Transparency** | Scores only | Full conversation logs |

## Our Advantage
- **Task-specific**: We tune for *our* use case (R data transformation)
- **Explainable**: We see *why* it failed, not just *that* it failed
- **Iterative**: Quick feedback loop to improve prompts/tools

---

# Slide 6: The System Architecture

```
┌──────────────────────────────────────────────────────┐
│                    USER PROMPT                       │
│        "Calculate pct of sales by region"            │
└──────────────────────────────────────────────────────┘
                         │
                         ▼
┌──────────────────────────────────────────────────────┐
│        SYSTEM PROMPT + SKILLS  [Tunable]             │
│   Instructions, data schema, patterns, constraints   │
└──────────────────────────────────────────────────────┘
                         │
                         ▼
┌──────────────────────────────────────────────────────┐
│                 MODEL  [Tunable]                     │
│        gpt-4o-mini / gpt-4o / claude-3.5            │
│              temperature, max_tokens                 │
└──────────────────────────────────────────────────────┘
                         │
                         ▼
┌──────────────────────────────────────────────────────┐
│                 TOOLS  [Tunable]                     │
│    eval_tool (validate)    data_tool (preview)       │
│         names, descriptions, return format           │
└──────────────────────────────────────────────────────┘
                         │
                         ▼
┌──────────────────────────────────────────────────────┐
│             FEEDBACK LOOP  [Tunable]                 │
│      Preview? Validation? Retries? Error format?     │
└──────────────────────────────────────────────────────┘
                         │
                         ▼
┌──────────────────────────────────────────────────────┐
│                     RESULT                           │
│              R data.frame or error                   │
└──────────────────────────────────────────────────────┘
```

---

# Slide 7: Tuning Variable 1 - Model Selection

| Variable | Options | Impact |
|----------|---------|--------|
| Model | gpt-4o-mini, gpt-4o, claude-3.5-sonnet | Accuracy vs cost |
| Temperature | 0.0 - 1.0 | Consistency vs creativity |

## Trade-off
- **gpt-4o-mini**: $0.15/1M tokens, more reasoning errors
- **gpt-4o**: $2.50/1M tokens, better reasoning
- ~17x cost difference

## Experiment
> Same task, 3 models, n=10 runs each. Measure accuracy & cost.

---

# Slide 8: Tuning Variable 2 - Tool Design

| Variable | Options |
|----------|---------|
| Tool count | 1 (eval only) vs 2 (eval + data) |
| Tool names | `eval_tool` vs `submit_code` |
| Return format | Truncated vs full |

## Key Question
> Does `data_tool` help the LLM iterate, or distract from validation?

## Experiment
> Compare 1-tool vs 2-tool setup. Measure validation rate.

---

# Slide 9: Tuning Variable 3 - Feedback Loop

## Four Variants Tested

| Variant | Description | Behavior |
|---------|-------------|----------|
| **A** | Baseline | LLM calls tools, no special feedback |
| **B** | Preview | LLM sees result preview from data_tool |
| **C** | Validation | Retry loop if no valid data.frame |
| **D** | Preview + Validation | Both B and C combined |

## Results: mtcars-complex (n=5, gpt-4o-mini)

| Metric | A (baseline) | B (preview) | C (validation) | D (both) |
|--------|--------------|-------------|----------------|----------|
| Has result | 3/5 | 3/5 | **5/5** | **5/5** |
| Correct | 2/5 (40%) | 2/5 (40%) | **5/5 (100%)** | **5/5 (100%)** |
| Avg time | 24.5s | 23.0s | 32.2s | 39.0s |
| Tool calls | 3.0 | 2.6 | 3.2 | 3.0 |

## Key Finding
**Validation (C, D) achieves 100% correctness** vs 40% for baseline.
The cost is ~50% more time, but guarantees correct results.

---

# Slide 10: Tuning Variable 4 - Skills

## What are Skills?
Markdown files that teach specific coding patterns to avoid LLM traps.

## The Problem: LLM Traps
Common errors that LLMs make consistently:
- `dplyr::select(., ...)` inside mutate with native pipe → fails
- `dplyr::rowSums()` → doesn't exist
- `across()` without `dplyr::` prefix → fails

## Three Approaches Tested

| Approach | Prompt Size | How Skills Work |
|----------|-------------|-----------------|
| **R1** No skills | Baseline | LLM has no guidance |
| **R2** All skills in prompt | ~10,000 tokens | Full content always loaded |
| **R3** Progressive disclosure | ~200 tokens | LLM calls `skill_tool` on demand |

## Experiment: rowsum-test (gpt-4o-mini)

| Metric | R1 (no skills) | R2 (in prompt) | R3 (skill_tool) |
|--------|----------------|----------------|-----------------|
| Success rate | 90% | 100% | **100%** |
| Avg time | 26.7s | 20.8s | **11.7s (2.3x faster)** |
| Tool calls | 5.1 | 2.0 | 3.0 |
| Prompt tokens | baseline | +10,000 | **+200** |

## Key Finding
**Progressive disclosure (R3)** achieves best results:
- 2.3x faster than baseline
- Uses only 2% of the tokens vs naive approach
- LLM correctly calls relevant skills (pivot-table, rowwise-sum)
- LLM ignores irrelevant skills (time-series-lag, percentage-calc)

---

# Slide 11: Key Insights from Experiments

## Two Complementary Strategies

| Strategy | Purpose | Effect |
|----------|---------|--------|
| **Validation Loop** | Ensure valid output | 100% success rate |
| **Progressive Skills** | Teach correct patterns on demand | 2.3x faster, minimal tokens |

## Why Progressive Disclosure Works
Like Claude Code's skill system:
1. LLM sees only skill **metadata** upfront (~200 tokens)
2. LLM has a `skill_tool` to request full content when needed
3. LLM decides which skills are relevant for the task

**Result**: Token-efficient and scalable to many skills.

## Why Skills Break Error Loops
LLMs get stuck trying the same broken pattern:
```
Attempt 1: rowSums(dplyr::select(., -store)) → Error: '.' not found
Attempt 2: rowSums(dplyr::select(., -store)) → Error: '.' not found
...
```
Skills teach the correct pattern (`dplyr::across()`) before the LLM writes code.

## Why Validation Works
Without validation, LLM may stop after `data_tool` (preview only).
With validation, LLM must call `eval_tool` and get confirmed success.

---

# Slide 12: How We Evaluate (Claude-as-Judge)

## Traditional Approach
- Unit tests: `assert sum(pct) == 1.0`
- Binary pass/fail
- Must anticipate all edge cases

## Our Approach
- Claude reads the prompt requirements
- Claude reads the actual output
- Claude judges: correct or not, with reasoning

## Example Evaluation
```yaml
run_02_a:
  correct: false
  pct_sum: 5.0
  reason: "BUG: pct_of_total all show 1.0.
           Computed inside summarize() while grouped."
```

---

# Slide 13: Full Logging for Debugging

Every run saves complete conversation:

```yaml
steps:
  - step: 1
    tool: data_tool
    code: |
      data |> dplyr::group_by(region) |> ...
    status: success
    response: |
      # A tibble: 5 x 3
      region  total_revenue  pct_of_total
      South   10786          1.0          # <- Bug visible!
      ...
```

**Benefit**: See exactly *why* something failed, not just *that* it failed.

---

# Slide 14: Comparison with Standard Benchmarks

## Berkeley Function Calling Leaderboard (BFCL)

| Aspect | BFCL | Our Harness |
|--------|------|-------------|
| Purpose | Rank models | Tune configuration |
| Scale | 1000s of functions | Few representative tasks |
| Evaluation | AST matching | Semantic correctness |
| Output | Leaderboard score | Detailed YAML logs |
| Reusability | Fixed benchmark | Task-specific |

## When to Use What
- **BFCL**: "Which model is best at function calling?"
- **Our harness**: "What configuration works best for *our* task?"

---

# Slide 15: Experiments Completed & Future Work

## Completed ✅

| Experiment | Trials | Finding |
|------------|--------|---------|
| **mtcars-complex** | A, B, C, D | Validation achieves 100% correctness |
| **rowsum-test** | R1, R2, R3 | Progressive disclosure 2.3x faster |

## Key Comparisons

| Intervention | Baseline | Optimized | Improvement |
|--------------|----------|-----------|-------------|
| Validation loop | 40% correct | 100% correct | +60% |
| Progressive skills | 26.7s | 11.7s | 2.3x faster |
| Token efficiency | 10,000 tokens | 200 tokens | 50x smaller |

## Future Work

| Priority | Experiment | Question |
|----------|------------|----------|
| 1 | Model comparison | Does gpt-4o need fewer skills/retries? |
| 2 | Skills + Validation | Do they combine synergistically? |
| 3 | Larger n | n=20-30 for statistical confidence |
| 4 | Different tasks | Generalize beyond R/dplyr |

---

# Slide 16: Summary

## What We Built
- **Test harness** for LLM tool-calling experiments
- **Validation loop** ensuring correct output
- **Progressive skills** (Claude Code-style) for on-demand pattern teaching
- **Claude-as-judge** for semantic evaluation
- **Full logging** for debugging

## Key Findings

| Intervention | Effect |
|--------------|--------|
| **Validation loop** | 40% → 100% correctness |
| **Progressive skills** | 2.3x faster, 50x fewer tokens |

## Recommendations
1. **Always use validation** - guarantees valid output
2. **Use progressive disclosure for skills** - scalable, token-efficient
3. **Add skills for known LLM traps** - prevents error loops
4. **Log everything** - enables debugging and iteration

---

# Appendix: Glossary

| Term | Definition |
|------|------------|
| **Harness** | Framework that runs tests under controlled conditions |
| **Tool calling** | LLM invoking external functions via structured output |
| **Skill** | Markdown file teaching a specific code pattern |
| **Progressive disclosure** | Pattern where LLM sees only skill metadata upfront, requests full content on demand |
| **skill_tool** | Tool that LLM calls to retrieve full skill content when needed |
| **Validation loop** | Retry mechanism that ensures LLM produces valid output |
| **Pass@k** | Probability that at least 1 of k attempts succeeds |
| **AST** | Abstract Syntax Tree - used by BFCL to match function calls |
| **Few-shot** | Including examples in the prompt |
| **Claude-as-judge** | Using an LLM to evaluate output quality |
| **Variant** | A specific configuration being tested |

---

# Appendix: Sources

## Benchmarks & Leaderboards
- [Berkeley Function Calling Leaderboard (BFCL)](https://gorilla.cs.berkeley.edu/leaderboard.html)
- [BigCodeBench](https://huggingface.co/blog/leaderboard-bigcodebench)
- [HumanEval](https://deepgram.com/learn/humaneval-llm-benchmark)
- [AgentBench](https://github.com/THUDM/AgentBench)
- [Scale AI ToolComp](https://scale.com/leaderboard/tool_use_enterprise)

## Evaluation Frameworks
- [EleutherAI lm-evaluation-harness](https://github.com/EleutherAI/lm-evaluation-harness)
- [Copilot Evaluation Harness](https://arxiv.org/html/2402.14261v1)

## Surveys & Guides
- [Survey on Evaluation of LLM-based Agents](https://arxiv.org/html/2503.16416v1)
- [LLM Agent Evaluation Guide](https://www.confident-ai.com/blog/llm-agent-evaluation-complete-guide)
- [30 LLM Evaluation Benchmarks](https://www.evidentlyai.com/llm-guide/llm-benchmarks)
- [Rethinking LLM Benchmarks for 2025](https://www.fluid.ai/blog/rethinking-llm-benchmarks-for-2025)

## Research Papers
- [ToolACE: Winning the Points of LLM Function Calling](https://arxiv.org/html/2409.00920v1)
- [ARTIST: Agentic Reasoning and Tool Integration](https://arxiv.org/html/2505.01441v1)
- [Benchmarks and Metrics for Code Generation: A Critical Review](https://arxiv.org/html/2406.12655v1)
