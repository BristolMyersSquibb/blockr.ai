# Build a typed ellmer schema from a block's constructor parameters, so the model
# emits NATIVE structured tool arguments (the API handles JSON escaping) instead
# of hand-serialising a JSON-object string into the `config` argument. The win is
# largest for big, quote-heavy free-text params (a composer `fn`), which the
# model cannot reliably escape inside a JSON string.
#
# Types are inferred from each formal's DEFAULT value, mirroring the function-
# block UI's create_input_for_arg(): scalar -> string/number/integer/boolean,
# named list -> nested object (this also forces correct `state` nesting, which
# fixes the flat-vs-wrapped state confusion), character vector -> enum. Arrays of
# objects (polymorphic, e.g. filter `conditions`) fall back to a JSON string the
# model fills and we re-parse -- localised escaping of one small field, not the
# whole config.

#' Typed tool arguments for a block, or NULL to fall back to the JSON-string path.
#' @noRd
block_param_types <- function(block) {
  ctor <- attr(block, "ctor")
  if (is.null(ctor)) return(NULL)
  fmls <- tryCatch(formals(ctor), error = function(e) NULL)
  if (is.null(fmls)) return(NULL)
  nms <- setdiff(names(fmls), "...")
  if (!length(nms)) return(NULL)

  block_name <- class(block)[1]
  docs <- tryCatch(get_block_param_docs_raw(block_name), error = function(e) NULL)
  # The registry `examples` carry the author's canonical SHAPE for each param --
  # crucial when the formal default is uninformative (NULL, character(), list())
  # or ambiguous (an unnamed vector that is really a multi-value array, not enum
  # choices). Prefer the example's shape when present; fall back to the default.
  examples <- tryCatch(attr(docs, "examples"), error = function(e) NULL)
  # The block author's DECLARED machine-readable type (core's `arg_*()`
  # descriptor), when present, is authoritative -- it captures enums and
  # arrays-of-records (the polymorphic fields example-inference can only
  # approximate as a JSON string). Prefer it; fall back to inference otherwise.
  spec <- tryCatch(get_block_arg_spec(block_name), error = function(e) NULL)

  types <- list()
  for (nm in nms) {
    desc <- if (!is.null(docs) && nm %in% names(docs) && nzchar(docs[[nm]])) {
      as.character(docs[[nm]])
    } else {
      nm
    }
    declared <- if (!is.null(spec) && nm %in% names(spec)) {
      tryCatch(blockr.core::block_arg_type(spec[[nm]]), error = function(e) NULL)
    } else {
      NULL
    }
    types[[nm]] <- tryCatch(
      if (!is.null(declared)) {
        ellmer_type_from_descriptor(declared, desc)
      } else if (!is.null(examples) && nm %in% names(examples) && !is.null(examples[[nm]])) {
        ellmer_type_from_value(examples[[nm]], desc)
      } else {
        ellmer_type_from_default(fmls[[nm]], desc)
      },
      error = function(e) ellmer::type_string(desc, required = FALSE)
    )
  }

  types
}

#' Bind a core `arg_*()` type descriptor (a JSON-Schema-subset list) to an ellmer
#' type via `ellmer::type_from_schema()`. The descriptor is serialised to JSON
#' text (the form `type_from_schema()` consumes); `desc` is attached and the
#' field is marked optional so the model may omit it (partial configs are valid).
#' @noRd
ellmer_type_from_descriptor <- function(descriptor, desc = "") {
  json <- as.character(
    jsonlite::toJSON(descriptor, auto_unbox = TRUE, null = "null")
  )
  type <- ellmer::type_from_schema(text = json)
  type@required <- FALSE
  if (nzchar(desc)) {
    type@description <- desc
  }
  type
}

#' @noRd
ellmer_type_from_default <- function(default, desc = "") {
  if (identical(default, quote(expr = ))) {
    return(ellmer::type_string(desc, required = FALSE))
  }
  val <- tryCatch(eval(default, envir = baseenv()), error = function(e) NULL)
  ellmer_type_from_value(val, desc)
}

#' @noRd
#' @param nested TRUE when typing a value INSIDE another object (vs a top-level
#'   param). Top-level objects stay typed structs; the arbitrary-key-map
#'   heuristic only applies to nested values.
ellmer_type_from_value <- function(val, desc = "", nested = FALSE) {
  if (is.null(val) || is.data.frame(val)) {
    return(ellmer::type_string(desc, required = FALSE))
  }
  if (is.list(val)) {
    nm <- names(val)
    if (!is.null(nm) && length(nm) && all(nzchar(nm))) {
      # FALLBACK for blocks that key an object by DATA (a map -- e.g. col->value).
      # A type_object would bake the example's keys in as fixed fields, so the
      # model copies them verbatim. When all values are scalars (a string/number/
      # bool map), pass it as a JSON-object string (arbitrary keys), re-parsed by
      # the tool. Only for NESTED values -- a top-level all-scalar object is
      # kept as a typed struct.
      # NOTE: the proper fix is in the BLOCK -- collections should be arrays of
      # fixed-field records (see mutate/summarize/rename), not data-keyed maps;
      # this heuristic only catches blocks that haven't been reshaped.
      if (nested && all(vapply(val, function(v) is.atomic(v) && length(v) == 1L,
                     logical(1)))) {
        ex <- tryCatch(as.character(jsonlite::toJSON(val, auto_unbox = TRUE)),
                       error = function(e) NULL)
        d <- if (!is.null(ex)) {
          paste0(desc, " -- a JSON object of key->value pairs, e.g. ", ex,
                 " (replace BOTH keys and values with the data's actual names)")
        } else {
          paste0(desc, " (a JSON object of key->value pairs)")
        }
        return(ellmer::type_string(d, required = FALSE))
      }
      # Named list -> nested object (recurse). Forces correct `state` nesting.
      fields <- list()
      for (i in seq_along(val)) {
        fields[[nm[i]]] <- ellmer_type_from_value(val[[i]], nm[i], nested = TRUE)
      }
      return(do.call(
        ellmer::type_object,
        c(list(.description = desc, .required = FALSE), fields)
      ))
    }
    # Unnamed list. An array of objects (elements are themselves lists) is
    # polymorphic -> JSON string the model fills, re-parsed in the tool. A scalar
    # list -> a typed array.
    if (length(val) && is.list(val[[1L]])) {
      ex <- tryCatch(as.character(jsonlite::toJSON(val, auto_unbox = TRUE)),
                     error = function(e) NULL)
      d <- if (!is.null(ex)) paste0(desc, " -- a JSON array string, e.g. ", ex) else
        paste0(desc, " (a JSON array string)")
      return(ellmer::type_string(d, required = FALSE))
    }
    if (length(val)) {
      return(ellmer::type_array(ellmer_type_from_value(val[[1L]], "", nested = TRUE),
                                description = desc, required = FALSE))
    }
    return(ellmer::type_string(paste0(desc, " (a JSON array string)"), required = FALSE))
  }
  n <- length(val)
  if (is.logical(val) && n == 1L) return(ellmer::type_boolean(desc, required = FALSE))
  if (is.integer(val) && n == 1L) return(ellmer::type_integer(desc, required = FALSE))
  if (is.numeric(val) && n == 1L) return(ellmer::type_number(desc, required = FALSE))
  if (is.character(val) && n == 1L) return(ellmer::type_string(desc, required = FALSE))
  if (is.character(val) && n > 1L) return(ellmer::type_enum(unname(val), desc, required = FALSE))
  if (is.numeric(val) && n > 1L) {
    return(ellmer::type_array(ellmer::type_number(), description = desc, required = FALSE))
  }
  ellmer::type_string(desc, required = FALSE)
}

#' Build a function whose formals ARE `arg_names` (so ellmer can pass native
#' structured arguments), collecting the supplied (non-NULL) ones into a named
#' list and handing them to `handler`.
#' @noRd
build_arg_collector <- function(arg_names, handler) {
  collector <- function() {
    env <- environment()
    vals <- mget(arg_names, envir = env, ifnotfound = list(NULL))
    vals <- vals[!vapply(vals, is.null, logical(1))]
    handler(vals)
  }
  formals(collector) <- stats::setNames(
    rep(list(NULL), length(arg_names)), arg_names
  )
  collector
}

#' Re-parse JSON-string leaves back into R lists (for the polymorphic-array
#' fields typed as strings above). Conservative: only strings that start with
#' `[`/`{` and parse cleanly are converted.
#' @noRd
reparse_json_strings <- function(x) {
  if (is.list(x)) {
    return(lapply(x, reparse_json_strings))
  }
  if (is.character(x) && length(x) == 1L) {
    s <- trimws(x)
    if (nzchar(s) && substr(s, 1, 1) %in% c("[", "{")) {
      parsed <- tryCatch(jsonlite::fromJSON(s, simplifyVector = FALSE),
                         error = function(e) NULL)
      if (!is.null(parsed)) return(parsed)
    }
  }
  x
}
