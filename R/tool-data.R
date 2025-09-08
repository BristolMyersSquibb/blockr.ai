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

    res <- evaluate::evaluate(
      code,
      envir = list2env(datasets, parent = baseenv())
    )

    prompt <- options(prompt = "> ")
    on.exit(options(prompt))

    utils::capture.output(evaluate::replay(res))
  }

  new_llm_tool(
    execute_r_code,
    description = paste(
      "In order to explore input datasets, you can run arbitrary R code",
      "in a context with the datasets available, bound to their respective",
      "names (", paste_enum(names(datasets)), "). You can use this tool up to",
      max_probes, "times. If the counter is exceeded, please report back any",
      "open questions you might have and await further user instruction."
    ),
    name = "data_tool",
    prompt = paste(
      "You may optionally use the \"data_tool\" to investigate input datasets.",
      "Please do not make excessive use of this tool but do use it in case you",
      "believe your answer might benefit from better understanding input data."
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
