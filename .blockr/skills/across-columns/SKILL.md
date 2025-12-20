---
name: across-columns
description: Apply functions to multiple columns at once using dplyr::across(). Use when summarizing or transforming columns by pattern (starts_with, ends_with, contains).
---

# Across Pattern for Multiple Columns

## The Rule

When applying a function to multiple columns selected by pattern, use `dplyr::across()`:

```r
# CORRECT
data |>
  dplyr::summarize(dplyr::across(starts_with("value_"), sum))

# WRONG - tidyselect doesn't work directly in summarize
data |>
  dplyr::summarize(sum(starts_with("value_")))  # Error!
```

## Pattern

```r
data |>
  dplyr::group_by(grouping_col) |>
  dplyr::summarize(dplyr::across(SELECTION, FUNCTION))
```

Where:
- SELECTION: `starts_with("x")`, `ends_with("x")`, `contains("x")`, or `c(col1, col2)`
- FUNCTION: `sum`, `mean`, `max`, `min`, etc. (without parentheses)

## Examples

Sum all value columns by group:
```r
data |>
  dplyr::group_by(category) |>
  dplyr::summarize(dplyr::across(starts_with("value_"), sum))
```

Calculate mean for specific columns:
```r
data |>
  dplyr::group_by(region) |>
  dplyr::summarize(dplyr::across(c(sales, revenue, profit), mean))
```
