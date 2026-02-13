# LLM Utilities for AI Control Block

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


#' Check if LLM response indicates completion
#' @param response Character string from LLM
#' @return Logical
#' @noRd
is_done_response <- function(response) {
  grepl("^\\s*DONE\\s*$", response, ignore.case = TRUE) ||
    (grepl("\\bDONE\\b", response) && !grepl("```", response))
}


#' Extract JSON from markdown code blocks or raw text
#' @param text Character string containing markdown or raw JSON
#' @return Character string with JSON, or NULL if not found
#' @noRd
extract_json <- function(text) {
  # Try code block first
  pattern <- "```(?:json)?\\s*\\n([\\s\\S]*?)\\n```"
  matches <- regmatches(text, gregexpr(pattern, text, perl = TRUE))[[1]]

  if (length(matches) > 0) {
    last_block <- matches[length(matches)]
    json <- sub("```(?:json)?\\s*\\n", "", last_block, perl = TRUE)
    json <- sub("\\n```$", "", json)
    return(trimws(json))
  }

  # Try raw JSON (starts with {)
  if (grepl("^\\s*\\{", text)) {
    return(trimws(text))
  }

  NULL
}


#' Strip JSON code blocks and clean up LLM response for display
#'
#' Removes JSON code blocks, sentences that reference JSON/configuration
#' internals, and trailing LLM pleasantries (e.g. "Let me know if...").
#' The result is a clean explanation suitable for showing to end users.
#'
#' @param text Character string from LLM response
#' @return Trimmed explanation text (may be empty string)
#' @noRd
strip_json_block <- function(text) {
  # Remove ```json ... ``` blocks
  out <- gsub("```(?:json)?\\s*\\n[\\s\\S]*?\\n```", "", text, perl = TRUE)
  # Remove raw JSON objects (balanced braces)
  out <- remove_raw_json(out)
  # Split into sentences, drop those mentioning JSON or asking to confirm/let know
  sentences <- strsplit(out, "(?<=[.!?:])\\s*", perl = TRUE)[[1]]
  keep <- !grepl("\\bJSON\\b", sentences, ignore.case = TRUE) &
    !grepl("^(If (this|there|you)|Let me know)\\b", sentences, perl = TRUE) &
    !grepl("\\blet me know\\b", sentences, ignore.case = TRUE)
  out <- paste(trimws(sentences[keep]), collapse = " ")
  # Collapse multiple blank lines and trim
  out <- gsub("\n{3,}", "\n\n", out)
  trimws(out)
}


#' Remove raw JSON objects from text using balanced-brace matching
#' @param text Character string
#' @return Text with JSON objects removed
#' @noRd
remove_raw_json <- function(text) {
  # Walk through the string, tracking brace depth to find top-level { ... }
  chars <- strsplit(text, "")[[1]]
  n <- length(chars)
  if (n == 0) return(text)
  keep <- rep(TRUE, n)
  i <- 1L
  while (i <= n) {
    if (chars[i] == "{") {
      depth <- 1L
      start <- i
      i <- i + 1L
      while (i <= n && depth > 0L) {
        if (chars[i] == "{") depth <- depth + 1L
        else if (chars[i] == "}") depth <- depth - 1L
        i <- i + 1L
      }
      if (depth == 0L) {
        keep[start:(i - 1L)] <- FALSE
      }
    } else {
      i <- i + 1L
    }
  }
  paste(chars[keep], collapse = "")
}


#' Create input data preview for LLM prompt
#'
#' Handles all input types: NULL, single data.frame, named list (x, y),
#' or variadic list of data.frames.
#'
#' @param input The raw result from dat() - can be NULL, data.frame, or list
#' @return Character string with formatted preview section, or "" if no data
#' @noRd
data_preview <- function(input) {
  if (is.null(input)) {
    return("")
  }

  # Empty list = no input data (source block)
  if (is.list(input) && length(input) == 0) {
    return("")
  }

  body <- if (inherits(input, "dm")) {
    tbl_names <- names(input)
    previews <- vapply(tbl_names, function(nm) {
      paste0("## ", nm, "\n\n", format_df_preview(input[[nm]]))
    }, character(1))
    paste0("dm object with ", length(tbl_names), " tables:\n\n",
           paste(previews, collapse = "\n\n"))
  } else if (is.data.frame(input)) {
    format_df_preview(input)
  } else if (is.list(input) && length(input) > 0) {
    previews <- vapply(seq_along(input), function(i) {
      name <- names(input)[i] %||% paste0("Input ", i)
      item <- input[[i]]
      if (is.data.frame(item)) {
        paste0("## ", name, "\n\n", format_df_preview(item))
      } else {
        paste0("## ", name, "\n\n", "Non-dataframe object: ", class(item)[1])
      }
    }, character(1))
    paste(previews, collapse = "\n\n")
  } else {
    paste0("Unknown input type: ", class(input)[1])
  }

  paste0("# Input Data\n\n", body, "\n\n")
}


#' Format a single data.frame for preview
#' @noRd
format_df_preview <- function(df) {
  col_info <- vapply(df, function(x) {
    paste0(class(x)[1])
  }, character(1))
  cols <- paste0(names(df), " (", col_info, ")", collapse = ", ")

  header <- paste0(nrow(df), " rows x ", ncol(df), " cols: ", cols)

  # Add sample rows so the LLM can see actual values
  sample_text <- tryCatch({
    n_show <- min(5L, nrow(df))
    if (n_show == 0L) return(header)
    sample_df <- utils::head(df, n_show)
    lines <- utils::capture.output(print(sample_df, right = FALSE))
    paste0("\n\nFirst ", n_show, " rows:\n", paste(lines, collapse = "\n"))
  }, error = function(e) "")

  paste0(header, sample_text)
}


#' Truncate and collapse whitespace for log messages
#' @param x Character string
#' @param n Max characters (default 200)
#' @return Truncated single-line string
#' @noRd
truncate_for_log <- function(x, n = 200) {
  x <- gsub("\\s+", " ", x)
  if (nchar(x) <= n) x else paste0(substr(x, 1, n), "...")
}


#' Format current block state for LLM prompt
#' @param state Plain list of current parameter values, or NULL
#' @return Character string with formatted section, or "" if NULL/empty
#' @noRd
format_current_state <- function(state) {
  if (is.null(state) || length(state) == 0) return("")
  json <- jsonlite::toJSON(state, auto_unbox = TRUE, pretty = TRUE)
  paste0("# Current Configuration\n\n```json\n", json, "\n```\n\n")
}


#' Format a block result for LLM confirmation preview
#' @param result Block evaluation result (data.frame, dm, ggplot, or other)
#' @return Character string preview
#' @noRd
format_result_preview <- function(result) {
  if (inherits(result, "dm")) {
    tbl_names <- names(result)
    lines <- vapply(tbl_names, function(nm) {
      paste0(nm, ": ", nrow(result[[nm]]), " rows")
    }, character(1))
    paste(lines, collapse = "\n")
  } else if (inherits(result, "ggplot")) {
    "Plot created successfully"
  } else if (is.data.frame(result)) {
    paste(utils::capture.output(print(utils::head(result, 3))), collapse = "\n")
  } else {
    paste0(class(result)[1], " object")
  }
}


#' Build system prompt for block argument discovery
#' @param var_names Names of controllable variables
#' @param block Block object for context
#' @return Character string with system prompt
#' @noRd
build_system_prompt <- function(var_names, block) {
  block_name <- class(block)[1]

  # Get registry info for richer context
  reg_info <- get_block_registry_info(block_name)

  block_context <- if (!is.null(reg_info$description)) {
    paste0(
      "You are configuring a ", reg_info$name, " (", block_name, ").\n",
      reg_info$description, "\n\n"
    )
  } else {
    paste0("You are configuring a ", block_name, ".\n\n")
  }

  param_docs_raw <- get_block_param_docs_raw(block_name)
  param_text <- if (!is.null(param_docs_raw)) {
    paste0(paste0(names(param_docs_raw), ": ", param_docs_raw, collapse = "\n"), "\n\n")
  } else {
    ""
  }

  block_prompt <- if (!is.null(param_docs_raw)) {
    p <- attr(param_docs_raw, "prompt")
    if (!is.null(p)) paste0(p, "\n\n") else ""
  } else {
    ""
  }

  # Include available helper functions from options (e.g. blockr.topline sets these)
  helper_fns <- getOption("blockr.dplyr.summary_functions")
  helper_text <- if (!is.null(helper_fns) && length(helper_fns) > 0) {
    fn_lines <- paste0("  ", names(helper_fns), ": ", helper_fns, collapse = "\n")
    paste0("Available helper functions:\n", fn_lines, "\n\n")
  } else {
    ""
  }

  example <- generate_example_json(param_docs_raw)
  example_text <- if (!is.null(example)) {
    paste0("Example:\n```json\n", example, "\n```\n\n")
  } else {
    paste0("Return JSON like: {\"", var_names[1], "\": <value>}\n\n")
  }

  ask_back_instructions <- paste0(
    "IMPORTANT:\n",
    "- If the user's request is vague or ambiguous (e.g. 'make it better', ",
    "'fix it', 'clean up', 'summarize the data'), do NOT guess. ",
    "Ask a specific clarifying question instead.\n",
    "- If the request is directional but not fully specified (e.g. 'make the font bigger', ",
    "'reduce the rows'), you MAY pick a reasonable value and return JSON. ",
    "Only ask back when the request is truly unclear about WHAT to do.\n",
    "- If the user asks for something this block CANNOT do (e.g. filtering in a formatting block, ",
    "or adding columns in a display block), explain the limitation clearly and suggest which ",
    "block type would be appropriate. Do NOT return JSON for impossible operations.\n",
    "- Only set parameters the user asked about. Leave other parameters at their defaults ",
    "unless you need to set them for the requested change to work.\n\n"
  )

  paste0(
    block_context,
    "Return JSON with parameter values.\n\n",
    "Parameters: ", paste(var_names, collapse = ", "), "\n\n",
    param_text,
    block_prompt,
    helper_text,
    ask_back_instructions,
    example_text,
    "After seeing the result, respond with just DONE if correct, or provide fixed JSON."
  )
}


#' Get registry info for a block type
#' @param block_name Name of the block class
#' @return List with name, description, category (or NULLs if not found)
#' @noRd
get_block_registry_info <- function(block_name) {
  reg <- tryCatch(
    blockr.core:::block_registry,
    error = function(e) NULL
  )

  if (is.null(reg)) {
    return(list(name = NULL, description = NULL, category = NULL))
  }

  entry <- tryCatch(
    get(block_name, envir = reg, inherits = FALSE),
    error = function(e) NULL
  )

  if (is.null(entry)) {
    return(list(name = NULL, description = NULL, category = NULL))
  }

  list(
    name = attr(entry, "name"),
    description = attr(entry, "description"),
    category = attr(entry, "category")
  )
}


#' Get raw parameter documentation vector for a block type
#'
#' Returns the named character vector from the registry with attributes intact,
#' so that `generate_example_json()` can extract `example` attributes.
#'
#' @param block_name Name of the block
#' @return Named character vector (with attributes) or NULL
#' @noRd
get_block_param_docs_raw <- function(block_name) {
  args <- tryCatch(
    blockr.core::registry_metadata(block_name, "arguments"),
    error = function(e) NULL
  )
  # registry_metadata returns list(value) for list-type fields
  if (is.list(args) && length(args) == 1L) args <- args[[1L]]
  if (is.null(args) || length(args) == 0 || is.null(names(args))) {
    return(NULL)
  }
  args
}


#' Generate example JSON from argument attributes
#'
#' Reads the `examples` attribute (a named list of R values) from the arguments
#' vector and converts it to a JSON string via `jsonlite::toJSON()`.
#'
#' @param args Named character vector or list with an `examples` attribute
#'   containing a named list of R values (e.g. `list(columns = list("mpg", "cyl"),
#'   exclude = FALSE)`).
#' @return A JSON object string, or NULL if no examples found
#' @noRd
generate_example_json <- function(args) {
  if (is.null(args)) return(NULL)
  examples <- attr(args, "examples")
  if (is.null(examples)) return(NULL)
  jsonlite::toJSON(examples, auto_unbox = TRUE, null = "null")
}
