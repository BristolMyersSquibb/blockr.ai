---
description: Evaluate LLM experiment runs in a trial directory
---

Evaluate all run YAML files in the directory: $ARGUMENTS

## Steps

1. List all `run_*.yaml` files in the directory
2. For each YAML file:
   - Read the `prompt` field to understand requirements
   - Read the `result` field to see the actual output
   - Check if the result meets ALL requirements
3. Add an `evaluation` section to each YAML file:
   ```yaml
   evaluation:
     correct: true|false
     reason: "Brief explanation"
   ```
4. Report summary to user

## Evaluation Criteria

- **correct: true** only if ALL requirements from the prompt are met
- **correct: false** if:
  - No result (NULL or empty)
  - Wrong columns
  - Wrong values (e.g., percentages don't sum to 1.0)
  - Wrong sort order
  - Edge cases not handled (e.g., NA not replaced)

## Common Bug to Check

`pct_of_total` computed inside `summarize()` while grouped gives 1.0 per row (sum is per-group, not global). This is WRONG.

## Output Format

```
Evaluated N runs in <directory>:
- run_001.yaml: CORRECT - All requirements met
- run_002.yaml: WRONG - pct_of_total sums to 5.0, not 1.0
- run_003.yaml: CORRECT - All requirements met

Summary: X/N correct
```
