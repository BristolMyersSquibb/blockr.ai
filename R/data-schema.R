# data_schema(): what a block result looks like, for a model reading it.
# Packages that own a result type register methods on this generic.

#' Produce a text schema of a data object for LLM consumption
#'
#' S3 generic that summarises an object's structure (dimensions, column types,
#' sample rows, keys, etc.) as a character string suitable for inclusion in an
#' LLM prompt.  Packages can define methods for custom types (e.g.
#' \pkg{blockr.dm} registers a \code{dm} method).
#'
#' @section Future:
#' Consider moving this generic to \pkg{blockr.core} so that any package can
#' provide methods without depending on \pkg{blockr.ai}.
#'
#' @param x Object to summarise.
#' @param ... Additional arguments passed to methods.
#' @return Character string.
#' @export
data_schema <- function(x, ...) {
  UseMethod("data_schema")
}

#' @rdname data_schema
#' @export
data_schema.data.frame <- function(x, ...) {
  format_df_preview(x)
}

# =============================================================================
# NO `data_schema` METHOD FOR `dm` (OR ANY OTHER PACKAGE'S TYPE) BELONGS HERE.
# -----------------------------------------------------------------------------
# `data_schema` is a generic. A method for a type belongs in the package that
# OWNS that type, where it is registered onto this generic via S3method():
#   - dm                      -> blockr.dm   (R/data-schema.R)   <- canonical
#   - gt_tbl / flextable / composed_*  -> blockr.sandbox (R/composer-ai-view.R)
# blockr.ai itself carries ONLY data.frame / default / ggplot (below).
#
# WHY THIS MATTERS (this was a real bug -- see #85): if you ALSO define
# `data_schema.dm` here, BOTH packages call `S3method(data_schema, dm)` and the
# winner is whichever namespace loaded LAST. In a deployed app blockr.dm loads
# after blockr.ai, so blockr.ai's copy is silently shadowed and its edits do
# NOTHING; under `load_all()` the order can flip, so the two copies diverge and
# behaviour depends on load order. One generic, one method per type, one home.
# Do not re-add a dm method here. Fix blockr.dm/R/data-schema.R instead.
# =============================================================================

#' @rdname data_schema
#' @export
data_schema.default <- function(x, ...) {
  cls <- paste(class(x), collapse = ", ")
  summary <- tryCatch({
    lines <- utils::capture.output(utils::str(x, max.level = 2, list.len = 20))
    if (length(lines) > 30) lines <- c(lines[1:30], "... (truncated)")
    paste(lines, collapse = "\n")
  }, error = function(e) {
    tryCatch(
      paste(utils::capture.output(print(x)), collapse = "\n"),
      error = function(e2) "(no preview available)"
    )
  })
  paste0("Object of class: ", cls, "\n", summary)
}

#' Format a single data.frame for preview
#' @noRd
format_df_preview <- function(df) {
  col_info <- vapply(df, function(x) {
    paste0(class(x)[1])
  }, character(1))
  cols <- paste0(names(df), " (", col_info, ")", collapse = ", ")

  header <- paste0(nrow(df), " rows x ", ncol(df), " cols: ", cols)

  # Add sample rows so the LLM can see actual values
  sample_text <- tryCatch({
    n_show <- min(5L, nrow(df))
    if (n_show == 0L) return(header)
    sample_df <- utils::head(df, n_show)
    lines <- utils::capture.output(print(sample_df, right = FALSE))
    paste0("\n\nFirst ", n_show, " rows:\n", paste(lines, collapse = "\n"))
  }, error = function(e) "")

  # Add per-column unique value summaries (crucial for value-based filters)
  col_summary <- tryCatch(format_column_summaries(df), error = function(e) "")

  paste0(header, sample_text, col_summary)
}

#' Format per-column summaries showing unique values
#'
#' For columns with few unique values (<= `max_unique`), lists all of them.
#' For high-cardinality columns the push stays small and the model is expected
#' to pull exact values with `data_tool` when it needs them: numeric columns get
#' a distribution summary (min/p25/median/p75/max, mean, sd) and categorical
#' columns get the most frequent values with their counts. The cap is
#' deliberately low (10) -- a short preview to orient on, not the full set.
#'
#' @param df A data.frame
#' @param max_unique Maximum unique values to list in full per column
#' @return Character string with summary section, or ""
#' @noRd
format_column_summaries <- function(df, max_unique = 10L) {
  if (ncol(df) == 0L || nrow(df) == 0L) return("")

  lines <- vapply(names(df), function(nm) {
    vals <- df[[nm]]
    present <- vals[!is.na(vals)]
    uvals <- unique(present)
    n_unique <- length(uvals)
    n_na <- sum(is.na(vals))
    na_note <- if (n_na > 0L) paste0(" (", n_na, " NA)") else ""
    head <- paste0("  ", nm, ": ", n_unique, " unique", na_note)

    if (n_unique <= max_unique) {
      uvals <- if (is.numeric(uvals)) sort(uvals) else sort(as.character(uvals))
      return(paste0(head, ": ", paste(uvals, collapse = ", ")))
    }

    if (is.numeric(present)) {
      q <- stats::quantile(present, probs = c(0, .25, .5, .75, 1), names = FALSE)
      paste0(head, ", min/p25/median/p75/max = ",
             paste(signif(q, 4), collapse = "/"),
             ", mean ", signif(mean(present), 4),
             ", sd ", signif(stats::sd(present), 4))
    } else {
      counts <- sort(table(as.character(present)), decreasing = TRUE)
      top <- utils::head(counts, max_unique)
      top_str <- paste0(names(top), " (", as.integer(top), ")", collapse = ", ")
      paste0(head, ", top: ", top_str)
    }
  }, character(1))

  paste0("\n\nColumn values:\n", paste(lines, collapse = "\n"))
}

#' @rdname data_schema
#' @export
data_schema.ggplot <- function(x, ...) {
  layers <- vapply(x$layers, function(l) {
    geom <- class(l$geom)[1]
    aes <- paste(names(l$mapping), collapse = ", ")
    if (nzchar(aes)) paste0(geom, " (", aes, ")") else geom
  }, character(1))

  global_aes <- paste(names(x$mapping), collapse = ", ")

  parts <- c(
    paste0("ggplot with ", length(x$layers), " layer(s):"),
    paste0("- ", layers),
    if (nzchar(global_aes)) paste0("Global mappings: ", global_aes)
  )
  paste(parts, collapse = "\n")
}
