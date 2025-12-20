# LLM Run Improvement Options

Based on mtcars-complex experiment results (Variant D: 100% success vs Baseline: 40%).

## Proven Improvements

### Variant D: Preview + Validation (IMPLEMENTED)
- **What**: LLM sees result preview + retry loop if no valid data.frame
- **Result**: 100% success on complex tasks
- **Status**: Ready to deploy

## Untested Improvements

### 1. Skills (like Claude Code)

Pre-written prompts injected for specific task types.

#### Claude Code Skill Architecture

Skills are **model-invoked** (not user-invoked like slash commands):
- Claude autonomously decides to use a skill based on its **description**
- Skills live in `.claude/skills/{skill-name}/SKILL.md`
- YAML frontmatter defines metadata, markdown body has instructions

```yaml
# .claude/skills/pivot-table/SKILL.md
---
name: pivot-table
description: Create pivot tables from long data. Use when user asks for
  crosstabs, pivot tables, or wants to reshape data from long to wide format.
---

# Pivot Table Skill

## Instructions
When creating pivot tables in R:
1. Use tidyr::pivot_wider() (NOT dplyr::pivot_wider)
2. Always specify values_fill = 0 for missing combinations
3. Column names from values become backtick-quoted (`4`, `6`, `8`)

## Code Pattern
```r
data |>
  dplyr::count(row_var, col_var) |>
  tidyr::pivot_wider(
    names_from = col_var,
    values_from = n,
    values_fill = 0
  )
```
```

#### How Skills Get Injected

1. **Startup**: Scan skill directories, extract name + description
2. **Prompt time**: Add skill descriptions to system prompt
3. **Model inference**: Claude matches description to request
4. **Execution**: Full skill content loaded for matched skills

#### Proposed blockr.ai Skills

```
.blockr/skills/
  pivot-table/SKILL.md        # tidyr::pivot_wider patterns
  percentage-calc/SKILL.md    # Ensure sum to 1.0, decimal format
  groupby-summarize/SKILL.md  # dplyr::group_by + summarize
  column-rename/SKILL.md      # Handle backtick-quoted names
  join-tables/SKILL.md        # dplyr join patterns
  time-series/SKILL.md        # lubridate date handling
```

**Pros:**
- Proven in Claude Code
- Model-invoked (automatic, no user action needed)
- Addresses "LLM doesn't know R best practices"
- Shareable via git

**Cons:**
- Need to build skill library
- Description quality is critical for matching

### 2. Few-Shot Examples

Include 1-3 working examples in the system prompt.

```
Example task: "Calculate mean by group"
Example code:
  data |>
    dplyr::group_by(category) |>
    dplyr::summarize(mean_val = mean(value))
```

**Pros:**
- Simple to implement
- Improves first-try success

**Cons:**
- Increases token usage
- Examples may not match user's task

### 3. Tool Redesign

| Option | Rationale |
|--------|-----------|
| Single tool only | Remove data_tool distraction |
| Rename to `submit_code` | "submit" implies finality |
| Add `plan_tool` | LLM describes approach before coding |
| Add `verify_tool` | Explicit verification step |

**Evidence from experiments:**
- data_tool DOES distract: 2/5 baseline runs failed because LLM explored but never committed
- Validation loop catches this, but better tool design might prevent it

### 4. Self-Critique Loop

After getting result, ask LLM to critique its own output:

```
"Does this output match the requirements? List any issues:
- Column names correct?
- Values in expected range?
- Sorting correct?
- Missing values handled?"
```

**Pros:**
- Catches logical errors
- Works with any model

**Cons:**
- Extra LLM call (cost/latency)
- May over-critique correct results

### 5. Code Templates/Scaffolding

Provide structured template instead of free-form code:

```r
# Fill in the blanks:
data |>
  dplyr::filter({condition}) |>
  dplyr::group_by({grouping_cols}) |>
  dplyr::summarize({aggregations}) |>
  dplyr::arrange({sorting})
```

**Pros:**
- Guides LLM toward correct structure
- Reduces syntax errors

**Cons:**
- Less flexible
- May not fit all tasks

### 6. RAG with Code Examples

Retrieve similar code examples from a database based on user prompt.

**Pros:**
- Task-specific examples
- Scales with example library

**Cons:**
- Requires building/maintaining example database
- Retrieval quality varies

## Priority Ranking

| Priority | Improvement | Effort | Expected Impact |
|----------|-------------|--------|-----------------|
| 1 | Skills system | Medium | High |
| 2 | Few-shot examples | Low | Medium |
| 3 | Tool renaming | Low | Low-Medium |
| 4 | Self-critique loop | Medium | Medium |
| 5 | Single tool design | Low | Unknown |
| 6 | Code templates | Medium | Medium |
| 7 | RAG examples | High | High |

## Next Steps

1. ~~Investigate Claude Code skills implementation~~ DONE
2. ~~Prototype skills system for blockr.ai~~ DONE - see `.blockr/skills/`
3. Integrate skills into blockr.ai system prompt
4. Test few-shot examples on mtcars-complex

---

## Prototype Skills Created

Two skills created in `.blockr/skills/`:

### pivot-table
Addresses errors from mtcars-complex:
- Use `tidyr::pivot_wider()` not `dplyr::pivot_wider()`
- Backtick-quote numeric column names
- Rename after pivot, before calculations

### percentage-calc
Addresses percentage calculation issues:
- Decimal (0-1) vs percent (0-100) format
- Rounding to 2 decimal places
- Division by zero handling

---

## Integration Design

### How to Add Skills to blockr.ai

1. **Load skills at startup**:
```r
load_skills <- function(skills_dir = ".blockr/skills") {
  skill_dirs <- list.dirs(skills_dir, recursive = FALSE)
  skills <- lapply(skill_dirs, function(dir) {
    skill_file <- file.path(dir, "SKILL.md")
    if (file.exists(skill_file)) {
      content <- readLines(skill_file, warn = FALSE)
      # Parse YAML frontmatter for name/description
      # Store full content for injection
    }
  })
  skills
}
```

2. **Add skill descriptions to system prompt**:
```r
# In system_prompt() function
skill_section <- paste(
  "## Available Skills",
  "",
  "The following skills provide guidance for specific tasks:",
  "",
  "- **pivot-table**: Create pivot tables, crosstabs, reshape long to wide",
  "- **percentage-calc**: Calculate percentages, proportions, ratios",
  "",
  "When a task matches a skill, follow its instructions carefully.",
  sep = "\n"
)
```

3. **Inject full skill content when relevant**:
```r
# Option A: Always include (simple, more tokens)
# Option B: Keyword matching (detect "pivot", "percentage" in prompt)
# Option C: Let LLM request skills (add skill_tool)
```

### Simplest Integration (Option A)

Just append skill content to system prompt:

```r
system_prompt <- function(proxy, datasets, tools) {
  base_prompt <- # existing prompt...

  # Load and append skills
  skills <- load_skills()
  skill_content <- paste(
    sapply(skills, function(s) s$content),
    collapse = "\n\n---\n\n"
  )

  paste(base_prompt, "\n\n# Skills\n\n", skill_content)
}
```

### Token Cost Estimate

- pivot-table skill: ~800 tokens
- percentage-calc skill: ~500 tokens
- Total overhead: ~1300 tokens per request

With gpt-4o-mini at $0.15/1M input tokens: ~$0.0002 per request (negligible)
