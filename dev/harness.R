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
