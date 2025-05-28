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
    border: 1px solid var(--bs-light-border-subtle);
    border-radius: 8px;
    padding: 15px;
  }
  .llm-response {
    margin-top: 15px;
  }
  .llm-details {
    margin-top: 10px;
    border: none;
  }
  [data-bs-theme=dark] .llm-details summary {
    background: var(--bs-light-bg-subtle);
  }
  [data-bs-theme=light] .llm-details summary {
    background: var(--bs-dark-bg-subtle);
  }
  .llm-details summary {
    padding: 8px;
    cursor: pointer;
    margin-bottom: 10px;
  }
  .llm-progress {
    margin-top: 10px;
    display: none;
  }
  .llm-progress.active {
    display: block;
  }"
}
