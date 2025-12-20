---
name: time-series-lag
description: Calculate lagged values, period-over-period changes, and growth rates within groups. Use when user asks for previous period values, lag calculations, month-over-month or year-over-year comparisons, or growth rates.
---

# Time-Series Lag Calculations in R

## Critical Rules

1. **Group before lag**: Always `dplyr::group_by()` before using `dplyr::lag()`
2. **Sort before lag**: Data must be sorted by time within groups
3. **Ungroup after**: Always `dplyr::ungroup()` after grouped operations
4. **Handle first-row NA**: `dplyr::lag()` returns NA for first row in each group

## Standard Pattern

```r
data |>
  dplyr::arrange(group_col, date_col) |>
  dplyr::group_by(group_col) |>
  dplyr::mutate(
    prev_value = dplyr::lag(value_col, n = 1),
    change = (value_col - prev_value) / prev_value,
    change = round(change, 3),
    change = dplyr::coalesce(change, 0)  # Replace NA with 0
  ) |>
  dplyr::ungroup()
```

## Common Errors

### Wrong: Lag without grouping
```r
# WRONG - lags across all rows, not within groups
data |>
  dplyr::mutate(prev = dplyr::lag(value))

# CORRECT - lag within each group
data |>
  dplyr::group_by(region) |>
  dplyr::mutate(prev = dplyr::lag(value)) |>
  dplyr::ungroup()
```

### Wrong: Lag without sorting
```r
# WRONG - lag based on row order, not time order
data |>
  dplyr::group_by(region) |>
  dplyr::mutate(prev = dplyr::lag(value))

# CORRECT - sort first
data |>
  dplyr::arrange(region, date) |>
  dplyr::group_by(region) |>
  dplyr::mutate(prev = dplyr::lag(value))
```

### Wrong: Forgetting NA handling
```r
# WRONG - first row has NA, division produces NA
data |>
  dplyr::mutate(change = (value - prev) / prev)

# CORRECT - handle NA explicitly
data |>
  dplyr::mutate(
    change = dplyr::if_else(is.na(prev), 0, (value - prev) / prev)
  )
# OR
data |>
  dplyr::mutate(
    change = (value - prev) / prev,
    change = dplyr::coalesce(change, 0)
  )
```

## Date Parsing

If dates are strings, parse first:

```r
data |>
  dplyr::mutate(date = lubridate::ymd(date))
# OR
data |>
  dplyr::mutate(date = as.Date(date, format = "%Y-%m-%d"))
```

## Growth Labels

```r
data |>
  dplyr::mutate(
    growth = dplyr::case_when(
      change > 0 ~ "up",
      change < 0 ~ "down",
      TRUE ~ "flat"
    )
  )
```
