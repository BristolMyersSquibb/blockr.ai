#' Block-specific UI
#'
#' UI customization at block level.
#'
#' @param x LLM block proxy object
#'
#' @return A string.
#'
#' @export
llm_block_css <- function(x) {
	UseMethod("llm_block_css")
}

#' @rdname llm_block_css
#' @export
llm_block_css.llm_block_proxy <- function(x) {
  "
  .llm-block {
    border: 1px solid #e0e0e0;
    border-radius: 8px;
    padding: 15px;
    background: #ffffff;
  }
  .llm-response {
    margin-top: 15px;
  }
  .llm-details {
    border: 1px solid #e0e0e0;
    border-radius: 4px;
    margin-top: 10px;
    border: none;
  }
  .llm-details summary {
    padding: 8px;
    background: #f8f9fa;
    cursor: pointer;
  }
  .llm-details summary:hover {
    background: #e9ecef;
  }
  .llm-code {
    background-color: #f5f5f5;
    padding: 10px;
    border-radius: 4px;
    font-family: monospace;
  }
  .llm-progress {
    margin-top: 10px;
    display: none;
  }
  .llm-progress.active {
    display: block;
  }"
}

#' @rdname llm_block_css
#' @export
llm_block_css.llm_plot_block_proxy <- function(x) {

  extra <- "
  .llm-plot {
    border: 1px solid #e0e0e0;
    border-radius: 4px;
    margin-top: 10px;
  }"

  paste0(NextMethod(), extra)
}
