#' Build user prompt for block argument discovery (template-based)
#'
#' Reads a Markdown template from `inst/prompts/user_prompt.md` and interpolates it with
#' [glue::glue()]. The template uses `{? cond: content}` / `{! cond: content}`
#'
#' @param prompt
#' @param data
#' @param current_state
#' @return Character string with user prompt
#' @noRd
build_user_prompt <- function(user_input, data, current_state) {
  data_preview_formatted <- data_preview(data)
  current_state_formatted <- format_current_state(current_state)
  user_prompt <- interpolate_template(
    template = read_template("user_prompt.md"),
    user_input = user_input,
    data_preview_formatted = data_preview_formatted,
    current_state_formatted = current_state_formatted
  )
  user_prompt
}
