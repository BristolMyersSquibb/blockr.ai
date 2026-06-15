# The "effect" of applying a configuration -- distinct, testable infrastructure.
#
# Validity ("does the block still evaluate?") is not the same as goodness ("did
# the config do what was asked?"). A valid config can do nothing: a filter that
# removes no rows, a transform that adds no column. `data_effect()` reports what
# actually changed so a caller -- or an LLM in the discovery loop -- can verify
# the effect against intent instead of trusting that valid means correct.
#
# It is an S3 generic dispatched on the RESULT type, mirroring `data_schema()`:
# a data.frame method does the row/column diff (the common, well-tested case);
# the default returns "". Packages can add methods for `dm`, `ggplot`, models,
# etc. the same way they extend `data_schema()`.

#' Describe the effect of applying a configuration to a block's data
#'
#' Summarises what changed between a block's input `data` and the `result` of
#' applying a configuration (rows added/removed, columns added/removed), so that
#' a *valid but ineffective* configuration is visible rather than silently
#' passing as success.
#'
#' S3 generic dispatched on `result`. The `data.frame` method computes the
#' row/column diff against the (single) input data frame. The default returns
#' `""`. Add methods for other result types (`dm`, `ggplot`, model objects) the
#' same way [data_schema()] is extended.
#'
#' @param input The block's input data: a data.frame, a named list of inputs, a
#'   `dm`, or NULL (source blocks).
#' @param result The object produced by applying the configuration.
#' @param ... Passed to methods.
#' @return A short single-line string; `""` when no meaningful diff applies.
#' @export
data_effect <- function(input, result, ...) {
  UseMethod("data_effect", result)
}

#' @rdname data_effect
#' @export
data_effect.default <- function(input, result, ...) {
  ""
}

#' Describe the effect of a config on a CONTROL/VIZ block from its arguments
#'
#' For blocks whose result is a passthrough (a chart/drilldown that filters only
#' on click, a profile that passes its `dm` through), the meaningful artifact is
#' the CONFIG, not the data -- so [data_effect()] on the result is blind (and a
#' passthrough even reads as a no-op). This S3 generic, dispatched on the BLOCK,
#' lets the type-owning package describe what the config set up (and flag invalid
#' column bindings) so the model gets real feedback. The validate tool uses it in
#' place of the data effect when it returns a non-`NULL` string.
#'
#' @param block The block being configured.
#' @param args The validated config (named list of parameters).
#' @param data The block's input data (to check column bindings against).
#' @param ... Passed to methods.
#' @return A short string, or `NULL` to fall back to [data_effect()].
#' @export
config_effect <- function(block, args, data = NULL, ...) {
  UseMethod("config_effect")
}

#' @rdname config_effect
#' @export
config_effect.default <- function(block, args, data = NULL, ...) {
  NULL
}

#' @rdname data_effect
#' @export
data_effect.data.frame <- function(input, result, ...) {
  in_df <- effect_primary_df(input)
  if (is.null(in_df)) {
    # No comparable input (source block, dm, or ambiguous multi-input): describe
    # the output rather than a diff.
    return(sprintf("output: %d rows x %d cols", nrow(result), ncol(result)))
  }

  parts <- character()
  delta <- nrow(in_df) - nrow(result)
  change <- if (delta > 0L) {
    sprintf("%d removed", delta)
  } else if (delta < 0L) {
    sprintf("%d added", -delta)
  } else {
    "UNCHANGED"
  }
  parts <- c(parts, sprintf("rows: %d -> %d (%s)",
                            nrow(in_df), nrow(result), change))

  added   <- setdiff(names(result), names(in_df))
  dropped <- setdiff(names(in_df), names(result))
  if (length(added)) {
    parts <- c(parts, paste0("columns added: ", paste(added, collapse = ", ")))
  }
  if (length(dropped)) {
    parts <- c(parts, paste0("columns removed: ", paste(dropped, collapse = ", ")))
  }

  # In-place changes: a mutate that rewrites a column keeps its name and the row
  # count, so it is invisible to the add/drop diff above and would otherwise read
  # as UNCHANGED. Only comparable when the row count is unchanged.
  modified <- if (delta == 0L) effect_modified_cols(in_df, result) else character()
  if (length(modified)) {
    parts <- c(parts, paste0("columns modified: ", paste(modified, collapse = ", ")))
  }

  if (!length(added) && !length(dropped) && !length(modified) && delta == 0L) {
    parts <- c(parts, "no rows or columns changed")
  }
  paste(parts, collapse = "; ")
}

#' Detect columns present in both frames whose type or values changed in place.
#'
#' Assumes equal row counts (the caller guards this). Reports a type change as
#' `col: type <old> -> <new>` and any other value change as `col: values
#' changed` (this includes a re-sort, which is a real effect worth surfacing).
#' @noRd
effect_modified_cols <- function(in_df, result) {
  shared <- intersect(names(in_df), names(result))
  out <- character()
  for (nm in shared) {
    a <- in_df[[nm]]
    b <- result[[nm]]
    ca <- class(a)[1]
    cb <- class(b)[1]
    if (ca != cb) {
      out <- c(out, sprintf("%s: type %s -> %s", nm, ca, cb))
    } else if (!identical(a, b)) {
      out <- c(out, sprintf("%s: values changed", nm))
    }
  }
  out
}

#' @rdname data_effect
#' @export
data_effect.dm <- function(input, result, ...) {
  out <- effect_tables(result)
  if (is.null(out)) {
    return("")
  }
  inn <- effect_tables(input)

  parts <- character()
  for (nm in names(out)) {
    out_n <- nrow(out[[nm]])
    in_n <- if (!is.null(inn) && nm %in% names(inn)) nrow(inn[[nm]]) else NA_integer_
    if (is.na(in_n)) {
      parts <- c(parts, sprintf("%s: %d rows (new)", nm, out_n))
    } else if (in_n != out_n) {
      parts <- c(parts, sprintf("%s: %d -> %d", nm, in_n, out_n))
    }
  }
  removed <- if (!is.null(inn)) setdiff(names(inn), names(out)) else character()
  if (length(removed)) {
    parts <- c(parts, paste0("tables removed: ", paste(removed, collapse = ", ")))
  }
  if (!length(parts)) {
    return(sprintf("%d tables, UNCHANGED", length(out)))
  }
  paste(parts, collapse = "; ")
}

#' Extract a named list of tables from a dm (or a named list of data frames).
#' @noRd
effect_tables <- function(x) {
  if (inherits(x, "dm")) {
    if (requireNamespace("dm", quietly = TRUE)) {
      t <- tryCatch(dm::dm_get_tables(x),
                    error = function(e) NULL, warning = function(w) NULL)
      if (length(t)) {
        return(t)
      }
    }
    # Fallback for test doubles / plain table lists wearing a dm class.
    t2 <- Filter(is.data.frame, unclass(x))
    if (length(t2)) {
      return(t2)
    }
    return(NULL)
  }
  if (is.list(x) && !is.null(names(x))) {
    dfs <- Filter(is.data.frame, x)
    if (length(dfs)) {
      return(dfs)
    }
  }
  NULL
}

#' Pick a single representative input data frame for effect diffing.
#'
#' Returns the input itself when it is a data.frame, the sole data.frame in a
#' plain named list of inputs, or NULL when there is no unambiguous single input
#' (a `dm`, multiple inputs, or none).
#' @noRd
effect_primary_df <- function(input) {
  if (is.data.frame(input)) {
    return(input)
  }
  if (is.list(input) && !is.object(input)) {
    dfs <- Filter(is.data.frame, input)
    if (length(dfs) == 1L) {
      return(dfs[[1L]])
    }
  }
  NULL
}
