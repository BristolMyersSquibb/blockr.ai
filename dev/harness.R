# LLM Evaluation Harness
#
# Simple functions to run LLM tool call chains outside of Shiny
# and inspect the results.
#
# Usage:
#   source("dev/harness.R")
#   res <- run_llm_ellmer(prompt, data, config)
#   summarize_run(res)


# --- Run function (ellmer direct) ---
#
# Runs a prompt through ellmer with blockr.ai tools, outside of Shiny.
# Verbose output shows progress.
#
run_llm_ellmer <- function(prompt, data, config) {

 cat("\n")
 cat(strrep("=", 60), "\n")
 cat("RUN: ellmer direct\n")
 cat(strrep("=", 60), "\n\n")

 start <- Sys.time()

 # Wrap data in named list if not already
 if (is.data.frame(data)) {
   datasets <- list(data = data)
 } else {
   datasets <- data
 }

 # Create proxy object (mimics blockr.ai block proxy)
 cat("Creating proxy...\n")
 proxy <- structure(
   list(messages = list(), code = character()),
   class = c("llm_transform_block_proxy", "llm_block_proxy")
 )

 # Create tools
 cat("Creating tools...\n")
 tools <- list(
   new_eval_tool(proxy, datasets),
   new_data_tool(proxy, datasets)
 )
 cat("  Tools:", paste(sapply(tools, function(t) t$tool@name), collapse = ", "), "\n")

 # Build system prompt
 cat("Building system prompt...\n
")
 sys_prompt <- system_prompt(proxy, datasets, tools)
 cat("  Length:", nchar(sys_prompt), "chars\n")

 # Create client
 cat("Creating LLM client...\n")
 client <- config$chat_fn()

 # Configure client
 client$set_system_prompt(sys_prompt)
 client$set_tools(lapply(tools, get_tool))

 # Call LLM (synchronous)
 cat("\n")
 cat(strrep("-", 60), "\n")
 cat("Calling LLM (synchronous)...\n")
 cat(strrep("-", 60), "\n\n")

 error <- NULL
 response <- tryCatch(
   client$chat(prompt),
   error = function(e) {
     error <<- conditionMessage(e)
     NULL
   }
 )

 duration <- as.numeric(difftime(Sys.time(), start, units = "secs"))

 cat("\n")
 cat(strrep("-", 60), "\n")
 cat("LLM finished in", round(duration, 1), "seconds\n")
 cat(strrep("-", 60), "\n")

 # Extract code from eval_tool
 cat("\nExtracting code from eval_tool...\n")
 eval_tool_obj <- tools[[1]]
 tool_fn <- get_tool(eval_tool_obj)
 tool_env <- environment(tool_fn)
 code <- get0("current_code", envir = tool_env, inherits = FALSE)

 if (!is.null(code) && nchar(code) > 0) {
   cat("  Code captured successfully\n")
 } else {
   cat("  No code captured (LLM may not have validated successfully)\n")
   code <- NULL
 }

 # Evaluate code to get result
 result <- NULL
 if (!is.null(code)) {
   cat("Evaluating code...\n")
   result <- tryCatch(
     eval(parse(text = code), envir = list2env(datasets, parent = baseenv())),
     error = function(e) {
       cat("  Evaluation error:", conditionMessage(e), "\n")
       structure(conditionMessage(e), class = "eval_error")
     }
   )
 }

 # Return structured result
 list(
   code = code,
   result = result,
   response = response,
   turns = client$get_turns(),
   duration_secs = duration,
   error = error,
   config = config,
   prompt = prompt
 )
}


# --- Summary function ---
#
# Pretty-prints key metrics from a run.
#
summarize_run <- function(run) {

 cat("\n")
 cat(strrep("=", 60), "\n")
 cat("SUMMARY\n")
 cat(strrep("=", 60), "\n\n")

 # Basic metrics
 cat("Duration:
     ", round(run$duration_secs, 1), " sec\n", sep = "")
 cat("Has code:
     ", !is.null(run$code) && nchar(run$code) > 0, "\n", sep = "")

 # Result info
 if (is.null(run$result)) {
   cat("Result:
     ", "NULL\n", sep = "")
 } else if (inherits(run$result, "eval_error")) {
   cat("Result:
     ", "ERROR - ", run$result, "\n", sep = "")
 } else if (is.data.frame(run$result)) {
   cat("Result:
     ", "data.frame [", nrow(run$result), " x ", ncol(run$result), "]\n", sep = "")
   cat("Columns:
     ", paste(names(run$result), collapse = ", "), "\n", sep = "")
 } else {
   cat("Result:
     ", class(run$result)[1], "\n", sep = "")
 }

 # Tool calls
 tool_calls <- count_tool_calls(run$turns)
 cat("Tool calls:
     ", tool_calls$total, " total\n", sep = "")
 if (tool_calls$total > 0) {
   for (nm in names(tool_calls$by_tool)) {
     cat("
             ", nm, ": ", tool_calls$by_tool[[nm]], "\n", sep = "")
   }
 }

 # Error
 if (!is.null(run$error)) {
   cat("Error:
     ", run$error, "\n", sep = "")
 }

 # Code
 if (!is.null(run$code) && nchar(run$code) > 0) {
   cat("\n")
   cat(strrep("-", 60), "\n")
   cat("CODE\n")
   cat(strrep("-", 60), "\n")
   cat(run$code, "\n")
 }

 # LLM response
 if (!is.null(run$response)) {
   cat("\n")
   cat(strrep("-", 60), "\n")
   cat("LLM RESPONSE\n")
   cat(strrep("-", 60), "\n")
   cat(substr(run$response, 1, 500))
   if (nchar(run$response) > 500) cat("...\n[truncated]")
   cat("\n")
 }

 cat("\n")
 cat(strrep("=", 60), "\n")

 invisible(run)
}


# --- Inspect function ---
#
# Shows the full process: prompt -> tool calls -> iterations -> result
#
inspect_run <- function(run) {

 cat("\n")
 cat(strrep("=", 70), "\n")
 cat("INSPECTION: Full Process Overview\n")
 cat(strrep("=", 70), "\n")

 # 1. Initial prompt
 cat("\n")
 cat(strrep("-", 70), "\n")
 cat("1. INITIAL PROMPT\n")
 cat(strrep("-", 70), "\n")
 cat(run$prompt, "\n")

 # 2. Tool call sequence
 cat("\n")
 cat(strrep("-", 70), "\n")
 cat("2. TOOL CALL SEQUENCE\n")
 cat(strrep("-", 70), "\n")

 tool_call_num <- 0
 for (i in seq_along(run$turns)) {
   turn <- run$turns[[i]]

   for (content in turn@contents) {
     cls <- class(content)[1]

     # Tool request (LLM calling a tool)
     if (grepl("ToolRequest", cls)) {
       tool_call_num <- tool_call_num + 1
       cat("\n")
       cat(">>> Tool Call #", tool_call_num, ": ", content@name, "\n", sep = "")

       if (content@name == "eval_tool") {
         code <- content@arguments$code
         cat("\nCode submitted:\n")
         cat(format_code_block(code), "\n")
       } else if (content@name == "data_tool") {
         code <- content@arguments$code
         cat("\nData exploration code:\n")
         cat(format_code_block(code), "\n")
       }
     }

     # Tool result (response from tool)
     if (grepl("ToolResult", cls)) {
       result_text <- paste(content@value, collapse = " ")

       if (grepl("Error", result_text)) {
         cat("\n<<< RESULT: ERROR\n")
         cat(wrap_text(result_text, width = 68, prefix = "    "), "\n")
       } else if (grepl("successfully", result_text)) {
         cat("\n<<< RESULT: SUCCESS\n")
         # Extract attempt number
         if (grepl("attempt (\\d+)", result_text)) {
           attempt <- sub(".*attempt (\\d+)/.*", "\\1", result_text)
           cat("    Code executed successfully on attempt ", attempt, "\n", sep = "")
         }
       } else {
         cat("\n<<< RESULT:\n")
         cat(wrap_text(substr(result_text, 1, 300), width = 68, prefix = "    "), "\n")
       }
     }
   }
 }

 if (tool_call_num == 0) {
   cat("\n  (No tool calls made)\n")
 }

 # 3. Final code
 cat("\n")
 cat(strrep("-", 70), "\n")
 cat("3. FINAL CODE\n")
 cat(strrep("-", 70), "\n")

 if (!is.null(run$code) && nchar(run$code) > 0) {
   cat(format_code_block(run$code), "\n")
 } else {
   cat("\n  (No code captured)\n")
 }

 # 4. Final result
 cat("\n")
 cat(strrep("-", 70), "\n")
 cat("4. FINAL RESULT\n")
 cat(strrep("-", 70), "\n")

 if (is.null(run$result)) {
   cat("\n  NULL (no result)\n")
 } else if (inherits(run$result, "eval_error")) {
   cat("\n  ERROR: ", run$result, "\n", sep = "")
 } else if (is.data.frame(run$result)) {
   cat("\n  data.frame [", nrow(run$result), " rows x ", ncol(run$result), " cols]\n", sep = "")
   cat("  Columns: ", paste(names(run$result), collapse = ", "), "\n\n", sep = "")

   # Show preview
   cat("  Preview:\n")
   preview <- utils::capture.output(print(as.data.frame(run$result)))
   # Limit to first 10 lines
   if (length(preview) > 10) {
     preview <- c(preview[1:10], "    ...")
   }
   cat(paste("    ", preview, collapse = "\n"), "\n")
 } else {
   cat("\n  Class: ", class(run$result)[1], "\n", sep = "")
   cat("  ", substr(utils::capture.output(str(run$result)), 1, 200), "\n", sep = "")
 }

 # 5. Summary metrics
 cat("\n")
 cat(strrep("-", 70), "\n")
 cat("5. METRICS\n")
 cat(strrep("-", 70), "\n")

 tool_calls <- count_tool_calls(run$turns)
 cat("\n")
 cat("  Duration:    ", round(run$duration_secs, 1), " sec\n", sep = "")
 cat("  Tool calls:
  ", tool_calls$total, " total", sep = "")
 if (tool_calls$total > 0) {
   cat(" (", paste(names(tool_calls$by_tool), tool_calls$by_tool, sep = ": ", collapse = ", "), ")", sep = "")
 }
 cat("\n")
 cat("  Success:
    ", !is.null(run$code) && is.data.frame(run$result), "\n", sep = "")

 cat("\n")
 cat(strrep("=", 70), "\n")

 invisible(run)
}


# --- Helper: count tool calls ---

count_tool_calls <- function(turns) {

 total <- 0
 by_tool <- list()

 for (turn in turns) {
   if (length(turn@contents) > 0) {
     for (content in turn@contents) {
       # S7 class names include namespace, e.g., "ellmer::ContentToolRequest"
       cls <- class(content)[1]
       if (grepl("ToolRequest", cls)) {
         total <- total + 1
         nm <- content@name
         by_tool[[nm]] <- (by_tool[[nm]] %||% 0) + 1
       }
     }
   }
 }

 list(total = total, by_tool = by_tool)
}


# --- Helper: format code block ---

format_code_block <- function(code, indent = 2) {
 lines <- strsplit(code, "\n")[[1]]
 prefix <- strrep(" ", indent)
 paste(prefix, lines, sep = "", collapse = "\n")
}


# --- Helper: wrap text ---

wrap_text <- function(text, width = 70, prefix = "") {
 words <- strsplit(text, " ")[[1]]
 lines <- character()
 current_line <- prefix

 for (word in words) {
   if (nchar(current_line) + nchar(word) + 1 > width) {
     lines <- c(lines, current_line)
     current_line <- paste0(prefix, word)
   } else {
     if (current_line == prefix) {
       current_line <- paste0(current_line, word)
     } else {
       current_line <- paste0(current_line, " ", word)
     }
   }
 }
 lines <- c(lines, current_line)
 paste(lines, collapse = "\n")
}


# Null coalesce operator (if not available)
`%||%` <- function(x, y) if (is.null(x)) y else x


# =============================================================================
# Result Storage (YAML-based)
# =============================================================================

RESULTS_DIR <- "dev/results"

# --- Save a single run to YAML ---

run_to_yaml <- function(run, variant = "default", run_number = 1) {

  # Extract tool sequence with full details

  tool_seq <- extract_tool_sequence(run$turns, verbose = TRUE)

  # Result preview
  result_preview <- if (is.data.frame(run$result)) {
    paste(utils::capture.output(print(run$result)), collapse = "\n")
  } else if (is.null(run$result)) {
    "NULL"
  } else {
    paste(class(run$result), collapse = ", ")
  }

  # Build YAML content
  lines <- c(
    "# Full run details for debugging",
    "",
    "meta:",
    paste0("  timestamp: \"", format(Sys.time(), "%Y-%m-%d %H:%M:%S"), "\""),
    paste0("  model: \"", run$config$model %||% "unknown", "\""),
    paste0("  variant: \"", variant, "\""),
    paste0("  run_number: ", run_number),
    "",
    "metrics:",
    paste0("  has_result: ", tolower(as.character(is.data.frame(run$result)))),
    paste0("  duration_secs: ", round(run$duration_secs, 1)),
    paste0("  tool_calls: ", count_tool_calls(run$turns)$total),
    "",
    "prompt: |",
    paste0("  ", strsplit(run$prompt, "\n")[[1]]),
    "",
    "# Each step shows the tool called, the code submitted, and the response",
    "steps:",
    tool_seq,
    "",
    "# Final validated code (from eval_tool)",
    "final_code: |",
    if (!is.null(run$code)) paste0("  ", strsplit(run$code, "\n")[[1]]) else "  # no code captured",
    "",
    "# Final result",
    "result: |",
    paste0("  ", strsplit(result_preview, "\n")[[1]]),
    "",
    paste0("error: ", if (is.null(run$error)) "null" else paste0("\"", run$error, "\""))
  )

  paste(lines, collapse = "\n")
}

extract_tool_sequence <- function(turns, verbose = FALSE) {
  lines <- character()
  step <- 0

  for (turn in turns) {
    for (content in turn@contents) {
      cls <- class(content)[1]

      if (grepl("ToolRequest", cls)) {
        step <- step + 1
        code <- content@arguments$code %||% ""

        lines <- c(lines,
          paste0("  - step: ", step),
          paste0("    tool: ", content@name)
        )

        if (verbose && nchar(code) > 0) {
          # Include full code, indented
          code_lines <- strsplit(code, "\n")[[1]]
          lines <- c(lines,
            "    code: |",
            paste0("      ", code_lines)
          )
        } else {
          lines <- c(lines, paste0("    code_length: ", nchar(code)))
        }
      }

      if (grepl("ToolResult", cls)) {
        result_text <- paste(content@value, collapse = "\n")
        is_error <- grepl("Error", result_text)

        if (verbose) {
          # Include full result, truncated if too long
          if (nchar(result_text) > 500) {
            result_text <- paste0(substr(result_text, 1, 500), "\n... (truncated)")
          }
          result_lines <- strsplit(result_text, "\n")[[1]]
          lines <- c(lines,
            paste0("    status: ", if (is_error) "error" else "success"),
            "    response: |",
            paste0("      ", result_lines)
          )
        } else {
          lines <- c(lines, paste0("    status: ", if (is_error) "error" else "success"))
        }
      }
    }
  }

  if (length(lines) == 0) "  []"
  else lines
}


# --- Save experiment (multiple runs) ---
#
# Saves results for Claude to evaluate later:
# - prompt.txt: the original prompt
# - run_01_a.yaml, run_01_b.yaml: full run details (prompt, steps, code, result)
# - meta.yaml: timing/model info + Claude's evaluation (added later)
#
save_experiment <- function(results_a, results_b, config, prompt,
                            name = "experiment") {

  # Create folder
  timestamp <- format(Sys.time(), "%Y%m%d_%H%M%S")
  model_clean <- gsub("[^a-zA-Z0-9]", "-", config$model %||% "unknown")
  folder_name <- paste0("trial_", name, "_", model_clean, "_", timestamp)
  folder_path <- file.path(RESULTS_DIR, folder_name)

  dir.create(folder_path, recursive = TRUE, showWarnings = FALSE)

  cat("Saving to:", folder_path, "\n")

  # Save prompt
  writeLines(prompt, file.path(folder_path, "prompt.txt"))

  # Save each run as YAML with full details
  for (i in seq_along(results_a)) {
    yaml_content <- run_to_yaml(results_a[[i]], "a", i)
    writeLines(yaml_content, file.path(folder_path, sprintf("run_%02d_a.yaml", i)))
  }
  for (i in seq_along(results_b)) {
    yaml_content <- run_to_yaml(results_b[[i]], "b", i)
    writeLines(yaml_content, file.path(folder_path, sprintf("run_%02d_b.yaml", i)))
  }

  # Save metadata
  meta <- c(
    paste0("name: ", name),
    paste0("model: ", config$model %||% "unknown"),
    paste0("timestamp: ", format(Sys.time(), "%Y-%m-%d %H:%M:%S")),
    paste0("n_runs: ", length(results_a)),
    "",
    "# Variant A: no preview",
    "# Variant B: with preview",
    "",
    "durations_a: [",
    paste0("  ", paste(round(sapply(results_a, `[[`, "duration_secs"), 1), collapse = ", ")),
    "]",
    "durations_b: [",
    paste0("  ", paste(round(sapply(results_b, `[[`, "duration_secs"), 1), collapse = ", ")),
    "]",
    "",
    "tool_calls_a: [",
    paste0("  ", paste(sapply(results_a, function(r) count_tool_calls(r$turns)$total), collapse = ", ")),
    "]",
    "tool_calls_b: [",
    paste0("  ", paste(sapply(results_b, function(r) count_tool_calls(r$turns)$total), collapse = ", ")),
    "]"
  )
  writeLines(meta, file.path(folder_path, "meta.yaml"))

  cat("Saved", length(results_a) + length(results_b), "runs\n")
  cat("\nTo evaluate: 'evaluate results in", folder_path, "'\n")

  invisible(folder_path)
}


# --- Save experiment with 3 variants ---

save_experiment_3way <- function(results_a, results_b, results_c, config, prompt,
                                  name = "experiment") {

  # Create folder
  timestamp <- format(Sys.time(), "%Y%m%d_%H%M%S")
  model_clean <- gsub("[^a-zA-Z0-9]", "-", config$model %||% "unknown")
  folder_name <- paste0("trial_", name, "_", model_clean, "_", timestamp)
  folder_path <- file.path(RESULTS_DIR, folder_name)

  dir.create(folder_path, recursive = TRUE, showWarnings = FALSE)

  cat("Saving to:", folder_path, "\n")

  # Save prompt
  writeLines(prompt, file.path(folder_path, "prompt.txt"))

  # Save each run as YAML
  for (i in seq_along(results_a)) {
    yaml_content <- run_to_yaml(results_a[[i]], "a", i)
    writeLines(yaml_content, file.path(folder_path, sprintf("run_%02d_a.yaml", i)))
  }
  for (i in seq_along(results_b)) {
    yaml_content <- run_to_yaml(results_b[[i]], "b", i)
    writeLines(yaml_content, file.path(folder_path, sprintf("run_%02d_b.yaml", i)))
  }
  for (i in seq_along(results_c)) {
    yaml_content <- run_to_yaml(results_c[[i]], "c", i)
    writeLines(yaml_content, file.path(folder_path, sprintf("run_%02d_c.yaml", i)))
  }

  # Save metadata
  meta <- c(
    paste0("name: ", name),
    paste0("model: ", config$model %||% "unknown"),
    paste0("timestamp: ", format(Sys.time(), "%Y-%m-%d %H:%M:%S")),
    paste0("n_runs: ", length(results_a)),
    "",
    "# Variant A: no preview (baseline)",
    "# Variant B: with preview (LLM sees result)",
    "# Variant C: with validation (retry if no valid result)",
    "",
    "durations_a: [",
    paste0("  ", paste(round(sapply(results_a, `[[`, "duration_secs"), 1), collapse = ", ")),
    "]",
    "durations_b: [",
    paste0("  ", paste(round(sapply(results_b, `[[`, "duration_secs"), 1), collapse = ", ")),
    "]",
    "durations_c: [",
    paste0("  ", paste(round(sapply(results_c, `[[`, "duration_secs"), 1), collapse = ", ")),
    "]",
    "",
    "tool_calls_a: [",
    paste0("  ", paste(sapply(results_a, function(r) count_tool_calls(r$turns)$total), collapse = ", ")),
    "]",
    "tool_calls_b: [",
    paste0("  ", paste(sapply(results_b, function(r) count_tool_calls(r$turns)$total), collapse = ", ")),
    "]",
    "tool_calls_c: [",
    paste0("  ", paste(sapply(results_c, function(r) count_tool_calls(r$turns)$total), collapse = ", ")),
    "]",
    "",
    "validation_retries_c: [",
    paste0("  ", paste(sapply(results_c, function(r) r$validation_retries %||% 0), collapse = ", ")),
    "]",
    "",
    "# Quick summary: how many produced a valid data.frame?",
    paste0("has_result_a: ", sum(sapply(results_a, function(r) is.data.frame(r$result))), "/", length(results_a)),
    paste0("has_result_b: ", sum(sapply(results_b, function(r) is.data.frame(r$result))), "/", length(results_b)),
    paste0("has_result_c: ", sum(sapply(results_c, function(r) is.data.frame(r$result))), "/", length(results_c))
  )
  writeLines(meta, file.path(folder_path, "meta.yaml"))

  total_runs <- length(results_a) + length(results_b) + length(results_c)
  cat("Saved", total_runs, "runs\n")
  cat("\nTo evaluate: 'evaluate results in", folder_path, "'\n")

  invisible(folder_path)
}


create_summary_yaml <- function(results_a, results_b, config, name) {

  summarize_variant <- function(results) {
    successes <- sum(sapply(results, function(r) is.data.frame(r$result)))
    durations <- sapply(results, `[[`, "duration_secs")
    calls <- sapply(results, function(r) count_tool_calls(r$turns)$total)

    list(
      success_rate = successes / length(results),
      duration_median = median(durations),
      duration_all = durations,
      tool_calls_median = median(calls),
      tool_calls_all = calls
    )
  }

  sum_a <- summarize_variant(results_a)
  sum_b <- summarize_variant(results_b)

  lines <- c(
    "experiment:",
    paste0("  name: \"", name, "\""),
    paste0("  model: \"", config$model %||% "unknown", "\""),
    paste0("  timestamp: \"", format(Sys.time(), "%Y-%m-%d %H:%M:%S"), "\""),
    paste0("  n_runs_per_variant: ", length(results_a)),
    "",
    "no_preview:",
    paste0("  success_rate: ", sum_a$success_rate),
    paste0("  duration_median: ", round(sum_a$duration_median, 1)),
    paste0("  duration_all: [", paste(round(sum_a$duration_all, 1), collapse = ", "), "]"),
    paste0("  tool_calls_median: ", sum_a$tool_calls_median),
    paste0("  tool_calls_all: [", paste(sum_a$tool_calls_all, collapse = ", "), "]"),
    "",
    "with_preview:",
    paste0("  success_rate: ", sum_b$success_rate),
    paste0("  duration_median: ", round(sum_b$duration_median, 1)),
    paste0("  duration_all: [", paste(round(sum_b$duration_all, 1), collapse = ", "), "]"),
    paste0("  tool_calls_median: ", sum_b$tool_calls_median),
    paste0("  tool_calls_all: [", paste(sum_b$tool_calls_all, collapse = ", "), "]")
  )

  paste(lines, collapse = "\n")
}


# --- List experiments ---

list_experiments <- function() {
  if (!dir.exists(RESULTS_DIR)) {
    cat("No results directory yet.\n")
    return(invisible(NULL))
  }

  folders <- list.dirs(RESULTS_DIR, full.names = FALSE, recursive = FALSE)
  folders <- folders[grepl("^trial_", folders)]

  if (length(folders) == 0) {
    cat("No experiments found.\n")
    return(invisible(NULL))
  }

  cat("Experiments in", RESULTS_DIR, ":\n\n")
  for (f in sort(folders, decreasing = TRUE)) {
    meta_file <- file.path(RESULTS_DIR, f, "meta.yaml")
    if (file.exists(meta_file)) {
      lines <- readLines(meta_file, warn = FALSE)
      model <- gsub("model: ", "", grep("^model:", lines, value = TRUE)[1])
      n_runs <- gsub("n_runs: ", "", grep("^n_runs:", lines, value = TRUE)[1])

      # Count CSVs
      csvs <- list.files(file.path(RESULTS_DIR, f), pattern = "\\.csv$")

      cat(sprintf("  %s\n", f))
      cat(sprintf("    model: %s | runs: %s | files: %d CSVs\n\n",
                  model, n_runs, length(csvs)))
    } else {
      cat(sprintf("  %s (no meta)\n", f))
    }
  }

  invisible(folders)
}


# --- Modified eval_tool that returns result preview ---
#
# This is an experimental variant that shows the LLM what the result
# looks like, so it can verify the output matches expectations.
#
new_eval_tool_with_result <- function(x, datasets,
                                      max_retries = 5L,
                                      preview_rows = 6L,
                                      ...) {

  invocation_count <- 0
  current_code <- NULL

  execute_r_code <- function(code, explanation = "") {

    invocation_count <<- invocation_count + 1

    cat("[eval_tool] Attempt ", invocation_count, "/", max_retries, "\n", sep = "")

    if (invocation_count > max_retries) {
      invocation_count <<- 0
      current_code <<- NULL
      ellmer::tool_reject(
        paste0("Maximum attempts (", max_retries, ") exceeded.")
      )
    }

    # Evaluate the code
    env <- list2env(datasets, parent = baseenv())
    result <- tryCatch(
      eval(parse(text = code), envir = env),
      error = function(e) {
        structure(conditionMessage(e), class = "eval_error")
      }
    )

    # Handle errors
    if (inherits(result, "eval_error")) {
      current_code <<- NULL
      error_msg <- as.character(result)

      if (invocation_count < max_retries) {
        return(paste0(
          "Error on attempt ", invocation_count, "/", max_retries, ":\n",
          error_msg, "\n\n",
          "Please fix the code and try again."
        ))
      } else {
        invocation_count <<- 0
        ellmer::tool_reject(paste0("Final error: ", error_msg))
      }
    }

    # Success - build result preview
    current_code <<- code

    # Create preview of the result
    preview <- ""
    if (is.data.frame(result)) {
      preview <- paste0(
        "\n\nResult preview (", nrow(result), " rows x ", ncol(result), " cols):\n",
        "Columns: ", paste(names(result), collapse = ", "), "\n\n",
        paste(
          utils::capture.output(print(utils::head(as.data.frame(result), preview_rows))),
          collapse = "\n"
        )
      )
    } else {
      preview <- paste0(
        "\n\nResult class: ", class(result)[1],
        "\n", substr(utils::capture.output(str(result)), 1, 300)
      )
    }

    invocation_count <<- 0

    paste0(
      "Code executed successfully on attempt ", invocation_count, "/", max_retries, ".",
      preview,
      "\n\nPlease verify this output matches the user's requirements. ",
      "If it looks correct, you can respond to the user. ",
      "If not, call this tool again with corrected code."
    )
  }

  new_llm_tool(
    execute_r_code,
    description = paste0(
      "Execute R code and see the result. ",
      "Returns a preview of the output so you can verify it matches requirements. ",
      "Maximum ", max_retries, " attempts allowed."
    ),
    name = "eval_tool",
    prompt = paste(
      "Before responding to the user, you MUST verify your code using eval_tool.",
      "The tool will show you what the result looks like.",
      "Check that the output matches the user's requirements (column names,",
      "row count, data types, sorting, etc.) before concluding."
    ),
    arguments = list(
      code = ellmer::type_string("R code to execute"),
      explanation = ellmer::type_string("Explanation of what the code does")
    )
  )
}


# --- Run function with result preview ---
#
# Same as run_llm_ellmer but uses the modified eval_tool
#
run_llm_ellmer_with_preview <- function(prompt, data, config) {

  cat("\n")
  cat(strrep("=", 60), "\n")
  cat("RUN: ellmer direct (with result preview)\n")
  cat(strrep("=", 60), "\n\n")

  start <- Sys.time()

  if (is.data.frame(data)) {
    datasets <- list(data = data)
  } else {
    datasets <- data
  }

  cat("Creating proxy...\n")
  proxy <- structure(
    list(messages = list(), code = character()),
    class = c("llm_transform_block_proxy", "llm_block_proxy")
  )

  # Use modified eval_tool that returns result preview
  cat("Creating tools (with result preview)...\n")
  tools <- list(
    new_eval_tool_with_result(proxy, datasets),  # <-- modified tool
    new_data_tool(proxy, datasets)
  )
  cat("  Tools:", paste(sapply(tools, function(t) t$tool@name), collapse = ", "), "\n")

  cat("Building system prompt...\n")
  sys_prompt <- system_prompt(proxy, datasets, tools)
  cat("  Length:", nchar(sys_prompt), "chars\n")

  cat("Creating LLM client...\n")
  client <- config$chat_fn()

  client$set_system_prompt(sys_prompt)
  client$set_tools(lapply(tools, get_tool))

  cat("\n")
  cat(strrep("-", 60), "\n")
  cat("Calling LLM (synchronous)...\n")
  cat(strrep("-", 60), "\n\n")

  error <- NULL
  response <- tryCatch(
    client$chat(prompt),
    error = function(e) {
      error <<- conditionMessage(e)
      NULL
    }
  )

  duration <- as.numeric(difftime(Sys.time(), start, units = "secs"))

  cat("\n")
  cat(strrep("-", 60), "\n")
  cat("LLM finished in", round(duration, 1), "seconds\n")
  cat(strrep("-", 60), "\n")

  cat("\nExtracting code from eval_tool...\n")
  eval_tool_obj <- tools[[1]]
  tool_fn <- get_tool(eval_tool_obj)
  tool_env <- environment(tool_fn)
  code <- get0("current_code", envir = tool_env, inherits = FALSE)

  if (!is.null(code) && nchar(code) > 0) {
    cat("  Code captured successfully\n")
  } else {
    cat("  No code captured\n")
    code <- NULL
  }

  result <- NULL
  if (!is.null(code)) {
    cat("Evaluating code...\n")
    result <- tryCatch(
      eval(parse(text = code), envir = list2env(datasets, parent = baseenv())),
      error = function(e) {
        structure(conditionMessage(e), class = "eval_error")
      }
    )
  }

  list(
    code = code,
    result = result,
    response = response,
    turns = client$get_turns(),
    duration_secs = duration,
    error = error,
    config = config,
    prompt = prompt,
    variant = "with_preview"  # tag to identify this variant
  )
}


# --- Variant C: with final validation loop ---
#
# Runs the LLM, then checks if we got a valid result.
# If not, sends a follow-up message asking the LLM to validate with eval_tool.
# Repeats up to max_validation_retries times.
#
run_llm_ellmer_with_validation <- function(prompt, data, config,
                                            max_validation_retries = 3) {

  cat("\n")
  cat(strrep("=", 60), "\n")
  cat("RUN: ellmer direct (with validation loop)\n")
  cat(strrep("=", 60), "\n\n")

  start <- Sys.time()

  if (is.data.frame(data)) {
    datasets <- list(data = data)
  } else {
    datasets <- data
  }

  cat("Creating proxy...\n")
  proxy <- structure(
    list(messages = list(), code = character()),
    class = c("llm_transform_block_proxy", "llm_block_proxy")
  )

  cat("Creating tools...\n")
  tools <- list(
    new_eval_tool(proxy, datasets),
    new_data_tool(proxy, datasets)
  )
  cat("  Tools:", paste(sapply(tools, function(t) t$tool@name), collapse = ", "), "\n")

  cat("Building system prompt...\n")
  sys_prompt <- system_prompt(proxy, datasets, tools)
  cat("  Length:", nchar(sys_prompt), "chars\n")

  cat("Creating LLM client...\n")
  client <- config$chat_fn()

  client$set_system_prompt(sys_prompt)
  client$set_tools(lapply(tools, get_tool))

  cat("\n")
  cat(strrep("-", 60), "\n")
  cat("Calling LLM (synchronous)...\n")
  cat(strrep("-", 60), "\n\n")

  error <- NULL
  response <- tryCatch(
    client$chat(prompt),
    error = function(e) {
      error <<- conditionMessage(e)
      NULL
    }
  )

  # Helper to extract code and result
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

  # Check initial result
  extracted <- extract_result()
  code <- extracted$code
  result <- extracted$result

  # Validation loop
  validation_attempt <- 0
  while (!is.data.frame(result) && validation_attempt < max_validation_retries) {
    validation_attempt <- validation_attempt + 1

    cat("\n")
    cat(strrep("-", 60), "\n")
    cat("VALIDATION RETRY ", validation_attempt, "/", max_validation_retries, "\n", sep = "")
    cat("Result is not a valid data.frame. Asking LLM to fix...\n")
    cat(strrep("-", 60), "\n\n")

    # Send follow-up message
    retry_msg <- if (is.null(code) || nchar(code) == 0) {
      "You haven't validated your code with eval_tool yet. Please call eval_tool with your R code to complete the task. The code must produce a data.frame as output."
    } else {
      "The code did not produce a valid data.frame result. Please fix the code and call eval_tool again to validate it."
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

  cat("\n")
  cat(strrep("-", 60), "\n")
  cat("LLM finished in", round(duration, 1), "seconds\n")
  if (validation_attempt > 0) {
    cat("  (", validation_attempt, " validation retries)\n", sep = "")
  }
  cat(strrep("-", 60), "\n")

  if (is.data.frame(result)) {
    cat("  Final result: data.frame with", nrow(result), "rows\n")
  } else {
    cat("  Final result: NOT a valid data.frame\n")
  }

  list(
    code = code,
    result = result,
    response = response,
    turns = client$get_turns(),
    duration_secs = duration,
    error = error,
    config = config,
    prompt = prompt,
    validation_retries = validation_attempt,
    variant = "with_validation"
  )
}


# --- Variant D: preview + validation loop ---
#
# Combines B (preview) and C (validation):
# - eval_tool shows result preview so LLM can verify
# - Retry loop if no valid data.frame result
#
run_llm_ellmer_with_preview_and_validation <- function(prompt, data, config,
                                                        max_validation_retries = 3) {

  cat("\n")
  cat(strrep("=", 60), "\n")
  cat("RUN: ellmer direct (preview + validation)\n")
  cat(strrep("=", 60), "\n\n")

  start <- Sys.time()

  if (is.data.frame(data)) {
    datasets <- list(data = data)
  } else {
    datasets <- data
  }

  cat("Creating proxy...\n")
  proxy <- structure(
    list(messages = list(), code = character()),
    class = c("llm_transform_block_proxy", "llm_block_proxy")
  )

  # Use preview eval_tool (from variant B)
  cat("Creating tools (with result preview)...\n")
  tools <- list(
    new_eval_tool_with_result(proxy, datasets),
    new_data_tool(proxy, datasets)
  )
  cat("  Tools:", paste(sapply(tools, function(t) t$tool@name), collapse = ", "), "\n")

  cat("Building system prompt...\n")
  sys_prompt <- system_prompt(proxy, datasets, tools)
  cat("  Length:", nchar(sys_prompt), "chars\n")

  cat("Creating LLM client...\n")
  client <- config$chat_fn()

  client$set_system_prompt(sys_prompt)
  client$set_tools(lapply(tools, get_tool))

  cat("\n")
  cat(strrep("-", 60), "\n")
  cat("Calling LLM (synchronous)...\n")
  cat(strrep("-", 60), "\n\n")

  error <- NULL
  response <- tryCatch(
    client$chat(prompt),
    error = function(e) {
      error <<- conditionMessage(e)
      NULL
    }
  )

  # Helper to extract code and result
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

  # Check initial result
  extracted <- extract_result()
  code <- extracted$code
  result <- extracted$result

  # Validation loop (from variant C)
  validation_attempt <- 0
  while (!is.data.frame(result) && validation_attempt < max_validation_retries) {
    validation_attempt <- validation_attempt + 1

    cat("\n")
    cat(strrep("-", 60), "\n")
    cat("VALIDATION RETRY ", validation_attempt, "/", max_validation_retries, "\n", sep = "")
    cat("Result is not a valid data.frame. Asking LLM to fix...\n")
    cat(strrep("-", 60), "\n\n")

    # Send follow-up message
    retry_msg <- if (is.null(code) || nchar(code) == 0) {
      "You haven't validated your code with eval_tool yet. Please call eval_tool with your R code to complete the task. The code must produce a data.frame as output."
    } else {
      "The code did not produce a valid data.frame result. Please check the result preview and fix the code, then call eval_tool again."
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

  cat("\n")
  cat(strrep("-", 60), "\n")
  cat("LLM finished in", round(duration, 1), "seconds\n")
  if (validation_attempt > 0) {
    cat("  (", validation_attempt, " validation retries)\n", sep = "")
  }
  cat(strrep("-", 60), "\n")

  if (is.data.frame(result)) {
    cat("  Final result: data.frame with", nrow(result), "rows\n")
  } else {
    cat("  Final result: NOT a valid data.frame\n")
  }

  list(
    code = code,
    result = result,
    response = response,
    turns = client$get_turns(),
    duration_secs = duration,
    error = error,
    config = config,
    prompt = prompt,
    validation_retries = validation_attempt,
    variant = "preview_and_validation"
  )
}


# ==============================================================================
# MODULAR EXPERIMENT API
# ==============================================================================
#
# New modular API for running experiments:
#   - run_experiment(): run 1+ times, produce 1 YAML per run
#   - judge_runs(): evaluate YAMLs, add evaluation section
#   - compare_trials(): compare across trials in an experiment
#

# --- run_experiment ---
#
# Run an experiment and save results as YAML files.
#
# Arguments:
#   run_fn      - The run function to use (e.g., run_llm_ellmer, run_llm_ellmer_with_validation)
#   prompt      - The prompt to send to the LLM
#   data        - The data to use (data.frame or named list)
#   output_dir  - Directory to save YAML files (will be created if needed)
#   model       - Model name (default: "gpt-4o-mini")
#   times       - Number of runs (default: 1)
#   ...         - Additional arguments passed to run_fn
#
# Returns:
#   Character vector of paths to saved YAML files
#
run_experiment <- function(run_fn, prompt, data, output_dir,
                            model = "gpt-4o-mini",
                            provider = "openai",
                            times = 1,
                            ...) {

  # Create output directory
  if (!dir.exists(output_dir)) {
    dir.create(output_dir, recursive = TRUE)
    cat("Created directory:", output_dir, "\n")
  }

  # Find existing run files to determine next number
  existing <- list.files(output_dir, pattern = "^run_\\d{3}\\.yaml$")
  if (length(existing) == 0) {
    next_num <- 1
  } else {
    nums <- as.integer(gsub("run_(\\d{3})\\.yaml", "\\1", existing))
    next_num <- max(nums) + 1
  }

  # Create config based on provider
  chat_fn <- switch(provider,
    "openai" = function() ellmer::chat_openai(model = model),
    "ollama" = function() ellmer::chat_ollama(model = model),
    stop("Unknown provider: ", provider, ". Use 'openai' or 'ollama'.")
  )

  config <- list(
    model = model,
    provider = provider,
    chat_fn = chat_fn
  )

  saved_files <- character()

  for (i in seq_len(times)) {
    run_num <- next_num + i - 1

    cat("\n")
    cat(strrep("#", 70), "\n")
    cat("# RUN ", run_num, " of ", next_num + times - 1, "\n", sep = "")
    cat(strrep("#", 70), "\n")

    # Execute run
    result <- run_fn(prompt = prompt, data = data, config = config, ...)

    # Convert to YAML
    yaml_content <- run_to_yaml_v2(result, run_num, deparse(substitute(run_fn)))

    # Save
    filename <- sprintf("run_%03d.yaml", run_num)
    filepath <- file.path(output_dir, filename)
    writeLines(yaml_content, filepath)

    cat("\nSaved:", filepath, "\n")
    saved_files <- c(saved_files, filepath)
  }

  cat("\n")
  cat(strrep("=", 70), "\n")
  cat("Completed ", times, " run(s). Files saved to: ", output_dir, "\n", sep = "")
  cat(strrep("=", 70), "\n")

  invisible(saved_files)
}


# --- run_to_yaml_v2 ---
#
# Convert a run result to YAML format (v2 - for modular API)
#
run_to_yaml_v2 <- function(run, run_number, run_fn_name = "unknown") {

  # Extract tool sequence with full details
  tool_seq <- extract_tool_sequence(run$turns, verbose = TRUE)

  # Result preview
  result_preview <- if (is.data.frame(run$result)) {
    paste(utils::capture.output(print(run$result)), collapse = "\n")
  } else if (is.null(run$result)) {
    "NULL"
  } else {
    paste(class(run$result), collapse = ", ")
  }

  # Data summary
  if (is.data.frame(run$config$data_used %||% NULL)) {
    data_info <- run$config$data_used
  } else {
    data_info <- NULL
  }

  # Build YAML content
  lines <- c(
    "# Experiment Run",
    "#",
    "# This file contains a complete record of one LLM run.",
    "# Generated by run_experiment()",
    "",
    "meta:",
    paste0("  timestamp: \"", format(Sys.time(), "%Y-%m-%d %H:%M:%S"), "\""),
    paste0("  run_number: ", run_number),
    paste0("  run_fn: \"", run_fn_name, "\""),
    paste0("  model: \"", run$config$model %||% "unknown", "\""),
    if (!is.null(run$config$provider)) paste0("  provider: \"", run$config$provider, "\"") else NULL,
    "",
    "metrics:",
    paste0("  has_result: ", tolower(as.character(is.data.frame(run$result)))),
    paste0("  duration_secs: ", round(run$duration_secs, 1)),
    paste0("  tool_calls: ", count_tool_calls(run$turns)$total),
    if (!is.null(run$validation_retries)) paste0("  validation_retries: ", run$validation_retries) else NULL,
    if (!is.null(run$iterations)) paste0("  iterations: ", run$iterations) else NULL,
    "",
    "prompt: |",
    paste0("  ", strsplit(run$prompt, "\n")[[1]]),
    ""
  )

  # Add skills tracking if present
  if (!is.null(run$skills_injected) && length(run$skills_injected) > 0) {
    lines <- c(lines,
      "# Skills injected into system prompt",
      "skills:",
      "  injected:",
      paste0("    - ", run$skills_injected)
    )

    # Add skill usage detection results
    if (!is.null(run$skill_usage)) {
      lines <- c(lines, "  usage:")

      for (skill_name in names(run$skill_usage)) {
        usage <- run$skill_usage[[skill_name]]
        lines <- c(lines,
          paste0("    ", skill_name, ":"),
          paste0("      usage_score: ", usage$usage_score),
          paste0("      matched: ", usage$matched, "/", usage$total),
          "      patterns:"
        )
        for (pattern_name in names(usage$patterns)) {
          lines <- c(lines,
            paste0("        ", pattern_name, ": ", tolower(as.character(usage$patterns[[pattern_name]])))
          )
        }
      }
    }
    lines <- c(lines, "")
  }

  lines <- c(lines,
    "# Tool call sequence",
    "steps:",
    tool_seq,
    "",
    "# Final validated code",
    "final_code: |",
    if (!is.null(run$code) && nchar(run$code) > 0) paste0("  ", strsplit(run$code, "\n")[[1]]) else "  # no code captured",
    "",
    "# Final result",
    "result: |",
    paste0("  ", strsplit(result_preview, "\n")[[1]]),
    "",
    paste0("error: ", if (is.null(run$error)) "null" else paste0("\"", run$error, "\"")),
    "",
    "# Evaluation (added by judge_runs())",
    "# evaluation:",
    "#   correct: null",
    "#   reason: \"\""
  )

  # Remove NULLs
  lines <- lines[!sapply(lines, is.null)]

  paste(lines, collapse = "\n")
}


# --- judge_runs ---
#
# Placeholder for evaluation function.
# In practice, this would be called by Claude to evaluate each run.
#
# Arguments:
#   trial_dir - Directory containing run_*.yaml files
#
# Returns:
#   Data frame with evaluation summary
#
judge_runs <- function(trial_dir) {

  if (!dir.exists(trial_dir)) {
    stop("Directory does not exist: ", trial_dir)
  }

  yaml_files <- list.files(trial_dir, pattern = "^run_\\d{3}\\.yaml$", full.names = TRUE)

  if (length(yaml_files) == 0) {
    stop("No run_*.yaml files found in: ", trial_dir)
  }

  cat("Found", length(yaml_files), "run files in:", trial_dir, "\n\n")

  for (f in yaml_files) {
    cat("  -", basename(f), "\n")
  }

  cat("\n")
  cat("To evaluate these runs, ask Claude:\n")
  cat("  \"Evaluate the runs in", trial_dir, "\"\n")
  cat("\n")
  cat("Claude will:\n")
  cat("  1. Read each YAML file\n")
  cat("  2. Check if the result meets the prompt requirements\n")
  cat("  3. Add an 'evaluation' section to each YAML\n")

  invisible(yaml_files)
}


# --- compare_trials ---
#
# Compare results across trials in an experiment.
#
# Arguments:
#   experiment_dir - Directory containing trial_* subdirectories
#
# Returns:
#   Data frame with comparison summary
#
compare_trials <- function(experiment_dir) {

  if (!dir.exists(experiment_dir)) {
    stop("Directory does not exist: ", experiment_dir)
  }

  # Find trial directories
  trial_dirs <- list.dirs(experiment_dir, recursive = FALSE)
  trial_dirs <- trial_dirs[grepl("^trial_", basename(trial_dirs))]

  if (length(trial_dirs) == 0) {
    stop("No trial_* directories found in: ", experiment_dir)
  }

  cat("Found", length(trial_dirs), "trials in:", experiment_dir, "\n\n")

  results <- list()

  for (trial_dir in trial_dirs) {
    trial_name <- basename(trial_dir)
    yaml_files <- list.files(trial_dir, pattern = "^run_\\d{3}\\.yaml$", full.names = TRUE)

    n_runs <- length(yaml_files)
    n_with_result <- 0
    n_correct <- 0
    total_duration <- 0
    total_tool_calls <- 0

    for (f in yaml_files) {
      content <- readLines(f, warn = FALSE)
      text <- paste(content, collapse = "\n")

      # Parse basic metrics
      has_result <- grepl("has_result: true", text)
      if (has_result) n_with_result <- n_with_result + 1

      # Check for evaluation
      if (grepl("correct: true", text)) {
        n_correct <- n_correct + 1
      }

      # Extract duration
      dur_match <- regmatches(text, regexpr("duration_secs: [0-9.]+", text))
      if (length(dur_match) > 0) {
        total_duration <- total_duration + as.numeric(gsub("duration_secs: ", "", dur_match))
      }

      # Extract tool calls
      tc_match <- regmatches(text, regexpr("tool_calls: [0-9]+", text))
      if (length(tc_match) > 0) {
        total_tool_calls <- total_tool_calls + as.integer(gsub("tool_calls: ", "", tc_match))
      }
    }

    results[[trial_name]] <- data.frame(
      trial = trial_name,
      n_runs = n_runs,
      has_result = paste0(n_with_result, "/", n_runs),
      correct = paste0(n_correct, "/", n_runs),
      avg_duration = round(total_duration / max(n_runs, 1), 1),
      avg_tool_calls = round(total_tool_calls / max(n_runs, 1), 1),
      stringsAsFactors = FALSE
    )

    cat(trial_name, ": ", n_runs, " runs, ",
        n_with_result, "/", n_runs, " with result, ",
        n_correct, "/", n_runs, " correct\n", sep = "")
  }

  cat("\n")

  do.call(rbind, results)
}


# ==============================================================================
# SKILLS SYSTEM
# ==============================================================================
#
# Load and inject skills into system prompts.
# Skills are markdown files in .blockr/skills/{name}/SKILL.md
#

# --- Load skills from directory ---
#
# Reads all SKILL.md files and extracts content (without YAML frontmatter)
#
load_skills <- function(skills_dir = ".blockr/skills") {

  if (!dir.exists(skills_dir)) {
    return(list())
  }

  skill_dirs <- list.dirs(skills_dir, recursive = FALSE, full.names = TRUE)

  skills <- list()
  for (dir in skill_dirs) {
    skill_file <- file.path(dir, "SKILL.md")
    if (file.exists(skill_file)) {
      content <- paste(readLines(skill_file, warn = FALSE), collapse = "\n")

      # Extract name from frontmatter
      name_match <- regmatches(content, regexpr("name:\\s*([a-z0-9-]+)", content))
      name <- if (length(name_match) > 0) {
        gsub("name:\\s*", "", name_match)
      } else {
        basename(dir)
      }

      # Remove YAML frontmatter for injection
      content_clean <- sub("^---.*?---\\s*", "", content, perl = TRUE)

      skills[[name]] <- list(
        name = name,
        path = skill_file,
        content = content_clean
      )

      cat("  Loaded skill:", name, "\n")
    }
  }

  skills
}


# --- Inject skills into system prompt ---
#
inject_skills <- function(base_prompt, skills) {

  if (length(skills) == 0) {
    return(base_prompt)
  }

  skill_content <- paste(
    sapply(skills, function(s) {
      paste0("## Skill: ", s$name, "\n\n", s$content)
    }),
    collapse = "\n\n---\n\n"
  )

  skill_section <- paste0(
    "\n\n",
    "# Reference Skills\n\n",
    "Follow these patterns carefully when they apply to the task:\n\n",
    skill_content
  )

  paste0(base_prompt, skill_section)
}


# --- Detect skill usage in generated code ---
#
# Checks if generated code follows skill patterns
#
detect_skill_usage <- function(code, skill_name = NULL) {

  if (is.null(code) || nchar(code) == 0) {
    return(NULL)
  }

  # Define patterns for each skill
  patterns <- list(
    "time-series-lag" = list(
      "group_before_lag" = "group_by\\s*\\([^)]+\\).*lag\\s*\\(",
      "arrange_first" = "arrange\\s*\\([^)]+\\).*group_by|arrange\\s*\\([^)]+\\).*lag",
      "ungroup_after" = "ungroup\\s*\\(\\)",
      "na_handling" = "coalesce|if_else.*is\\.na|replace_na|is\\.na.*0",
      "case_when_growth" = "case_when"
    ),
    "pivot-table" = list(
      "tidyr_pivot" = "tidyr::pivot_wider",
      "values_fill" = "values_fill",
      "backtick_cols" = "`[0-9]+`"
    ),
    "percentage-calc" = list(
      "round_pct" = "round\\s*\\([^,]+,\\s*[0-9]+\\)",
      "division_safe" = "if_else.*==\\s*0|coalesce"
    )
  )

  # If specific skill requested, only check that one
  if (!is.null(skill_name)) {
    skill_patterns <- patterns[[skill_name]]
    if (is.null(skill_patterns)) return(NULL)
    patterns <- list()
    patterns[[skill_name]] <- skill_patterns
  }

  # Check all patterns
  results <- list()
  for (skill in names(patterns)) {
    skill_patterns <- patterns[[skill]]

    matches <- sapply(skill_patterns, function(pattern) {
      grepl(pattern, code, perl = TRUE, ignore.case = TRUE)
    })

    results[[skill]] <- list(
      patterns = as.list(matches),
      matched = sum(matches),
      total = length(matches),
      usage_score = round(sum(matches) / length(matches), 2)
    )
  }

  results
}


# --- Run with skills variant ---
#
# Same as run_llm_ellmer_with_preview_and_validation but with skills injected
#
run_llm_ellmer_with_skills <- function(prompt, data, config,
                                        skills_dir = ".blockr/skills",
                                        max_validation_retries = 3) {

  cat("\n")
  cat(strrep("=", 60), "\n")
  cat("RUN: ellmer direct (preview + validation + SKILLS)\n")
  cat(strrep("=", 60), "\n\n")

  start <- Sys.time()

  if (is.data.frame(data)) {
    datasets <- list(data = data)
  } else {
    datasets <- data
  }

  # Load skills
  cat("Loading skills from:", skills_dir, "\n")
  skills <- load_skills(skills_dir)
  skills_injected <- names(skills)
  cat("  Skills loaded:", length(skills), "\n\n")

  cat("Creating proxy...\n")
  proxy <- structure(
    list(messages = list(), code = character()),
    class = c("llm_transform_block_proxy", "llm_block_proxy")
  )

  # Use preview eval_tool
  cat("Creating tools (with result preview)...\n")
  tools <- list(
    new_eval_tool_with_result(proxy, datasets),
    new_data_tool(proxy, datasets)
  )
  cat("  Tools:", paste(sapply(tools, function(t) t$tool@name), collapse = ", "), "\n")

  cat("Building system prompt...\n")
  sys_prompt <- system_prompt(proxy, datasets, tools)
  cat("  Base length:", nchar(sys_prompt), "chars\n")

  # Inject skills into system prompt
  sys_prompt <- inject_skills(sys_prompt, skills)
  cat("  With skills:", nchar(sys_prompt), "chars\n")

  cat("Creating LLM client...\n")
  client <- config$chat_fn()

  client$set_system_prompt(sys_prompt)
  client$set_tools(lapply(tools, get_tool))

  cat("\n")
  cat(strrep("-", 60), "\n")
  cat("Calling LLM (synchronous)...\n")
  cat(strrep("-", 60), "\n\n")

  error <- NULL
  response <- tryCatch(
    client$chat(prompt),
    error = function(e) {
      error <<- conditionMessage(e)
      NULL
    }
  )

  # Helper to extract code and result
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

  # Check initial result
  extracted <- extract_result()
  code <- extracted$code
  result <- extracted$result

  # Validation loop
  validation_attempt <- 0
  while (!is.data.frame(result) && validation_attempt < max_validation_retries) {
    validation_attempt <- validation_attempt + 1

    cat("\n")
    cat(strrep("-", 60), "\n")
    cat("VALIDATION RETRY ", validation_attempt, "/", max_validation_retries, "\n", sep = "")
    cat("Result is not a valid data.frame. Asking LLM to fix...\n")
    cat(strrep("-", 60), "\n\n")

    retry_msg <- if (is.null(code) || nchar(code) == 0) {
      "You haven't validated your code with eval_tool yet. Please call eval_tool with your R code to complete the task. The code must produce a data.frame as output."
    } else {
      "The code did not produce a valid data.frame result. Please check the result preview and fix the code, then call eval_tool again."
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

  cat("\n")
  cat(strrep("-", 60), "\n")
  cat("LLM finished in", round(duration, 1), "seconds\n")
  if (validation_attempt > 0) {
    cat("  (", validation_attempt, " validation retries)\n", sep = "")
  }
  cat(strrep("-", 60), "\n")

  if (is.data.frame(result)) {
    cat("  Final result: data.frame with", nrow(result), "rows\n")
  } else {
    cat("  Final result: NOT a valid data.frame\n")
  }

  # Detect skill usage in generated code
  skill_usage <- detect_skill_usage(code)

  list(
    code = code,
    result = result,
    response = response,
    turns = client$get_turns(),
    duration_secs = duration,
    error = error,
    config = config,
    prompt = prompt,
    validation_retries = validation_attempt,
    variant = "with_skills",
    skills_injected = skills_injected,
    skill_usage = skill_usage
  )
}


# =============================================================================
# PROGRESSIVE DISCLOSURE SKILLS (Claude Code style)
# =============================================================================
#
# Instead of injecting all skill content into the system prompt,
# we provide a catalog (names + descriptions) and a skill_tool
# that the LLM can call to retrieve full skill content on demand.
#


# --- Load skill catalog (names + descriptions only) ---
#
# Returns a lightweight catalog for the system prompt
#
load_skill_catalog <- function(skills_dir = ".blockr/skills") {

  if (!dir.exists(skills_dir)) {
    return(list())
  }

  skill_dirs <- list.dirs(skills_dir, recursive = FALSE, full.names = TRUE)

  catalog <- list()
  for (dir in skill_dirs) {
    skill_file <- file.path(dir, "SKILL.md")
    if (file.exists(skill_file)) {
      content <- paste(readLines(skill_file, warn = FALSE), collapse = "\n")

      # Extract name from frontmatter
      name_match <- regmatches(content, regexpr("name:\\s*([a-z0-9-]+)", content))
      name <- if (length(name_match) > 0) {
        gsub("name:\\s*", "", name_match)
      } else {
        basename(dir)
      }

      # Extract description from frontmatter
      desc_match <- regmatches(content, regexpr("description:\\s*[^\n]+", content))
      description <- if (length(desc_match) > 0) {
        gsub("description:\\s*", "", desc_match)
      } else {
        paste("Skill for", name)
      }

      catalog[[name]] <- list(
        name = name,
        description = description
      )
    }
  }

  catalog
}


# --- Inject skill catalog into system prompt ---
#
# Adds just the skill names and descriptions (not full content)
#
inject_skill_catalog <- function(base_prompt, catalog) {

  if (length(catalog) == 0) {
    return(base_prompt)
  }

  catalog_text <- paste(
    sapply(catalog, function(s) {
      paste0("- **", s$name, "**: ", s$description)
    }),
    collapse = "\n"
  )

  catalog_section <- paste0(
    "\n\n",
    "# Available Skills\n\n",
    "You have access to coding pattern skills. ",
    "When you encounter a task that matches a skill, call `skill_tool(name)` ",
    "to get detailed instructions BEFORE writing code.\n\n",
    catalog_text, "\n\n",
    "Call skill_tool with the skill name to get full instructions."
  )

  paste0(base_prompt, catalog_section)
}


# --- Create skill_tool for on-demand retrieval ---
#
# Returns an ellmer tool that retrieves full skill content
#
new_skill_tool <- function(skills) {

  # Track which skills were called
  skills_called <- character()

  tool_fn <- function(skill_name) {
    # Record that this skill was requested
    skills_called <<- c(skills_called, skill_name)

    if (!skill_name %in% names(skills)) {
      return(paste0(
        "Unknown skill: '", skill_name, "'\n",
        "Available skills: ", paste(names(skills), collapse = ", ")
      ))
    }

    skill <- skills[[skill_name]]
    paste0(
      "# Skill: ", skill$name, "\n\n",
      skill$content, "\n\n",
      "---\n",
      "Apply this pattern to complete your task. ",
      "Remember to use eval_tool to validate your code."
    )
  }

  # Create the tool
  tool_obj <- list(
    tool = ellmer::tool(
      tool_fn,
      name = "skill_tool",
      description = paste0(
        "Get detailed instructions for a coding pattern skill. ",
        "Call this BEFORE writing code when the task matches a skill description. ",
        "Returns markdown instructions with correct patterns and common mistakes to avoid."
      ),
      skill_name = ellmer::type_string(
        "The name of the skill to retrieve (e.g., 'rowwise-sum', 'pivot-table')"
      )
    ),
    get_skills_called = function() skills_called
  )

  tool_obj
}


# --- Run with skill_tool (progressive disclosure) ---
#
# LLM sees skill catalog in prompt, can call skill_tool to get full content
#
# =============================================================================
# DETERMINISTIC LOOP (Variant E)
# =============================================================================
#
# System-controlled flow without tool calling:
# 1. Show data preview upfront
# 2. LLM writes code as plain text
# 3. System runs code deterministically
# 4. On error: show error, iterate
# 5. On success: show result, LLM reviews
# 6. LLM says DONE or provides fixed code
#

run_llm_deterministic_loop <- function(prompt, data, config,
                                        max_iterations = 5) {

  cat("\n")
  cat(strrep("=", 60), "\n")
  cat("RUN: deterministic loop (no tools)\n")
  cat(strrep("=", 60), "\n\n")

  start <- Sys.time()

  if (is.data.frame(data)) {
    datasets <- list(data = data)
  } else {
    datasets <- data
  }

  # Create data preview
  data_preview <- paste(
    sapply(names(datasets), function(nm) {
      d <- datasets[[nm]]
      preview_lines <- utils::capture.output(print(utils::head(d, 5)))
      paste0(
        "## Dataset: ", nm, "\n",
        "Dimensions: ", nrow(d), " rows x ", ncol(d), " cols\n",
        "Columns: ", paste(names(d), collapse = ", "), "\n\n",
        "```\n",
        paste(preview_lines, collapse = "\n"),
        "\n```"
      )
    }),
    collapse = "\n\n"
  )

  # System prompt for deterministic loop
  sys_prompt <- paste0(
    "You are an R code assistant. You write dplyr code to transform data.\n\n",
    "IMPORTANT RULES:\n",
    "1. Always prefix dplyr functions: dplyr::filter(), dplyr::mutate(), etc.\n",
    "2. Always prefix tidyr functions: tidyr::pivot_wider(), etc.\n",
    "3. Use the native pipe |> (not %>%)\n",
    "4. Your code must start with a dataset name and produce a data.frame\n",
    "5. Wrap your R code in ```r ... ``` markdown blocks\n\n",
    "When you see the result of your code:\n",
    "- If it's correct, respond with just: DONE\n",
    "- If it needs fixing, provide corrected code in ```r ... ``` blocks\n"
  )

  cat("Creating LLM client...\n")
  client <- config$chat_fn()
  client$set_system_prompt(sys_prompt)

  # Build initial message with data preview
  initial_msg <- paste0(
    "# Data Available\n\n",
    data_preview,
    "\n\n# Task\n\n",
    prompt,
    "\n\nWrite R code to complete this task. Wrap your code in ```r ... ``` blocks."
  )

  cat("Data preview length:", nchar(data_preview), "chars\n")
  cat("\n")
  cat(strrep("-", 60), "\n")
  cat("Starting deterministic loop...\n")
  cat(strrep("-", 60), "\n\n")

  # Track state
  final_code <- NULL
  final_result <- NULL
  iteration <- 0
  error <- NULL
  all_messages <- list()

  # Helper to extract code from markdown
  extract_code_from_markdown <- function(text) {
    # Match ```r ... ``` or ```R ... ``` blocks
    pattern <- "```[rR]\\s*\\n([\\s\\S]*?)\\n```"
    matches <- regmatches(text, gregexpr(pattern, text, perl = TRUE))[[1]]

    if (length(matches) == 0) {
      # Try without language specifier
      pattern <- "```\\s*\\n([\\s\\S]*?)\\n```"
      matches <- regmatches(text, gregexpr(pattern, text, perl = TRUE))[[1]]
    }

    if (length(matches) == 0) {
      return(NULL)
    }

    # Extract content from last code block
    last_block <- matches[length(matches)]
    code <- sub("```[rR]?\\s*\\n", "", last_block)
    code <- sub("\\n```$", "", code)
    trimws(code)
  }

  # Main loop
  current_msg <- initial_msg

  while (iteration < max_iterations) {
    iteration <- iteration + 1

    cat("Iteration ", iteration, "/", max_iterations, "\n", sep = "")

    # Get LLM response
    response <- tryCatch(
      client$chat(current_msg),
      error = function(e) {
        error <<- conditionMessage(e)
        NULL
      }
    )

    if (is.null(response)) {
      cat("  LLM error:", error, "\n")
      break
    }

    all_messages <- c(all_messages, list(list(role = "user", content = current_msg)))
    all_messages <- c(all_messages, list(list(role = "assistant", content = response)))

    # Check for DONE
    if (grepl("^\\s*DONE\\s*$", response, ignore.case = TRUE) ||
        grepl("\\bDONE\\b", response) && !grepl("```", response)) {
      cat("  LLM said DONE\n")
      break
    }

    # Extract code
    code <- extract_code_from_markdown(response)

    if (is.null(code) || nchar(trimws(code)) == 0) {
      cat("  No code found in response\n")
      current_msg <- "I couldn't find any R code in your response. Please provide the code wrapped in ```r ... ``` blocks."
      next
    }

    cat("  Code extracted (", nchar(code), " chars)\n", sep = "")

    # Run code
    env <- list2env(datasets, parent = baseenv())
    result <- tryCatch(
      eval(parse(text = code), envir = env),
      error = function(e) {
        structure(conditionMessage(e), class = "eval_error")
      }
    )

    if (inherits(result, "eval_error")) {
      # Error - ask LLM to fix
      cat("  Error:", substr(result, 1, 60), "...\n")
      current_msg <- paste0(
        "Your code produced an error:\n\n",
        "```\n", result, "\n```\n\n",
        "Please fix the code and try again."
      )
    } else if (is.data.frame(result)) {
      # Success - show result and ask for confirmation
      final_code <- code
      final_result <- result

      result_preview <- paste(
        utils::capture.output(print(result)),
        collapse = "\n"
      )

      cat("  Success: data.frame with ", nrow(result), " rows\n", sep = "")

      current_msg <- paste0(
        "Your code executed successfully. Here is the result:\n\n",
        "```\n", result_preview, "\n```\n\n",
        "Does this look correct? If yes, respond with just: DONE\n",
        "If not, provide corrected code in ```r ... ``` blocks."
      )
    } else {
      # Not a data.frame
      cat("  Result is not a data.frame\n")
      current_msg <- paste0(
        "Your code ran but did not produce a data.frame. ",
        "The result was of class: ", class(result)[1], "\n\n",
        "Please fix the code to produce a data.frame as output."
      )
    }
  }

  duration <- as.numeric(difftime(Sys.time(), start, units = "secs"))

  cat("\n")
  cat(strrep("-", 60), "\n")
  cat("Deterministic loop finished in", round(duration, 1), "seconds\n")
  cat("  Iterations:", iteration, "\n")
  cat(strrep("-", 60), "\n")

  if (is.data.frame(final_result)) {
    cat("  Final result: data.frame with", nrow(final_result), "rows\n")
  } else {
    cat("  Final result: NOT a valid data.frame\n")
  }

  list(
    code = final_code,
    result = final_result,
    response = response,
    turns = client$get_turns(),
    duration_secs = duration,
    error = error,
    config = config,
    prompt = prompt,
    iterations = iteration,
    variant = "deterministic_loop"
  )
}


run_llm_ellmer_with_skill_tool <- function(prompt, data, config,
                                            skills_dir = ".blockr/skills",
                                            max_validation_retries = 3) {

  cat("\n")
  cat(strrep("=", 60), "\n")
  cat("RUN: ellmer direct (preview + validation + SKILL TOOL)\n")
  cat(strrep("=", 60), "\n\n")

  start <- Sys.time()

  if (is.data.frame(data)) {
    datasets <- list(data = data)
  } else {
    datasets <- data
  }

  # Load full skills (for skill_tool to return)
  cat("Loading skills from:", skills_dir, "\n")
  skills <- load_skills(skills_dir)
  cat("  Skills available:", length(skills), "\n")

  # Load catalog (just names + descriptions)
  catalog <- load_skill_catalog(skills_dir)
  cat("  Catalog entries:", length(catalog), "\n\n")

  cat("Creating proxy...\n")
  proxy <- structure(
    list(messages = list(), code = character()),
    class = c("llm_transform_block_proxy", "llm_block_proxy")
  )

  # Create skill_tool
  skill_tool_obj <- new_skill_tool(skills)

  # Use preview eval_tool
  cat("Creating tools (with skill_tool)...\n")
  tools <- list(
    new_eval_tool_with_result(proxy, datasets),
    new_data_tool(proxy, datasets),
    skill_tool_obj
  )
  cat("  Tools:", paste(c("eval_tool", "data_tool", "skill_tool"), collapse = ", "), "\n")

  cat("Building system prompt...\n")
  sys_prompt <- system_prompt(proxy, datasets, tools[1:2])  # Don't include skill_tool in base
  cat("  Base length:", nchar(sys_prompt), "chars\n")

  # Inject skill CATALOG (not full content)
  sys_prompt <- inject_skill_catalog(sys_prompt, catalog)
  cat("  With catalog:", nchar(sys_prompt), "chars\n")

  cat("Creating LLM client...\n")
  client <- config$chat_fn()

  client$set_system_prompt(sys_prompt)
  client$set_tools(list(
    get_tool(tools[[1]]),
    get_tool(tools[[2]]),
    skill_tool_obj$tool
  ))

  cat("\n")
  cat(strrep("-", 60), "\n")
  cat("Calling LLM (synchronous)...\n")
  cat(strrep("-", 60), "\n\n")

  error <- NULL
  response <- tryCatch(
    client$chat(prompt),
    error = function(e) {
      error <<- conditionMessage(e)
      NULL
    }
  )

  # Helper to extract code and result
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

  # Check initial result
  extracted <- extract_result()
  code <- extracted$code
  result <- extracted$result

  # Validation loop
  validation_attempt <- 0
  while (!is.data.frame(result) && validation_attempt < max_validation_retries) {
    validation_attempt <- validation_attempt + 1

    cat("\n")
    cat(strrep("-", 60), "\n")
    cat("VALIDATION RETRY ", validation_attempt, "/", max_validation_retries, "\n", sep = "")
    cat("Result is not a valid data.frame. Asking LLM to fix...\n")
    cat(strrep("-", 60), "\n\n")

    retry_msg <- if (is.null(code) || nchar(code) == 0) {
      "You haven't validated your code with eval_tool yet. Please call eval_tool with your R code to complete the task. The code must produce a data.frame as output."
    } else {
      "The code did not produce a valid data.frame result. Please check the result preview and fix the code, then call eval_tool again."
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

  # Get which skills were called
  skills_called <- skill_tool_obj$get_skills_called()

  cat("\n")
  cat(strrep("-", 60), "\n")
  cat("LLM finished in", round(duration, 1), "seconds\n")
  if (validation_attempt > 0) {
    cat("  (", validation_attempt, " validation retries)\n", sep = "")
  }
  cat("Skills called:", if (length(skills_called) > 0) paste(skills_called, collapse = ", ") else "(none)", "\n")
  cat(strrep("-", 60), "\n")

  if (is.data.frame(result)) {
    cat("  Final result: data.frame with", nrow(result), "rows\n")
  } else {
    cat("  Final result: NOT a valid data.frame\n")
  }

  # Detect skill usage in generated code
  skill_usage <- detect_skill_usage(code)

  list(
    code = code,
    result = result,
    response = response,
    turns = client$get_turns(),
    duration_secs = duration,
    error = error,
    config = config,
    prompt = prompt,
    validation_retries = validation_attempt,
    variant = "with_skill_tool",
    skills_available = names(skills),
    skills_called = skills_called,
    skill_usage = skill_usage
  )
}
