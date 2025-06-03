#' @rdname new_llm_block
#' @export
new_llm_transform_block <- function(...) {
  new_llm_block(c("llm_transform_block", "transform_block"), ...)
}

#' @export
result_ptype.llm_transform_block_proxy <- function(x) {
  data.frame()
}
