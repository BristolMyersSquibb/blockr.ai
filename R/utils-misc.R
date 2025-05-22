# Define response types
type_response <- function() {
  type_object(
    explanation = type_string("Explanation of the analysis approach"),
    code = type_string("R code to perform the analysis")
  )
}

return_result_if_success <- function(result, code) {
  warning("Expression status: ", result$success, "\nFinal code:\n", code)
  if (isTRUE(result$success)) {
    result$result  # Return the cached result
  } else {
    data.frame()  # Return empty dataframe on error
  }
}

get_model <- function() {
  getOption("blockr.ai.model", "gpt-4o")
}

get_model_family <- function() {
  # commented out inconsistent apis
  supported <- c(
    # "azure",
    "bedrock",
    "claude",
    # "cortex",
    # "databricks",
    "gemini",
    "github",
    "groq",
    "ollama",
    "openai",
    "perplexity"
    # "vllm"
  )
  model_family <- getOption("blockr.ai.model_family", "openai")
  rlang::arg_match(model_family, supported)
}

chat_dispatch <- function(system_prompt, ..., turns = NULL, model = get_model(), model_family = get_model_family()) {
  switch(
    model_family,
    bedrock = ellmer::chat_bedrock(system_prompt, turns, model = model, ...),
    claude = ellmer::chat_claude(system_prompt, turns, model = model, ...),
    gemini = ellmer::chat_gemini(system_prompt, turns, model = model, ...),
    github = ellmer::chat_github(system_prompt, turns, model = model, ...),
    groq = ellmer::chat_groq(system_prompt, turns, model = model, ...),
    ollama = ellmer::chat_ollama(system_prompt, turns, model = model, ...),
    openai = ellmer::chat_openai(system_prompt, turns, model = model, ...),
    perplexity = ellmer::chat_perplexity(system_prompt, turns, model = model, ...),
  )
}

eval_code <- function(code, data) {
  eval(
    parse(text = code),
    envir = list2env(data, parent = baseenv())
  )
}

try_eval_code <- function(...) {
  tryCatch(
    eval_code(...),
    error = function(e) {
      structure(conditionMessage(e), class = c(class(e), "try_error"))
    }
  )
}

style_code <- function(code) {
  paste0(styler::style_text(code), collapse = "\n")
}
