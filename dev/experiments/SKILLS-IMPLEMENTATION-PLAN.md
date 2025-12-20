# Skills Implementation Plan

## Goal

Implement proper progressive disclosure skills like Claude Code:
1. LLM sees only skill metadata (names + descriptions) upfront
2. LLM has a `skill_tool` to request full skill content when needed
3. LLM decides which skills to call based on the task

## Current State

```
System prompt: base instructions + ALL skill content (~10,000 tokens)
Tools: eval_tool, data_tool
```

## Target State

```
System prompt: base instructions + skill catalog (~200 tokens)
Tools: eval_tool, data_tool, skill_tool
```

## Implementation Steps

### Step 1: Create Skill Catalog

Extract just name + description from each SKILL.md frontmatter:

```r
load_skill_catalog <- function(skills_dir = ".blockr/skills") {
  # Returns: list of (name, description) pairs
  # NOT the full content
}
```

Output format for system prompt:
```
Available Skills (call skill_tool to get full instructions):
- rowwise-sum: Calculate row-wise sums across multiple columns
- pivot-table: Create pivot tables, reshape data from long to wide
- time-series-lag: Calculate lagged values and period-over-period changes
- ...
```

### Step 2: Create skill_tool

```r
new_skill_tool <- function(skills) {
  # skills = full skill content (loaded but not in prompt)

  tool_fn <- function(name) {
    if (!name %in% names(skills)) {
      return(paste("Unknown skill:", name,
                   "Available:", paste(names(skills), collapse = ", ")))
    }
    skills[[name]]$content
  }

  # Return ellmer tool with schema
  ellmer::Tool(
    name = "skill_tool",
    description = "Get detailed instructions for a specific skill.
                   Call this when you need guidance on a coding pattern.",
    arguments = list(
      name = ellmer::String("Name of the skill to retrieve")
    ),
    fn = tool_fn
  )
}
```

### Step 3: Update run function

```r
run_llm_ellmer_with_skill_tool <- function(prompt, data, config, ...) {

  # Load skills (full content, but NOT injected into prompt)
  skills <- load_skills(skills_dir)

  # Create skill catalog (just names + descriptions)
  catalog <- create_skill_catalog(skills)

  # Build system prompt with catalog only
  sys_prompt <- system_prompt(proxy, datasets, tools)
  sys_prompt <- inject_skill_catalog(sys_prompt, catalog)

  # Create tools including skill_tool
  tools <- list(
    new_eval_tool_with_result(proxy, datasets),
    new_data_tool(proxy, datasets),
    new_skill_tool(skills)  # NEW: can retrieve full skill content
  )

  # ... rest of the function
}
```

### Step 4: Track skill usage

Record which skills were called in the YAML output:

```yaml
skills:
  available:
    - rowwise-sum
    - pivot-table
    - time-series-lag
    - percentage-calc
    - across-columns
  called:
    - rowwise-sum  # LLM requested this one
  call_count: 1
```

## Experiment Design

### Trial R3: Skills via Tool (Progressive Disclosure)

Compare three approaches for the rowsum task:

| Trial | Approach | Skills in Prompt | Skill Tool |
|-------|----------|------------------|------------|
| R1 | No skills | 0 tokens | No |
| R2 | All skills upfront | ~10,000 tokens | No |
| R3 | Skills via tool | ~200 tokens (catalog) | Yes |

### Metrics to Track

1. **Success rate**: Does LLM produce correct result?
2. **Skill calls**: Which skills did LLM request?
3. **Precision**: Did LLM call only relevant skills?
4. **Token efficiency**: Prompt size comparison
5. **Speed**: Time to completion

### Expected Outcomes

- R3 should call `rowwise-sum` skill (relevant)
- R3 should NOT call `time-series-lag` (irrelevant)
- R3 should be faster than R2 (smaller prompt)
- R3 should be more accurate than R1 (has guidance when needed)

## Files to Modify

1. `dev/harness.R`:
   - Add `load_skill_catalog()`
   - Add `inject_skill_catalog()`
   - Add `new_skill_tool()`
   - Add `run_llm_ellmer_with_skill_tool()`

2. `dev/experiments/run-rowsum-experiment.R`:
   - Add `run_R3_with_skill_tool()`
   - Update `run_rowsum_experiment()` to include R3

## Open Questions

1. Should LLM be able to call multiple skills?
2. Should we limit skill calls (e.g., max 2)?
3. How to handle skill not found?
4. Should skill_tool return structured data or raw markdown?
