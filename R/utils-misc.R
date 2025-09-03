style_code <- function(code) {
  paste0(styler::style_text(code), collapse = "\n")
}

last <- function(x) x[[length(x)]]

split_newline <- function(...) {
  strsplit(paste0(..., collapse = ""), "\n", fixed = TRUE)[[1L]]
}

log_wrap <- function(..., level = "info") {
  for (tok in strwrap(split_newline(...), width = 0.7 * getOption("width"))) {
    write_log(tok, level = level)
  }
}

log_asis <- function(..., level = "info") {
  for (tok in split_newline(...)) {
    write_log(tok, level = level)
  }
}

has_length <- function(x) length(x) > 0
