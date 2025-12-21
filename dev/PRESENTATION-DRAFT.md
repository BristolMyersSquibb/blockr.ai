# blockr.ai: LLM-Powered Data Analysis
## Part 1: Tuning & Experiments | Part 2: Future Architecture

---

# Part 1: Tuning & Experiments

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

# Slide 4: Experiment - Feedback Loop Variants

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

# Slide 5: Deterministic Loop (No Tools)

## The Insight
Tool-based validation works, but adds overhead. What if we skip tools entirely?

## Deterministic Loop Flow
```
┌─────────────────────────────────────┐
│ 1. Show data preview (automatic)    │  ← Not a tool call
└─────────────────────────────────────┘
                 ↓
┌─────────────────────────────────────┐
│ 2. LLM writes code (plain text)     │  ← No tool schema
└─────────────────────────────────────┘
                 ↓
┌─────────────────────────────────────┐
│ 3. System runs code (automatic)     │  ← Guaranteed validation
└─────────────────────────────────────┘
                 ↓
        [Error] → show error, iterate
        [Success] → show result, LLM confirms "DONE"
```

## Experiment Results (mtcars-complex, gpt-4o-mini)

| Trial | Approach | Correct | Avg Time | Speedup |
|-------|----------|---------|----------|---------|
| A | Tool-based baseline | 40% | 24.5s | - |
| D | Tool-based + validation | 100% | 39.0s | 1x |
| **E** | **Deterministic loop** | **100%** | **9.1s** | **4.3x** |

## Why Deterministic is Faster
- No tool call overhead (no JSON parsing)
- No tool schemas in every message
- System controls flow directly
- Simpler message structure

---

# Slide 6: Why Deterministic Makes Sense

## Tools Are for Choices

Tools make sense when the LLM needs to **decide** what to do.
But in code generation, there's no real choice:

| Step | Is there a choice? |
|------|-------------------|
| See data first | No - always needed |
| Run code after writing | No - always validate |

## Tool-Based = False Choice

```
LLM "decides" to call data_tool    →  Should ALWAYS happen
LLM "decides" to call eval_tool    →  Should ALWAYS happen
```

Adds overhead and failure modes for no benefit.

## Better UX When Hitting Limits (Perhaps)

With deterministic flow, we control the conversation:

```
"I tried 5 times but couldn't get it right.
Here's what's failing: [specific error]

Options:
- Try 5 more iterations
- Help me: did you mean X or Y?
- Show what I have so far"
```

---

# Slide 7: Deterministic Loop - Model Compatibility

## Key Finding: Works with Models that Fail at Tool Calling

| Model | Tool-based Baseline | Deterministic |
|-------|---------------------|---------------|
| **GPT-4o-mini** | ~90% success | ~100% success |
| **Gemini** | **0% (ignores tools!)** | **100% success** |

**Why Gemini fails with tools**: Returns text without calling `eval_tool`.

**Why Deterministic works everywhere**: No tools required - just extracts code from markdown.

## Trade-offs Summary

| Aspect | Deterministic | Tool-based |
|--------|---------------|------------|
| Speed | ✓ 3-4x faster | Slower (tool overhead) |
| Reliability | ✓ 100% | ✓ 100% (with validation) |
| Model support | ✓ Works with all models | ✗ Requires good tool support |
| Exploration | ✗ Fixed preview only | ✓ Can query data |
| Best for | Well-defined transforms | Exploratory analysis |

---

# Slide 8: Skills (Progressive Disclosure)

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

# Slide 9: Evaluation (Claude-as-Judge)

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

# Slide 10: Full Logging

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

# Slide 11: Local & Open-Source Models

## The Promise
Can we run blockr.ai with local models for privacy/cost savings?

## Tested Models (Deterministic Approach)

| Model | Size | Success | Avg Speed | Notes |
|-------|------|---------|-----------|-------|
| **GPT-4o-mini** | ~8B (closed) | 100% | 9s | Reference |
| **gpt-oss:20b** | 20B | 100% | 65s | Works well |
| **gemma3:12b** | 12B | 100% | 50s | Needs all 5 iterations |
| gemma3:4b | 4B | 0% | — | Infinite loops |
| mistral:7b | 7B | 0% | — | Ignores instructions |

## Key Finding: Need 12B+ Parameters
- **Sub-10B models failed** (0% success on our task)
- 4B models: Infinite loops, incoherent code structure
- 7B models: Can't follow namespace rules (`dplyr::`, `|>` not `%>%`)
- **12B+**: Reliable success (100%)

## Why Deterministic Enables Local Models

| Approach | gpt-oss:20b | Gemini |
|----------|-------------|--------|
| Tool-based | **0% (broken)** | **0% (ignores tools)** |
| Deterministic | **100%** | **100%** |

Many open-source models don't implement tool calling correctly.
The deterministic approach removes this barrier entirely.

## Models to Evaluate (Future Work)

Code-specialized models *might* work at smaller sizes. Worth testing:

| Model | Size | Why Test |
|-------|------|----------|
| **Qwen2.5-Coder** | 7B, 14B, 32B | Best-in-class code model |
| **DeepSeek-Coder** | 6.7B, 33B | Matches CodeLlama-34B on benchmarks |
| **StarCoder2** | 15B | Specialized for code |

**Hypothesis**: Code-specialized 7B models may succeed where general-purpose 7B models fail.
Needs testing to confirm.

## Deployment Trade-offs

| Factor | API (GPT-4o-mini) | Local (gpt-oss:20b) |
|--------|-------------------|---------------------|
| **Speed** | 9s | 65s |
| **Cost** | Per-token pricing | Fixed infrastructure |
| **Privacy** | Data leaves your network | Data stays local |
| **Reliability** | Dependent on API | Dependent on hardware |

---

# Part 2: Future Architecture

---

# Slide 12: Universal AI Assistant Architecture

## The Shift: From Specialized Blocks to Universal Assistant

**Current**: AI embedded in specific block types (LLM Transform Block)
**Proposed**: Universal AI assistant that works with ANY block

## Two Entry Points, One Capability

```
┌─────────────────────────────────────────────────────────────┐
│                    AI Assistant                             │
│              (universal, context-aware)                     │
└─────────────────────────────────────────────────────────────┘
                    │
        ┌───────────┴───────────┐
        ▼                       ▼
┌───────────────┐       ┌───────────────┐
│   DAG View    │       │  Block View   │
│ "Filter and   │       │ "Keep only    │
│  summarize    │       │  setosa"      │
│  the data"    │       │      ↓        │
│      ↓        │       │ Fills this    │
│ Creates whole │       │ block         │
│ workflow      │       │               │
└───────────────┘       └───────────────┘
```

## What Each Level Does

| Level | Input | Output | Implementation |
|-------|-------|--------|----------------|
| **DAG AI** | Problem description | Complete block chain | `discover_block_chain()` |
| **Block AI** | Task for this block | Filled arguments | `discover_block_args()` |

## The Code Block = Block + AI

The current LLM Transform Block is really:

```
┌─────────────────┐   ┌─────────────────┐
│   Code Block    │ + │  AI Assistant   │  =  LLM Transform Block
│ (executes R)    │   │ (helps write)   │
└─────────────────┘   └─────────────────┘
```

This pattern applies to ALL blocks - AI assistant is composable, not built-in.

## Iteration Needs by Block Type

| Block Type | Degrees of Freedom | AI Iterations |
|------------|-------------------|---------------|
| filter_block | Low (pick column, values) | 1-2 |
| summarize_block | Medium (func, cols, grouping) | 2-3 |
| code_block | Very High (arbitrary R) | 3-5+ |

## Benefits

1. **Reusable**: Same AI works with filter, summarize, code, any block
2. **Composable**: Blocks don't need AI built-in, it's layered on top
3. **Two scopes**: DAG-level for big picture, block-level for details
4. **Simple mental model**: "AI helps me configure things"

---

# Slide 13: Headless Block Execution

## The Key Insight

The deterministic loop from Part 1 runs **code** headlessly.
The same pattern works for **any block**.

## From Code to Blocks

| Part 1 | Part 2 |
|--------|--------|
| Run R code headlessly | Run any block headlessly |
| Validate output | Validate output |
| Iterate until correct | Iterate until correct |

## `run_block_headless()`

```r
# Run any block without UI
result <- run_block_headless(
 block_ctor = new_filter_block,
 data = iris,
 conditions = list(...)
)
```

- Same pattern as code execution
- Works with filter, summarize, mutate, any block
- Returns result for validation

## Iteration Needs by Block Complexity

| Block Type | Degrees of Freedom | Iterations |
|------------|-------------------|------------|
| filter_block | Low (column + values) | 1-2 |
| summarize_block | Medium (func, cols, grouping) | 2-3 |
| **code_block** | **High (arbitrary R)** | **3-5+** |

Code block may need more iterations and tweaked prompts due to unlimited possibilities.

## Unified Pattern

Same headless execution for all blocks - complexity handled by iteration count.

```
┌─────────────────┐
│  filter_block   │ ──┐
├─────────────────┤   │
│ summarize_block │ ──┼──► run_block_headless() ──► validate ──► iterate
├─────────────────┤   │
│   code_block    │ ──┘
└─────────────────┘
```

---

# Slide 14: AI Assistant UI (Figma Draft)

## The Problem

How do users access the AI assistant within a block?

## UI Requirements

- **Discoverable** but not intrusive
- Let users type natural language requests
- Show when AI is working
- Show what changed after AI fills fields
- Allow easy undo
- User should see both AI input and form fields

## Design Exploration (Figma Draft)

See Figma for UI explorations. Key patterns to consider:

| Pattern | Description |
|---------|-------------|
| **Header icon** | Sparkle icon next to Input/Output buttons |
| **Sidebar panel** | Slides in from right, form stays visible |
| **Top inline input** | Collapsible text field above form |
| **Floating bubble** | Chat-style popup in corner |
| **Mode switch** | Toggle between Manual and AI mode |

## Interaction States

1. **Closed** - Just an icon, minimal footprint
2. **Open** - Text input ready for request
3. **Loading** - AI is processing
4. **Success** - Fields filled, highlight changes
5. **Error** - Show message, allow retry

## Next Steps

- Review Figma explorations
- User testing on preferred pattern
- Implement chosen design

---

# Slide 15: Outlook - AI in Workflows

## Two AI Roles in blockr

| Role | What it does | Status |
|------|--------------|--------|
| **AI Assistant** | Helps configure blocks/workflows | Prototype built |
| **AI Decision Block** | Processes data with LLM in the flow | Future work |

## AI Decision Block Concept

A block that uses LLM to enrich/classify data:

```
[data] → [AI Decision Block] → [enriched data]
              │
        "Classify urgency"
        "Flag anomalies"
        "Extract entities"
```

## Example Use Case

**Input:**
| id | description |
|----|-------------|
| 1 | Server is down |
| 2 | Typo in footer |

**After AI Decision Block** ("classify urgency"):
| id | description | urgency |
|----|-------------|---------|
| 1 | Server is down | high |
| 2 | Typo in footer | low |

## What's NOT AI (Workflow Automation)

These belong to blockr.workflow, not blockr.ai:

- Scheduling (run daily at 9am)
- File watchers (run on data update)
- n8n/Zapier integration
- Headless execution

The AI Decision Block can be **used in** automated workflows, but automation itself is not an AI feature.

## Summary: blockr.ai Scope

| In Scope | Out of Scope |
|----------|--------------|
| AI Assistant (configure) | Scheduling |
| AI Decision Block (process) | Triggers |
| Deterministic transform | n8n integration |

---

# Slide 16: Terminology - Assistant vs Agent

## Two Levels of AI Help

| Term | Level | What it does |
|------|-------|--------------|
| **AI Assistant** | Block | Helps fill one block's fields |
| **AI Agent** | Workflow | Plans and builds entire workflows |

## AI Assistant (Block-Level)

```
User: "Keep only rows where mpg > 20"
        ↓
AI fills in filter_block fields
        ↓
Done (single block configured)
```

- Reactive: responds to specific request
- Bounded: one block at a time
- User decides which block to use

## AI Agent (Workflow-Level)

```
User: "Explore this dataset"
        ↓
AI plans: summary → distributions → correlations → plots
        ↓
AI builds each block, validates, iterates
        ↓
Done (complete workflow created)
```

- Autonomous: decides what blocks to use
- Multi-step: plans → executes → validates
- Open-ended: can handle exploratory prompts

## Same Technology, Different Scope

Both use the same underlying capabilities:
- LLM for understanding intent
- Block signatures for configuration
- Headless runner for validation

The difference is **scope and autonomy**:

| Aspect | Assistant | Agent |
|--------|-----------|-------|
| Scope | Single block | Entire workflow |
| Autonomy | User-directed | Self-directed |
| Planning | None | Multi-step |
| Prompt style | "Fill this" | "Build me..." |

---

# Appendix: Glossary

| Term | Definition |
|------|------------|
| **AI Assistant** | Block-level AI that helps fill one block's fields |
| **AI Agent** | Workflow-level AI that plans and builds entire workflows |
| **AI Decision Block** | Block that uses LLM to process/classify data in the flow |
| **Harness** | Framework that runs tests under controlled conditions |
| **Tool calling** | LLM invoking external functions via structured output |
| **Skill** | Markdown file teaching a specific code pattern |
| **Progressive disclosure** | LLM sees only skill metadata upfront, requests full content on demand |
| **Deterministic loop** | System-controlled flow: show data → LLM writes code → system runs → iterate until DONE |
| **Validation loop** | Retry mechanism that ensures LLM produces valid output |
| **Pass@k** | Probability that at least 1 of k attempts succeeds |
| **Claude-as-judge** | Using an LLM to evaluate output quality |

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
