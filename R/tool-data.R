new_data_tool <- function(x, datasets,
                          max_probes = blockr_option("max_data_probes", 5L),
                          ...) {

  invocation_count <- 0

  execute_r_code <- function(code) {

    invocation_count <<- invocation_count + 1

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

  new_llm_tool(
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
}
