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
  gt::render_gt(gt_theme(result, session))
}

#' @export
result_ptype.llm_gt_block_proxy <- function(x) {
  gt::gt(data.frame())
}

#' @rdname system_prompt
#' @export
system_prompt.llm_gt_block_proxy <- function(x, datasets, ...) {

  paste0(
    NextMethod(),
    "\n\n",
    "Your task is to produce code to generate a table using the gt package.\n",
    "Example of good code you might write:\n",
    "gt::gt(data) |>\n",
    "  gt::tab_header(\"",
    "    title = \"Some title\",",
    "    subtitle = \"Some subtitle\"",
    "  )\n\n",
    "Important: Your code must always return a gt object as the last ",
    "expression.\n"
  )
}

gt_theme <- function(obj, session) {

  if (isFALSE(coal(get_board_option_or_null("thematic"), FALSE))) {
    return(obj)
  }

  theme <- bslib::bs_current_theme(session)

  if (!bslib::is_bs_theme(theme)) {
    return(obj)
  }

  is_dm <- identical(
    coal(get_board_option_or_null("dark_mode"), "light"),
    "dark"
  )

  if ("3" %in% bslib::theme_version(theme)) {

    vars <- c(
      table.background.color = "body-bg",
      table.font.color = "text-color"
    )

  } else if (is_dm) {

    vars <- c(
      table.background.color = "body-bg-dark",
      table.font.color = "body-color-dark"
    )

  } else {

    vars <- c(
      table.background.color = "body-bg",
      table.font.color = "body-color"
    )
  }

  vars <- stats::setNames(
    as.list(bslib::bs_get_variables(theme, unname(vars))),
    names(vars)
  )

  do.call(gt::tab_options, c(list(obj), vars))
}
