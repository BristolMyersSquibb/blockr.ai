# Function to query LLM
query_llm <- function(user_prompt, system_prompt, error = NULL, verbose = getOption("blockr.ai.verbose", TRUE)) {

  # user message ---------------------------------------------------------------
  if (!is.null(error)) {
    user_prompt <-
      paste(
        user_prompt,
        "\nIn another conversation your solution resulted in this error:",
        shQuote(error, type = "cmd"),
        "Be careful to provide a solution that doesn't reproduce this problem",
        sep = "\n"
      )
    }

  if (verbose) {
    cat(
      "\n-------------------- user prompt --------------------\n",
      user_prompt,
      "\n",
      sep = ""
    )
  }

  # response -------------------------------------------------------------------
  chat <- chat_dispatch(system_prompt)
  response <- chat$extract_data(user_prompt, type = type_response())

  if (verbose) {
    cat(
      "\n-------------------- response explanation -----------\n",
      response$explanation,
      "\n",
      "\n-------------------- response code ------------------\n",
      response$code,
      "\n",
      sep = ""
    )
  }

  response
}

general_system_prompt <- function() {
  paste0(
    "You are an R programming assistant.\n",
    "Your task is to produce working R code according to user instructions.\n",
    "In addition, you should provide clear explanations to accompany the ",
    "generated R code.\n",
    "If you call functions in packages, always use namespace prefixes.\n",
    "Do not use libarary calls for attaching package namespaces."
  )
}

input_system_prompt <- function(datasets) {

  build_metadata <- getOption(
    "blockr.ai.make_meta_data",
    build_metadata_default
  )

  metadata <- build_metadata(datasets)

  paste0(
    "You have the following dataset at your disposal:",
    shQuote(names(datasets)), ".\n",
    "These come with summaries or metadata given below along with a ",
    "description: ", shQuote(metadata$description, type = "cmd"), ".\n\n",
    "```{r}\n",
    paste(
      constructive::construct_multi(metadata$summaries)$code,
      collapse = "\n"
    ),
    "\n```\n\n",
    "Be very careful to use only the provided names in your explanations ",
    "and code.\n",
    "This means you should not use generic names of undefined datasets ",
    "like `x` or `data` unless these are explicitly provided.\n",
    "You should not produce code to rebuild the input objects.\n"
  )
}

transform_system_prompt <- function(datasets, verbose = NULL) {

  if (is.null(verbose)) {
    verbose <- getOption("blockr.ai.verbose", TRUE)
  }

  prompt <- paste0(
    general_system_prompt(),
    "\n\n",
    input_system_prompt(datasets),
    "\n\n",
    "Your task is to transform input datasets into a single output dataset.\n",
    "If possible, use dplyr for data transformations.\n",
    "Use the base R pipe and not the magrittr pipe to make nested function ",
    "calls more readable.\n\n",
    "Example of good code you might write:\n",
    "data |>\n",
    "  group_by(category) |>\n",
    "  summarize(mean_value = mean(value))\n\n",
    "Important: make sure that your code always returns a transformed ",
    "data.frame.\n"
  )

  if (verbose) {
    cat(
      "\n-------------------- system prompt --------------------\n",
      prompt,
      "\n",
      sep = ""
    )
  }

  prompt
}

plot_system_prompt <- function(datasets, verbose = NULL) {

  if (is.null(verbose)) {
    verbose <- getOption("blockr.ai.verbose", TRUE)
  }

  prompt <- paste0(
    general_system_prompt(),
    "\n\n",
    input_system_prompt(datasets),
    "\n\n",
    "Your task is to produce code to generate a data visualization using ",
    "the ggplot package.\n",
    "Example of good code you might write:\n",
    "ggplot(data) +\n",
    "  geom_point(aes(x = displ, y = hwy)) +\n",
    "  facet_wrap(~ class, nrow = 2)\n\n",
    "Important: Your code must always return a ggplot2 plot object as the ",
    "last expression.\n"
  )

  if (verbose) {
    cat(
      "\n-------------------- system prompt --------------------\n",
      prompt,
      "\n"
    )
  }

  prompt
}
