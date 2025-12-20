---
name: percentage-calc
description: Calculate percentages, proportions, or ratios. Use when user asks for percentage of total, proportion, share, or ratio calculations. Handles decimal vs percent format and rounding.
---

# Percentage Calculation Skill for R/dplyr

## Key Decisions

1. **Decimal (0-1) vs Percent (0-100)** - Check what user wants:
   - "as decimal" or "between 0 and 1" → divide only
   - "as percentage" or "0-100" → multiply by 100

2. **Rounding** - Always round percentages for readability:
   - `round(pct, 2)` for 2 decimal places

3. **Division by zero** - Handle when total = 0:
   - Use `dplyr::if_else()` or `dplyr::coalesce()`

## Standard Patterns

### Percentage of Row Total
```r
data |>
  dplyr::mutate(
    pct_col = col_value / row_total,
    pct_col = round(pct_col, 2)
  )
```

### Percentage of Group Total
```r
data |>
  dplyr::group_by(group_var) |>
  dplyr::mutate(
    pct = value / sum(value),
    pct = round(pct, 2)
  ) |>
  dplyr::ungroup()
```

### Percentage of Grand Total
```r
data |>
  dplyr::mutate(
    pct = value / sum(value),
    pct = round(pct, 2)
  )
```

## Handle Division by Zero

```r
# Option 1: Replace Inf/NaN with 0
data |>
  dplyr::mutate(
    pct = dplyr::if_else(total == 0, 0, value / total)
  )

# Option 2: Use coalesce for NA
data |>
  dplyr::mutate(
    pct = dplyr::coalesce(value / total, 0)
  )
```

## Verify Percentages Sum to 1

When percentages should sum to 1.0 (or 100%), verify:

```r
# Check sum
sum(data$pct)  # Should be 1.0 or 100

# If rounding causes issues, adjust last value
data |>
  dplyr::mutate(
    pct = value / sum(value),
    pct = round(pct, 2)
  )
# Note: Rounding may cause sum to be 0.99 or 1.01 - usually acceptable
```

## Complete Example

Task: Calculate percentage of 8-cylinder cars per gear group (as decimal 0-1)

```r
data |>
  dplyr::mutate(
    pct_8cyl = n_8cyl / total,
    pct_8cyl = round(pct_8cyl, 2)
  )
```

Output:
```
  gear n_8cyl total pct_8cyl
1    3      7    10     0.70
2    4      0    12     0.00
3    5      1     4     0.25
```
