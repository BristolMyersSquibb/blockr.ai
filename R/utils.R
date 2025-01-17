#' @noRd
#' @param x list of datasets
name_unnamed_datasets <- function(x) {
  names(x) <- if_else(
    names2(x) == "",
    paste0("data", seq_along(x)),
    names2(x)
  )
  x
}

