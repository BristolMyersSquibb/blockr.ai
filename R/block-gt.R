#' @rdname new_llm_block
#' @export
new_llm_gt_block <- function(...) {
  new_llm_block("llm_gt_block", ...)
}

#' @export
block_ui.llm_gt_block <- function(id, x, ...) {
  tagList(
    gt::gt_output(NS(id, "result"))
  )
}

#' @export
block_output.llm_gt_block <- function(x, result, session) {
  gt::render_gt(result)
}

#' @export
result_ptype.llm_gt_block_proxy <- function(x) {
  gt::gt(data.frame())
}
