style_code <- function(code) {
  paste0(styler::style_text(code), collapse = "\n")
}

last <- function(x) x[[length(x)]]

has_length <- function(x) length(x) > 0
