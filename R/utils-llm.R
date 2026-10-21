#' Create chat client
#' @param model Model name (default from blockr_option("ai_model"))
#' @return An ellmer chat client
#' @noRd
llm_client <- function(model = blockr.core::blockr_option("ai_model", "gpt-4o-mini")) {
  message("[discover] client: ", model)
  chat_fns <- getOption("blockr.chat_function")
  if (!is.null(chat_fns) && model %in% names(chat_fns)) {
    return(chat_fns[[model]]())
  }
  ellmer::chat_openai(model = model)
}
