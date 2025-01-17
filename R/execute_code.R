# Function to execute code with retry logic
execute_code <- function(code, datasets, max_retries) {
  for(i in 1:max_retries) {
    tryCatch({
      # Create environment with datasets
      env <- list2env(datasets)
      # Execute code
      result <- eval(parse(text = code), envir = env)
      # If we get here, code executed successfully
      warning("Code execution successful:\n", code)
      return(list(success = TRUE, code = code, result = result))
    }, error = function(e) {
      if(i == max_retries) {
        warning("Code execution failed after ", max_retries, " attempts:\n",
                "Last code:\n", code, "\nError: ", e$message)
        return(list(success = FALSE, error = e$message))
      }
      warning("Code execution attempt ", i, " failed:\n",
              "Code:\n", code, "\nError: ", e$message)
      # Query LLM with error
      response <- query_llm(current_question(), metadata(), e$message)
      code <- response$code
      current_code(code)
    })
  }
  # If we get here, max retries reached
  warning("Maximum retries reached. Last code:\n", code)
  return(list(success = FALSE, error = "Maximum retries reached"))
}
