style_code <- function(code) {

  res <- tryCatch(
    styler::style_text(code),
    warning = function(w) code
  )

  paste0(res, collapse = "\n")
}

last <- function(x) x[[length(x)]]

md_text <- function(x) {
  structure(paste0(x, collapse = ""), class = "md_text")
}

code_expr <- function(code) {
  str2expression(coal(code, ""))
}
