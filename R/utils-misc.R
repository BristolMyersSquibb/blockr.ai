type_response <- function() {
  type_object(
    explanation = type_string("Explanation of the analysis approach"),
    code = type_string("R code to perform the analysis")
  )
}

chat_dispatch <- function(system_prompt, ..., turns = NULL,
                          model = blockr_option("chat_model", "gpt-4o"),
                          vendor = blockr_option("chat_vendor", "openai")) {

  chat <- switch(
    vendor,
    bedrock = ellmer::chat_bedrock,
    claude = ellmer::chat_claude,
    gemini = ellmer::chat_gemini,
    github = ellmer::chat_github,
    groq = ellmer::chat_groq,
    ollama = ellmer::chat_ollama,
    openai = ellmer::chat_openai,
    perplexity = ellmer::chat_perplexity,
    stop("Unknown LLM vendor ", vendor, ".")
  )

  chat(system_prompt, turns, model = model, ...)
}

eval_code <- function(code, data) {
  eval(
    parse(text = code),
    envir = list2env(data, parent = baseenv())
  )
}

try_eval_code <- function(...) {
  tryCatch(
    {
      res <- eval_code(...)

      # plots might not fail at definition time but only when printing.
      # We trigger the failure early with ggplotGrob()
      if (ggplot2::is.ggplot(res)) {
        suppressMessages(ggplot2::ggplotGrob(res))
      }

      res
    },
    error = function(e) {
      structure(conditionMessage(e), class = "try-error")
    }
  )
}

style_code <- function(code) {
  paste0(styler::style_text(code), collapse = "\n")
}

last <- function(x) x[[length(x)]]

split_newline <- function(...) {
  strsplit(paste0(..., collapse = ""), "\n", fixed = TRUE)[[1L]]
}

log_wrap <- function(..., level = "info") {
  for (tok in strwrap(split_newline(...), width = 0.7 * getOption("width"))) {
    write_log(tok, level = level)
  }
}

log_asis <- function(..., level = "info") {
  for (tok in split_newline(...)) {
    write_log(tok, level = level)
  }
}
