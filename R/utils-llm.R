# LLM Utilities for AI Control Block

#' Create chat client
#' @param model Model name (default from blockr_option("ai_model"))
#' @return An ellmer chat client
#' @noRd
llm_client <- function(model = blockr.core::blockr_option("ai_model", "gpt-4o-mini")) {
  message("[discover] client: ", model)
  chat_fns <- getOption("blockr.chat_function")
  if (!is.null(chat_fns) && model %in% names(chat_fns)) {
    return(chat_fns[[model]]())
  }
  ellmer::chat_openai(model = model)
}










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


#' Create input data preview for LLM prompt
#'
#' Handles all input types: NULL, single data.frame, named list (x, y),
#' or variadic list of data.frames.
#'
#' @param input The raw result from dat() - can be NULL, data.frame, or list
#' @return Character string with formatted preview section, or "" if no data
#' @noRd
data_preview <- function(input) {
  if (is.null(input) || (is.list(input) && length(input) == 0)) {
    return("")
  }

  body <- if (is.list(input) && !is.data.frame(input) &&
              !is.object(input) && length(input) > 0) {
    previews <- vapply(seq_along(input), function(i) {
      name <- names(input)[i] %||% paste0("Input ", i)
      paste0("## ", name, "\n\n", data_schema(input[[i]]))
    }, character(1))
    paste(previews, collapse = "\n\n")
  } else {
    data_schema(input)
  }

  paste0("# Input Data\n\n", body, "\n\n")
}


#' Normalize data into a named list for exploration backends
#' @param data Input data (data.frame, dm, named list, or other)
#' @return Named list
#' @noRd
normalize_datasets <- function(data) {
  if (is.null(data)) return(list())
  if (is.data.frame(data)) return(list(data = data))
  if (inherits(data, "dm")) {
    nms <- names(data)
    return(setNames(lapply(nms, function(n) data[[n]]), nms))
  }
  if (is.list(data) && !is.object(data) && length(data) > 0 && !is.null(names(data))) return(data)
  list(data = data)
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


#' Truncate and collapse whitespace for log messages
#' @param x Character string
#' @param n Max characters (default 200)
#' @return Truncated single-line string
#' @noRd
truncate_for_log <- function(x, n = 200) {
  x <- gsub("\\s+", " ", x)
  if (nchar(x) <= n) x else paste0(substr(x, 1, n), "...")
}


#' Format current block state for LLM prompt
#' @param state Plain list of current parameter values, or NULL
#' @return Character string with formatted section, or "" if NULL/empty
#' @noRd
format_current_state <- function(state) {
  if (is.null(state) || length(state) == 0) return("")
  json <- jsonlite::toJSON(state, auto_unbox = TRUE, pretty = TRUE)
  paste0("# Current Configuration\n\n```json\n", json, "\n```\n\n")
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




#' Get registry info for a block type
#' @param block_name Name of the block class
#' @return List with name, description, category (or NULLs if not found)
#' @noRd
get_block_registry_info <- function(block_name) {
  tryCatch(
    {
      meta <- blockr.core::registry_metadata(block_name,
        fields = c("name", "description", "category"))
      list(
        name = meta$name,
        description = meta$description,
        category = meta$category
      )
    },
    error = function(e) list(name = NULL, description = NULL, category = NULL)
  )
}


#' Get raw parameter documentation vector for a block type
#'
#' Returns the named character vector from the registry with attributes intact,
#' so that `generate_example_json()` can extract `example` attributes.
#'
#' @param block_name Name of the block
#' @return Named character vector (with attributes) or NULL
#' @noRd
get_block_param_docs_raw <- function(block_name) {
  args <- tryCatch(
    blockr.core::registry_metadata(block_name, "arguments"),
    error = function(e) NULL
  )
  # registry_metadata returns list(value) for list-type fields
  if (is.list(args) && length(args) == 1L) args <- args[[1L]]
  if (is.null(args) || length(args) == 0 || is.null(names(args))) {
    return(NULL)
  }
  args
}


#' Generate example JSON from argument attributes
#'
#' Reads the `examples` attribute (a named list of R values) from the arguments
#' vector and converts it to a JSON string via `jsonlite::toJSON()`.
#'
#' @param args Named character vector or list with an `examples` attribute
#'   containing a named list of R values (e.g. `list(columns = list("mpg", "cyl"),
#'   exclude = FALSE)`).
#' @return A JSON object string, or NULL if no examples found
#' @noRd
generate_example_json <- function(args) {
  if (is.null(args)) return(NULL)
  examples <- attr(args, "examples")
  if (is.null(examples)) return(NULL)
  jsonlite::toJSON(examples, auto_unbox = TRUE, null = "null")
}
