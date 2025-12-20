# Prompt Explorer
#
# Interactive script to test prompts and find failure patterns
#
# Usage:
#   source("dev/experiments/prompt-explorer.R")
#   test_prompt(prompt, data)
#   test_prompt_with_skill(prompt, data, skill_text)

source("dev/harness.R")

# Simple test function - runs one prompt, shows result
test_prompt <- function(prompt, data, model = "gpt-4o-mini") {

  config <- list(
    chat_fn = function() ellmer::chat_openai(model = model)
  )

  cat("\n")
  cat(strrep("=", 70), "\n")
  cat("TESTING PROMPT (no skills)\n")
  cat(strrep("=", 70), "\n")
  cat("\nPrompt:\n", prompt, "\n")

  res <- run_llm_ellmer_with_preview_and_validation(
    prompt = prompt,
    data = data,
    config = config
  )

  cat("\n")
  cat(strrep("=", 70), "\n")
  cat("RESULT\n")
  cat(strrep("=", 70), "\n")

  if (!is.null(res$code)) {
    cat("\nGenerated code:\n")
    cat(res$code, "\n")
  }

  if (is.data.frame(res$result)) {
    cat("\nResult (", nrow(res$result), " rows x ", ncol(res$result), " cols):\n", sep = "")
    print(res$result)
    cat("\nSUCCESS\n")
  } else {
    cat("\nFAILED - no valid data.frame result\n")
    if (!is.null(res$error)) {
      cat("Error:", res$error, "\n")
    }
  }

  invisible(res)
}


# Test with a skill injected
test_prompt_with_skill <- function(prompt, data, skill_text, model = "gpt-4o-mini") {

  config <- list(
    chat_fn = function() ellmer::chat_openai(model = model)
  )

  cat("\n")
  cat(strrep("=", 70), "\n")
  cat("TESTING PROMPT (WITH SKILL)\n")
  cat(strrep("=", 70), "\n")
  cat("\nPrompt:\n", prompt, "\n")
  cat("\nSkill:\n", substr(skill_text, 1, 200), "...\n")

  # Manually inject skill into system prompt
  res <- run_llm_with_custom_system(
    prompt = prompt,
    data = data,
    config = config,
    skill_text = skill_text
  )

  cat("\n")
  cat(strrep("=", 70), "\n")
  cat("RESULT\n")
  cat(strrep("=", 70), "\n")

  if (!is.null(res$code)) {
    cat("\nGenerated code:\n")
    cat(res$code, "\n")
  }

  if (is.data.frame(res$result)) {
    cat("\nResult (", nrow(res$result), " rows x ", ncol(res$result), " cols):\n", sep = "")
    print(res$result)
    cat("\nSUCCESS\n")
  } else {
    cat("\nFAILED - no valid data.frame result\n")
  }

  invisible(res)
}


# Helper to run with custom system prompt addition
run_llm_with_custom_system <- function(prompt, data, config, skill_text,
                                        max_validation_retries = 3) {

  start <- Sys.time()

  if (is.data.frame(data)) {
    datasets <- list(data = data)
  } else {
    datasets <- data
  }

  proxy <- structure(
    list(messages = list(), code = character()),
    class = c("llm_transform_block_proxy", "llm_block_proxy")
  )

  tools <- list(
    new_eval_tool_with_result(proxy, datasets),
    new_data_tool(proxy, datasets)
  )

  sys_prompt <- system_prompt(proxy, datasets, tools)

  # Inject skill
  sys_prompt <- paste0(
    sys_prompt,
    "\n\n# SKILL GUIDANCE\n\n",
    skill_text
  )

  client <- config$chat_fn()
  client$set_system_prompt(sys_prompt)
  client$set_tools(lapply(tools, get_tool))

  error <- NULL
  response <- tryCatch(
    client$chat(prompt),
    error = function(e) {
      error <<- conditionMessage(e)
      NULL
    }
  )

  extract_result <- function() {
    eval_tool_obj <- tools[[1]]
    tool_fn <- get_tool(eval_tool_obj)
    tool_env <- environment(tool_fn)
    code <- get0("current_code", envir = tool_env, inherits = FALSE)

    result <- NULL
    if (!is.null(code) && nchar(code) > 0) {
      result <- tryCatch(
        eval(parse(text = code), envir = eval_env(datasets)),
        error = function(e) NULL
      )
    }
    list(code = code, result = result)
  }

  extracted <- extract_result()
  code <- extracted$code
  result <- extracted$result

  # Validation loop
  validation_attempt <- 0
  while (!is.data.frame(result) && validation_attempt < max_validation_retries) {
    validation_attempt <- validation_attempt + 1

    retry_msg <- if (is.null(code) || nchar(code) == 0) {
      "Please call eval_tool with your R code to complete the task."
    } else {
      "The code did not produce a valid data.frame. Please fix and call eval_tool again."
    }

    response <- tryCatch(
      client$chat(retry_msg),
      error = function(e) {
        error <<- conditionMessage(e)
        NULL
      }
    )

    extracted <- extract_result()
    code <- extracted$code
    result <- extracted$result
  }

  duration <- as.numeric(difftime(Sys.time(), start, units = "secs"))

  list(
    code = code,
    result = result,
    duration = duration,
    error = error,
    validation_retries = validation_attempt
  )
}


# --- Test data sets ---

# Simple data for testing
TEST_DATA_SIMPLE <- data.frame(
  category = c("A", "A", "B", "B"),
  value = c(10, 20, 30, 40)
)

# Wide data with pattern columns
TEST_DATA_WIDE <- data.frame(
  category = c("A", "A", "B", "B", "C", "C"),
  subcategory = c("x", "y", "x", "y", "x", "y"),
  value_jan = c(10, 20, 30, 40, 50, 60),
  value_feb = c(15, 25, 35, 45, 55, 65),
  value_mar = c(12, 22, 32, 42, 52, 62),
  count_jan = c(1, 2, 3, 4, 5, 6),
  count_feb = c(2, 3, 4, 5, 6, 7),
  stringsAsFactors = FALSE
)

# Numeric pivot data
TEST_DATA_NUMERIC_COLS <- data.frame(
  store = rep(c("Store1", "Store2"), each = 4),
  quarter = rep(1:4, times = 2),
  sales = c(100, 120, 110, 130, 80, 90, 85, 95)
)


# --- Example prompts to test ---

# These are prompts that MIGHT fail - test them!

PROMPT_ACROSS_TRAP <- '
Using data, sum all columns that start with "value_" for each category.
Result should have: category, value_jan, value_feb, value_mar (each summed).
'

PROMPT_PIVOT_NUMERIC <- '
Using data, pivot so that each quarter becomes a column.
Rows: store
Columns: one column per quarter (1, 2, 3, 4) showing sales
Add a total column that sums all quarters.
'

PROMPT_WRONG_PACKAGE <- '
Using data, pivot the data wider with category as rows and subcategory as columns.
Values should be the sum of value_jan.
Use values_fill = 0 for missing values.
'


# --- Skills to test ---

SKILL_ACROSS <- '
# Across Pattern for Multiple Columns

When applying a function to multiple columns selected by pattern, use dplyr::across():

CORRECT:
  data |> dplyr::summarize(dplyr::across(starts_with("value_"), sum))

WRONG:
  data |> dplyr::summarize(sum(starts_with("value_")))  # Error!

Pattern:
  dplyr::summarize(dplyr::across(SELECTION, FUNCTION))

Where SELECTION is starts_with(), ends_with(), etc.
And FUNCTION is sum, mean, max (without parentheses)
'

SKILL_PIVOT <- '
# Pivot Table Skill

1. Use tidyr::pivot_wider() - NOT dplyr::pivot_wider (does not exist)

2. Numeric column names need backticks:
   After pivoting on quarter (1,2,3,4), columns are `1`, `2`, `3`, `4`

   WRONG: mutate(total = 1 + 2 + 3 + 4)  # adds numbers!
   CORRECT: mutate(total = `1` + `2` + `3` + `4`)

3. Or use names_prefix to avoid backticks:
   tidyr::pivot_wider(names_from = quarter, values_from = sales, names_prefix = "q")
   # Creates q1, q2, q3, q4 - no backticks needed
'


cat("\n")
cat("Prompt Explorer loaded!\n")
cat("\n")
cat("Test data available:\n")
cat("  TEST_DATA_SIMPLE - basic category/value\n")
cat("  TEST_DATA_WIDE - multiple value_* columns\n")
cat("  TEST_DATA_NUMERIC_COLS - store/quarter/sales\n")
cat("\n")
cat("Example prompts:\n")
cat("  PROMPT_ACROSS_TRAP\n")
cat("  PROMPT_PIVOT_NUMERIC\n")
cat("  PROMPT_WRONG_PACKAGE\n")
cat("\n")
cat("Skills:\n")
cat("  SKILL_ACROSS\n")
cat("  SKILL_PIVOT\n")
cat("\n")
cat("Usage:\n")
cat("  test_prompt(PROMPT_ACROSS_TRAP, list(data = TEST_DATA_WIDE))\n")
cat("  test_prompt_with_skill(PROMPT_ACROSS_TRAP, list(data = TEST_DATA_WIDE), SKILL_ACROSS)\n")
cat("\n")
