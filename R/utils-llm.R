style_code <- function(code) {

  res <- tryCatch(
    styler::style_text(code),
    warning = function(w) code
  )

  paste0(res, collapse = "\n")
}

last <- function(x) x[[length(x)]]

md_text <- function(x) {
  structure(paste0(x, collapse = ""), class = "md_text")
}

code_expr <- function(code) {
  str2expression(coal(code, ""))
}


#' Create a chat client for the specified model
#'
#' Creates an ellmer chat client based on the model name. Automatically
#' detects OpenWebUI models (containing ":") and uses the appropriate
#' API endpoint.
#'
#' @param model Model name (e.g., "gpt-4o-mini", "gpt-oss:20b", "gemma3:12b")
#' @return An ellmer chat client
#' @noRd
create_chat_client <- function(model) {

  # OpenWebUI models contain ":" (e.g., "gpt-oss:20b", "gemma3:12b")
  # Standard OpenAI models don't (e.g., "gpt-4o-mini", "gpt-4o")
  is_openwebui <- grepl(":", model)

  if (is_openwebui) {
    ellmer::chat_openai_compatible(
      base_url = "https://ai.cynkra.com/api/v1",
      credentials = function() Sys.getenv("OPENWEBUI_API_KEY"),
      model = model
    )
  } else {
    ellmer::chat_openai(model = model)
  }
}
