new_eval_tool <- function(x, datasets,
                          max_retries = blockr_option("max_retries", 3L),
                          ...) {

  invocation_count <- 0

  execute_r_code <- function(code, explanation = "") {

    invocation_count <<- invocation_count + 1

    log_info(
      "Executing R code (attempt ", invocation_count, "/", max_retries,
      "):\n", code
    )

    if (invocation_count > max_retries) {

      log_warn("Maximum attempts (", max_retries, ") exceeded")

      invocation_count <<- 0

      ellmer::tool_reject(
        paste0(
          "Maximum number of attempts (", max_retries, ") exceeded. ",
          "Unable to execute code successfully after multiple tries."
        )
      )
    }

    result <- try_eval_code(x, code, datasets)

    if (inherits(result, "try-error")) {

      error_msg <- extract_try_error(result)

      log_warn(
        "Code execution failed on attempt ", invocation_count, ":\n",
        error_msg
      )

      if (invocation_count < max_retries) {

        return(
          paste0(
            "Error on attempt ", invocation_count, "/", max_retries, ": ",
            error_msg, "\n\nPlease analyze this error and provide corrected ",
            "code. Call this tool again with the fixed code."
          )
        )

      } else {

        log_warn("Final attempt failed. Cannot retry further.")

        invocation_count <<- 0

        ellmer::tool_reject(
          paste0(
            "Final error after ", max_retries, " attempts: ", error_msg,
            "\n\nUnable to execute code successfully. Please give up trying, ",
            "before receiving new user instructions."
          )
        )
      }
    }

    log_debug("Code execution successful on attempt ", invocation_count)

    invocation_count <<- 0

    paste0(
      "Code executed successfully on attempt ", invocation_count, "/",
      max_retries, ". Your task has been completed successfully. Please ",
      "return the following code chunk to the user alongside an explanation ",
      "of what it does:\n\n```r\n", code, "\n```."
    )
  }

  new_llm_tool(
    execute_r_code,
    description = paste0(
      "Execute R code against the provided datasets. If code fails, you ",
      "can call this tool again with corrected code. Maximum ", max_retries,
      " attempts allowed before the tool rejects further calls."
    ),
    name = "eval_tool",
    prompt = paste(
      "Before returning any code and accompanying explanations to the user,",
      "you must check your code using the \"eval_tool\" to make sure the code",
      "runs without errors. This is not optional. It is critical that you",
      "verify your result using the \"eval_tool\"."
    ),
    arguments = list(
      code = ellmer::type_string("R code to execute"),
      explanation = ellmer::type_string("Explanation of what the code does")
    )
  )
}
