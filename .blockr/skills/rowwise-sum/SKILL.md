---
name: rowwise-sum
description: Calculate row-wise sums across multiple columns. Use when summing values across columns for each row, especially after pivoting.
---

# Row-wise Sum Pattern

## The Problem

The `.` placeholder does NOT work with native pipe `|>` inside `mutate()`.

```r
# WRONG - . not available with native pipe
data |>
  dplyr::mutate(total = rowSums(dplyr::select(., -id)))  # Error!

# WRONG - dplyr::rowSums doesn't exist
data |>
  dplyr::mutate(total = dplyr::rowSums(...))  # Error!
```

## Solution: Use dplyr::across() with rowSums

```r
# CORRECT - use across() to select columns, then rowSums
data |>
  dplyr::mutate(total = rowSums(dplyr::across(dplyr::where(is.numeric))))
```

## Pattern for Pivoted Data with Numeric Column Names

After `pivot_wider()` with numeric values like quarters (1, 2, 3, 4):

```r
data |>
  tidyr::pivot_wider(names_from = quarter, values_from = sales) |>
  dplyr::mutate(total = `1` + `2` + `3` + `4`)  # Simple approach
```

Or for many columns:

```r
data |>
  tidyr::pivot_wider(names_from = quarter, values_from = sales) |>
  dplyr::mutate(total = rowSums(dplyr::across(dplyr::where(is.numeric))))
```

## Key Rules

1. Use `rowSums()` from base R (not `dplyr::rowSums`)
2. Use `dplyr::across()` to select columns (not `dplyr::select(., ...)`)
3. Numeric column names need backticks: `` `1` + `2` + `3` ``
