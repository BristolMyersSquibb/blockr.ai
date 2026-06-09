new_data_tool <- function(x, datasets,
                          max_probes = blockr_option("max_data_probes", 5L),
                          ...) {

  invocation_count <- 0
  total_probes <- 0L

  execute_r_code <- function(code) {

    invocation_count <<- invocation_count + 1
    total_probes <<- total_probes + 1L

    code <- paste(code, collapse = "\n")

    log_info(
      "Probing data (run ", invocation_count, "/", max_probes,
      "):\n", code
    )

    if (invocation_count > max_probes) {

      log_warn("Maximum attempts (", max_probes, ") exceeded")

      invocation_count <<- 0

      ellmer::tool_reject(
        paste0(
          "Maximum number of attempts (", max_probes, ") exceeded. ",
          "Stop using this tool and await further user instructions."
        )
      )
    }

    res <- evaluate::evaluate(code, eval_env(datasets))

    prompt <- options(prompt = "> ")
    on.exit(options(prompt))

    utils::capture.output(evaluate::replay(res))
  }

  tool <- new_llm_tool(
    execute_r_code,
    description = paste(
      "Run arbitrary R code to explore input datasets. Datasets are available",
      "by name:", paste_enum(names(datasets)), ". You can use this tool up to",
      max_probes, "times."
    ),
    name = "data_tool",
    prompt = paste0(
      data_exploration_preamble(), "\n\n",
      "Use the \"data_tool\" to run R code that refers to datasets by name: ",
      paste_enum(names(datasets)), ". You can use this tool up to ",
      max_probes, " times."
    ),
    arguments = list(
      code = ellmer::type_string(
        paste0(
          "R code to evaluate in an environment where input dataset are ",
          "available as ", paste_enum(names(datasets)), ".")
      )
    )
  )

  tool$probes_used <- function() total_probes

  tool
}


#' Shared preamble for the data-exploration tool prompt.
#' @return Character string.
#' @noRd
data_exploration_preamble <- function() {
  paste0(
    "DATA EXPLORATION:\n",
    "You have a data exploration capability that lets you run R code against ",
    "the input data before answering. Use it to inspect column names, data ",
    "types, value ranges, unique levels, or anything else you need to ",
    "understand the data well enough to configure this block correctly.\n\n",
    "If the 5-row preview already contains the information you need, go ahead ",
    "and answer directly -- exploration is not required for every task.\n\n",
    "IMPORTANT: keep probes SMALL and TARGETED. Query only the specific ",
    "columns you need (e.g. 5-8 columns at a time, not 20). If a probe result ",
    "looks truncated, your next action MUST be either another, more targeted ",
    "data probe (fewer columns, fewer rows), or applying a configuration with ",
    "`validate_config`. Do not output a plain-text complaint about truncation ",
    "-- act on it."
  )
}
