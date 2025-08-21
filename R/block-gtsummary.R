#' @rdname new_llm_block
#' @export
new_llm_gtsummary_block <- function(...) {
  new_llm_block("llm_gtsummary_block", ...)
}

#' @export
block_ui.llm_gtsummary_block <- function(id, x, ...) {
  tagList(
    gt::gt_output(NS(id, "result"))
  )
}

#' @export
block_output.llm_gtsummary_block <- function(x, result, session) {

  if (inherits(result, "gtsummary")) {
    result <- gtsummary::as_gt(result)
  }

  gt::render_gt(gt_theme(result, session))
}


#' @export
result_ptype.llm_gtsummary_block_proxy <- function(x) {
  gtsummary::tbl_summary(data.frame(a = 1))
}
