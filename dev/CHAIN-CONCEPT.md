# Concept: Multi-Block Chain Discovery

## Problem
Complex data tasks need multiple blocks chained together.

**Example**: "Filter iris to setosa, then calculate mean of each numeric column"

This needs:
1. `filter_block` → outputs filtered data (50 rows)
2. `summarize_block` → takes filtered data, outputs means

## Approach: Hybrid Planning + Step-by-Step Validation

### Phase 1: Planning
- Show LLM the available blocks and their capabilities
- LLM outputs an ordered plan: `[filter_block, summarize_block]`
- Plan includes rough description of what each step does

### Phase 2: Execution (step by step)
For each block in the plan:
1. Call `discover_block_args()` with:
   - The sub-task for this step
   - The current data (output from previous step)
   - The block constructor
2. Run with `run_block_headless()`
3. Validate the result (check it looks right)
4. Pass result to next step

### Phase 3: Return
- Final result
- Chain definition: list of (block_type, args) pairs
- Can be used to recreate the pipeline

## Available Blocks (blockr.dplyr)

### Row operations
- `filter_block` - Keep rows matching conditions (value-based)
- `filter_expr_block` - Keep rows matching expression (code-based)
- `slice_block` - Take first/last n rows

### Column operations
- `select_block` - Keep/drop columns
- `mutate_block` - Add/modify columns (expression list)
- `mutate_expr_block` - Add/modify columns (code-based)
- `rename_block` - Rename columns

### Aggregation
- `summarize_block` - Aggregate with grouping (structured)
- `summarize_expr_block` - Aggregate (code-based)

### Sorting
- `arrange_block` - Sort by columns

### Reshaping
- `pivot_wider_block` - Long to wide
- `pivot_longer_block` - Wide to long
- `separate_block` - Split column
- `unite_block` - Combine columns

### Combining (requires multiple inputs)
- `join_block` - Merge datasets
- `bind_rows_block` - Stack vertically
- `bind_cols_block` - Stack horizontally

## Function Signature

```r
discover_block_chain <- function(
  prompt,
  data,
  available_blocks = get_dplyr_blocks(),  # list of block info
  max_steps = 5,
  validate_each_step = TRUE,
  model = "gpt-4o-mini",
  verbose = TRUE
)

# Returns:
list(
  result = <final data.frame>,
  success = TRUE/FALSE,
  chain = list(
    list(block = "filter_block", args = list(...), result = <df>),
    list(block = "summarize_block", args = list(...), result = <df>)
  ),
  iterations = 3,
  duration_secs = 12.5
)
```

## Example Usage

```r
result <- discover_block_chain(
  prompt = "Filter iris to setosa, then calculate mean Sepal.Length",
  data = iris
)

# result$chain contains the step-by-step definition
# Can recreate with:
# data %>% run_block_headless(filter_block, args1) %>%
#          run_block_headless(summarize_block, args2)
```

## Open Questions

1. **How to describe blocks to LLM?**
   - Just names? Names + descriptions? Full signatures?

2. **How to split the prompt into sub-tasks?**
   - LLM does it during planning? Or we ask for each step?

3. **What if a step fails?**
   - Retry with different args? Try different block? Backtrack?

4. **How to validate intermediate results?**
   - Show to LLM and ask "does this look right?"
   - Check row/column counts?
