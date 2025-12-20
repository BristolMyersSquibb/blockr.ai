---
name: pivot-table
description: Create pivot tables, crosstabs, or reshape data from long to wide format. Use when user asks to pivot, create crosstabs, count by two variables, or transform rows into columns.
---

# Pivot Table Skill for R/dplyr

## Critical Rules

1. **Use tidyr::pivot_wider()** - NOT dplyr::pivot_wider (it doesn't exist)
2. **Numeric column names need backticks** - After pivoting on numeric values like `cyl`, columns are named `4`, `6`, `8` and must be referenced as `` `4` ``, `` `6` ``, `` `8` ``
3. **Rename AFTER pivot, BEFORE calculations** - If you need friendly names like `n_4cyl`, rename immediately after pivot_wider
4. **Always use values_fill** - Prevent NA values with `values_fill = 0`

## Common Error: Wrong Package

```r
# WRONG - will error
dplyr::pivot_wider(...)

# CORRECT
tidyr::pivot_wider(...)
```

## Common Error: Column Reference Timing

```r
# WRONG - n_4cyl doesn't exist yet
data |>
  tidyr::pivot_wider(...) |>
  dplyr::mutate(total = n_4cyl + n_6cyl + n_8cyl)  # Error!

# CORRECT - use backtick names first, then rename
data |>
  tidyr::pivot_wider(...) |>
  dplyr::mutate(total = `4` + `6` + `8`) |>
  dplyr::rename(n_4cyl = `4`, n_6cyl = `6`, n_8cyl = `8`)
```

## Standard Pattern

```r
data |>
  dplyr::count(row_var, col_var) |>
  tidyr::pivot_wider(
    names_from = col_var,
    values_from = n,
    values_fill = 0
  ) |>
  # If renaming: do calculations with backtick names first
  dplyr::mutate(total = `value1` + `value2` + `value3`) |>
  # Then rename
dplyr::rename(
    friendly_name1 = `value1`,
    friendly_name2 = `value2`
  )
```

## With names_prefix (Alternative)

If you want auto-prefixed names, use names_prefix:

```r
tidyr::pivot_wider(
  names_from = cyl,
  values_from = n,
  values_fill = 0,
  names_prefix = "n_"
)
# Creates columns: n_4, n_6, n_8 (no backticks needed)
```

## Complete Example

Task: Count cars by gear and cylinder, add total column

```r
mtcars |>
  dplyr::count(gear, cyl) |>
  tidyr::pivot_wider(
    names_from = cyl,
    values_from = n,
    values_fill = 0
  ) |>
  dplyr::mutate(total = `4` + `6` + `8`) |>
  dplyr::rename(
    n_4cyl = `4`,
    n_6cyl = `6`,
    n_8cyl = `8`
  ) |>
  dplyr::select(gear, n_4cyl, n_6cyl, n_8cyl, total)
```
