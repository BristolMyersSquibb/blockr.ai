#' Data exploration backend
#'
#' Creates a backend that controls how the LLM can explore input data
#' during block argument discovery.
#'
#' @param type Backend type: `"none"` (default, no exploration), `"manual"`
#'   (LLM requests R code execution via tagged code blocks), or `"tools"`
#'   (ellmer native tool calling). Also accepts a backend list directly
#'   for custom backends.
#' @param ... Passed to backend constructor (e.g. `max_probes`, `structured`).
#' @return A list with `setup(client, data)`, `process(response, data)`,
#'   and `probes_used()`.
#' @export
data_exploration_backend <- function(type = c("none", "manual", "tools"), ...) {
  if (is.list(type)) return(type)
  type <- match.arg(type)
  switch(type,
    none = data_backend_none(),
    manual = data_backend_manual(...),
    tools = data_backend_tools(...)
  )
}


data_backend_none <- function() {
  list(
    setup = function(client, data) NULL,
    process = function(response, data) NULL,
    probes_used = function() 0L
  )
}


data_backend_manual <- function(
    max_probes = blockr.core::blockr_option("max_data_probes", 3L),
    structured = FALSE
) {
  probe_count <- 0L

  if (structured) {
    manual_backend_structured(max_probes, probe_count_env = environment())
  } else {
    manual_backend_unstructured(max_probes, probe_count_env = environment())
  }
}


# Shared: execute R code against datasets and return captured output
execute_data_query <- function(code, data, probe_count, max_probes) {
  datasets <- normalize_datasets(data)
  result <- tryCatch({
    res <- evaluate::evaluate(code, blockr.core::eval_env(datasets))
    old_prompt <- getOption("prompt")
    options(prompt = "> ")
    on.exit(options(prompt = old_prompt))
    paste(utils::capture.output(evaluate::replay(res)), collapse = "\n")
  }, error = function(e) {
    paste0("Error: ", conditionMessage(e))
  })

  if (nchar(result) > 3000L) {
    result <- paste0(substr(result, 1, 3000), "\n... (truncated)")
  }

  message("[discover] data probe ", probe_count, "/", max_probes, ": ",
          truncate_for_log(code))

  remaining <- max_probes - probe_count
  paste0(
    "Data exploration result:\n```\n",
    result,
    "\n```\n\n",
    if (remaining > 0L) {
      paste0("Now provide your JSON answer, or explore further (",
             remaining, " remaining).")
    } else {
      "Now provide your JSON answer."
    }
  )
}


#' Shared preamble for data exploration prompts
#' @return Character string
#' @noRd
data_exploration_preamble <- function() {
  paste0(
    "DATA EXPLORATION:\n",
    "You have a data exploration capability that lets you run R code against ",
    "the input data before answering. Use it to inspect column names, data ",
    "types, value ranges, unique levels, or anything else you need to ",
    "understand the data well enough to configure this block correctly.\n\n",
    "If the 5-row preview already contains the information you need, ",
    "go ahead and answer directly -- exploration is not required for every task."
  )
}


# --- Unstructured: detect ```data_query``` tagged code blocks ---

manual_backend_unstructured <- function(max_probes, probe_count_env) {

  setup <- function(client, data) {
    datasets <- normalize_datasets(data)
    dataset_names <- paste(names(datasets), collapse = ", ")

    paste0(
      "\n\n", data_exploration_preamble(), "\n\n",
      "To explore, briefly explain what you need to find, then write an R code ",
      "block tagged `data_query`:\n",
      "```data_query\n",
      "str(", names(datasets)[1], ")\n",
      "```\n",
      "The code runs in an environment where ", dataset_names, " ",
      if (length(datasets) == 1L) "is" else "are",
      " available. You can do this up to ", max_probes, " times.\n",
      "When you have enough information, provide your JSON answer as usual.\n"
    )
  }

  process <- function(response, data) {
    code <- extract_data_query(response)
    if (is.null(code)) return(NULL)

    probe_count_env$probe_count <- probe_count_env$probe_count + 1L
    pc <- probe_count_env$probe_count

    if (pc > max_probes) {
      return(paste0(
        "Maximum data exploration rounds (", max_probes, ") reached. ",
        "Please provide your JSON answer based on what you've seen so far."
      ))
    }

    execute_data_query(code, data, pc, max_probes)
  }

  list(
    setup = setup,
    process = process,
    probes_used = function() probe_count_env$probe_count
  )
}


# --- Structured: LLM uses JSON envelope {"action":"explore","code":"..."} ---

manual_backend_structured <- function(max_probes, probe_count_env) {

  setup <- function(client, data) {
    datasets <- normalize_datasets(data)
    dataset_names <- paste(names(datasets), collapse = ", ")

    paste0(
      "\n\n", data_exploration_preamble(), "\n\n",
      "To explore, respond with a JSON code block containing an explore action:\n",
      "```json\n",
      "{\"action\": \"explore\", \"code\": \"str(", names(datasets)[1], ")\", ",
      "\"explanation\": \"what you need to find\"}\n",
      "```\n",
      "The code runs in an environment where ", dataset_names, " ",
      if (length(datasets) == 1L) "is" else "are",
      " available. You can explore up to ", max_probes, " times.\n",
      "When you have enough information, provide your JSON answer in a ",
      "`json` code block as usual (without an \"action\" field).\n"
    )
  }

  process <- function(response, data) {
    json_str <- extract_json(response)
    if (is.null(json_str)) return(NULL)

    parsed <- tryCatch(
      jsonlite::fromJSON(json_str, simplifyVector = FALSE),
      error = function(e) NULL
    )
    if (is.null(parsed)) return(NULL)

    # Only handle exploration requests; answer JSON (no action field) falls
    # through to the main loop's extract_json() + validation.
    if (!identical(parsed$action, "explore")) return(NULL)

    code <- parsed$code
    if (is.null(code) || !nzchar(trimws(code))) return(NULL)

    probe_count_env$probe_count <- probe_count_env$probe_count + 1L
    pc <- probe_count_env$probe_count

    if (pc > max_probes) {
      return(paste0(
        "Maximum data exploration rounds (", max_probes, ") reached. ",
        "Please provide your JSON answer based on what you've seen so far."
      ))
    }

    execute_data_query(code, data, pc, max_probes)
  }

  list(
    setup = setup,
    process = process,
    probes_used = function() probe_count_env$probe_count
  )
}


data_backend_tools <- function(
    max_probes = blockr.core::blockr_option("max_data_probes", 3L)
) {
  tool_ref <- NULL

  setup <- function(client, data) {
    datasets <- normalize_datasets(data)
    if (length(datasets) == 0L) return(NULL)

    tool <- new_data_tool(NULL, datasets, max_probes = max_probes)
    tool_ref <<- tool
    client$set_tools(list(get_tool(tool)))

    tool_prompt <- get_prompt(tool)
    if (length(tool_prompt) > 0L && any(nzchar(tool_prompt))) {
      paste0("\n\n", paste(tool_prompt, collapse = "\n"))
    }
  }

  list(
    setup = setup,
    process = function(response, data) NULL,
    probes_used = function() {
      if (is.null(tool_ref)) return(NA_integer_)
      tool_ref$probes_used()
    }
  )
}


#' Extract data_query code block from LLM response
#' @param text LLM response text
#' @return Code string, or NULL if no data_query block found
#' @noRd
extract_data_query <- function(text) {
  pattern <- "```data_query\\s*\\n([\\s\\S]*?)\\n```"
  matches <- regmatches(text, gregexpr(pattern, text, perl = TRUE))[[1]]
  if (length(matches) == 0L) return(NULL)

  last_block <- matches[length(matches)]
  code <- sub("```data_query\\s*\\n", "", last_block, perl = TRUE)
  code <- sub("\\n```$", "", code)
  trimws(code)
}
