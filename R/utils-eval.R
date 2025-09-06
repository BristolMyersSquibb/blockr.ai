eval_code <- function(code, data) {
  eval(
    parse(text = code),
    envir = list2env(data, parent = baseenv())
  )
}

try_eval_code <- function(x, code, data) {
  try(
    check_result(
      eval_code(code, data),
      ptype = result_ptype(x),
      check_fun = blockr_option("result_check_fun", inherits_base_class)
    ),
    silent = TRUE
  )
}

extract_try_error <- function(x) {

  stopifnot(inherits(x, "try-error"))

  if (is.null(attr(x, "condition"))) {
    unclass(x)
  } else {
    conditionMessage(attr(x, "condition"))
  }
}

#' Tools for evaluating and checking code
#'
#' LLM-produced code is evaluated and the result is checked w.r.t. block-
#' specific expectations.
#'
#' @param x Object to be checked
#' @param ptype A prototype object
#'
#' @export
inherits_base_class <- function(x, ptype) {

  expected <- last(class(ptype))

  if (inherits(x, expected)) {
    return(TRUE)
  }

  paste0(
    "Instead of inheriting from `", expected, "`, the class vector is ",
    paste_enum(class(x))
  )
}

#' @rdname inherits_base_class
#' @export
result_ptype <- function(x) {
  UseMethod("result_ptype")
}

#' @param check_fun A function that either returns `TRUE` or a string
#' indicating the type of check failure
#'
#' @rdname inherits_base_class
#' @export
check_result <- function(x, ptype, check_fun = inherits_base_class) {
  UseMethod("check_result")
}

#' @rdname inherits_base_class
#' @export
check_result.default <- function(x, ptype, check_fun = inherits_base_class) {

  chk <- check_fun(x, ptype)

  if (isTRUE(chk)) {
    return(x)
  }

  stop(chk)
}

#' @rdname inherits_base_class
#' @export
check_result.ggplot <- function(x, ptype, check_fun = inherits_base_class) {
  # plots might not fail at definition time but only when printing.
  # We trigger the failure early with ggplotGrob()
  suppressMessages(ggplot2::ggplotGrob(x))
  NextMethod()
}
