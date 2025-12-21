# Concept: Universal AI Assistant for blockr

## Overview

Move from specialized LLM blocks to a universal AI assistant that works at two levels:
1. **Block level**: Helps configure any individual block
2. **DAG level**: Creates entire workflows from natural language

## Current State

```
┌─────────────────────────┐
│  LLM Transform Block    │  ← Specialized, monolithic
│  (AI + code bundled)    │
└─────────────────────────┘
```

- AI is embedded inside specific block types
- Each AI-enabled block is a separate implementation
- Not reusable across block types

## Proposed Architecture

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
│               │       │               │
│ "Describe     │       │ "Help me      │
│  problem"     │       │  configure    │
│      ↓        │       │  this block"  │
│ Creates       │       │      ↓        │
│ whole chain   │       │ Fills current │
│               │       │ block         │
└───────────────┘       └───────────────┘
```

## Two Entry Points, Same Capability

### DAG-Level AI

**Context**: User is in the DAG/workflow view (blockr.dag)
**Input**: Natural language problem description
**Output**: Complete block chain with connections and configuration

**Example**:
```
User: "Filter iris to setosa, then calculate mean Sepal.Length"
  ↓
AI creates:
  [filter_block] → [summarize_block]
  with correct arguments for each
```

**Implementation**: `discover_block_chain()`

### Block-Level AI

**Context**: User is editing a specific block
**Input**: Natural language description of what this block should do
**Output**: Filled-in arguments for the current block

**Example**:
```
User: "Keep only rows where Species is setosa"
  ↓
AI fills filter_block with:
  conditions = list(list(column = "Species", values = "setosa"))
```

**Implementation**: `discover_block_args()`

## The Code Block Special Case

The current "LLM Transform Block" becomes:

```
┌─────────────────┐   ┌─────────────────┐
│   Code Block    │ + │  AI Assistant   │
│ (executes R)    │   │ (helps write)   │
└─────────────────┘   └─────────────────┘
```

- **Code Block**: Simple block that takes R code as input, executes it
- **AI Assistant**: Helps write the code when asked
- Together they equal the current LLM Transform Block

### Why This Matters

| Block Type | Degrees of Freedom | Iterations Typical |
|------------|-------------------|-------------------|
| filter_block | Low | 1-2 |
| summarize_block | Medium | 2-3 |
| mutate_expr_block | Medium-High | 2-4 |
| **code_block** | **Very High** | **3-5+** |

For code blocks, the AI may need more iterations because:
- Infinite possibilities in arbitrary R code
- More ways to make mistakes
- Need to validate output matches intent

## Implementation Components

### Already Built (blockr.ai)

| Component | File | Purpose |
|-----------|------|---------|
| `run_block_headless()` | `R/run-block-headless.R` | Execute any block without UI |
| `discover_block_args()` | `R/discover-block-args.R` | AI fills single block |
| `discover_block_chain()` | `R/discover-chain.R` | AI creates whole workflow |
| `get_dplyr_block_info()` | `R/dplyr-blocks.R` | Block descriptions for LLM |

### To Build

| Component | Purpose |
|-----------|---------|
| Block-level AI UI | "Ask AI" button in each block |
| DAG-level AI UI | Text input in DAG view |
| Code block | Simple block that executes arbitrary R |
| Integration with blockr.dag | Wire up chain creation to DAG |

## User Experience

### Scenario 1: DAG View

1. User opens DAG view (empty or with existing blocks)
2. Types: "Load mtcars, filter to 6+ cylinders, add hp_per_cyl, summarize by cyl"
3. AI creates 4 connected blocks, configured correctly
4. User can tweak individual blocks if needed

### Scenario 2: Block View

1. User adds a filter_block manually
2. Clicks "Ask AI" or opens AI panel
3. Types: "Keep cars with mpg above 25"
4. AI fills in the filter expression
5. User sees result preview, accepts or modifies

### Scenario 3: Code Block

1. User adds a code_block
2. Types: "Calculate rolling 7-day average of sales"
3. AI writes the R code, runs it, shows result
4. If error, AI iterates until correct
5. User accepts the final code

## Technical Design

### Unified AI Function

```r
ai_assist <- function(
  prompt,
  data,
  context = c("block", "dag"),
  block_ctor = NULL,  # Required if context = "block"
  max_iterations = 5,
  model = "gpt-4o-mini"
) {
  if (context == "dag") {
    discover_block_chain(prompt, data, model = model)
  } else {
    discover_block_args(prompt, data, block_ctor, model = model)
  }
}
```

### Integration Points

**blockr.dag**:
- Add text input for problem description
- Call `ai_assist(context = "dag")`
- Render returned chain in DAG view

**blockr.core / block UI**:
- Add AI assist button/panel to block UI
- Call `ai_assist(context = "block", block_ctor = current_block)`
- Fill block fields with returned args

## UI Design (Figma Draft)

See Figma for UI explorations.

**Figma Prompt Used:**

> **AI Assistant for Data Block Editor**
>
> **What we're building:**
> A data analysis tool where users configure "blocks" (Filter, Summarize, etc.) through form inputs. We want to add an AI assistant that helps users fill these forms using natural language.
>
> **The problem:**
> Users sometimes struggle to configure blocks correctly. We want them to be able to describe what they want in plain English ("keep only rows where Time is greater than 3") and have AI fill the form for them.
>
> **What the AI assistant needs to do:**
> - Be discoverable but not intrusive
> - Let users type a natural language request
> - Show when AI is working
> - Show what changed after AI fills the fields
> - Allow easy undo
>
> **Context:**
> - This sits inside a block card that already has form fields
> - Users should ideally see both the AI input and the form
> - Clean, minimal existing aesthetic
>
> **Ask:** Explore UI patterns for integrating this AI assistant into the block. Show a few different approaches.

## Open Questions

1. **Iteration Control**: Should users see AI iterations or just final result?
   - Show progress for transparency?
   - Hide for simplicity?

2. **Error Handling**: What if AI can't solve the problem?
   - Show best attempt?
   - Ask for clarification?

3. **Model Selection**: Should users be able to choose models?
   - Power users might want gpt-4o for complex tasks
   - Default to gpt-4o-mini for speed/cost

## Next Steps

1. [ ] Review concept with Nicolas
2. [ ] Design UI mockups for block-level AI
3. [ ] Design UI mockups for DAG-level AI
4. [ ] Implement code_block (simple R execution block)
5. [ ] Integrate AI assistant into block UI
6. [ ] Integrate chain discovery into blockr.dag
