# Shared tool contract for the tool-driven harnesses.
#
# The ellmer harness builds these two tools; the contract is deliberately
# MCP) drive the same two tools. Building them in one place keeps the contract
# identical across harnesses, which is what makes the A/B comparison
# apples-to-apples.

#' Build the data-exploration and validate-config tools for a block + data.
#'
#' @param block A block object.
#' @param data Input data (or NULL).
#' @param validate Validation function; when NULL, the standalone validator is
#'   used (fresh block + testServer). In a live board this is the
#'   reactiveVal-writing validator, so the last successful call is the apply.
#' @return A list with `data` (an `llm_tool` or NULL when there is no input
#'   data), `validate` (the validate-config `llm_tool`), and `validate_fn` (the
#'   resolved validate function).
#' @noRd
build_harness_tools <- function(block, data, validate = NULL) {
  if (is.null(validate)) {
    validate <- standalone_validator_internal(attr(block, "ctor"), data)
  }

  datasets <- normalize_datasets(data)
  data_tool <- if (length(datasets) > 0L) {
    new_data_tool(
      NULL, datasets,
      max_probes = blockr.core::blockr_option("max_data_probes", 8L)
    )
  } else {
    NULL
  }

  # Skills targeting this block, plus the read tools for them (empty when no
  # library is configured or none match). Built here, in the shared harness
  # contract, so the other consumer harnesses pick them up by construction.
  skills <- skills_for_block(block)
  skill_tools <- new_skill_tools(skills)

  list(
    data = data_tool,
    validate = new_validate_tool(validate, block, data = data),
    validate_fn = validate,
    skills = skills,
    skill_tools = skill_tools
  )
}
