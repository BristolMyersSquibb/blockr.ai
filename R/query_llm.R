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
      "\n-------------------- system prompt --------------------\n",
      system_prompt,

      "\n-------------------- user prompt --------------------\n",
      user_prompt,
      "\n"
    )
  }

  # response -------------------------------------------------------------------
  chat <- chat_dispatch(system_prompt)
  response <- chat$extract_data(user_prompt, type = type_response())
  response
}

transform_system_prompt <- function(datasets) {
  make_metadata <- getOption("blockr.ai.make_meta_data", make_metadata_default)
  metadata <- make_metadata(datasets)
  paste(
    "You are a R programming assistant. You help users analyze datasets by generating R code.",
    "You will provide clear explanations and generate working R code.",
    "You have the following dataset(s) at my disposal:",
    toString(shQuote(names(datasets))),
    "These come with summaries or metadata given below along with a description:",
    shQuote(metadata$description, type = "cmd"),
    "",
    "```{r}",
    paste(constructive::construct_multi(metadata$summaries)$code, collapse = "\n"),
    "```",
    "",
    "You'll be very careful to use the provided names in your explanations and code.",
    "This means you will never use generic names of undefined datasets like `x`",
    "Or `data` unless these are explicitly provided.",
    "You'll Never produce code to rebuild the input objects.",
    "Important: Your code must always return a dataframe as the last expression.",
    "\nExamples of good code You might write:",
    "1. Direct transformation:",
    "data %>%",
    "  group_by(category) %>%",
    "  summarize(mean_value = mean(value))",
    "\n2. With intermediate steps:",
    "result <- data %>%",
    "  filter(value > 0)",
    "result %>% group_by(group) %>%",
    "  summarize(total = sum(value))",
    "\nI avoid these mistakes:",
    "# Assigning without returning:",
    "result <- data %>% summarize(...)",
    "# Printing instead of returning:",
    "print(data %>% summarize(...))",
    "\nYou always ensure your code returns a dataframe.",
    sep = "\n"
  )
}

plot_system_prompt <- function(datasets) {
  make_metadata <- getOption("blockr.ai.make_meta_data", make_metadata_default)
  metadata <- make_metadata(datasets)
  paste(
    "You are a R programming assistant. You help users analyze datasets by generating R code.",
    "You will provide clear explanations and generate working R code.",
    "You have the following dataset(s) at my disposal:",
    toString(shQuote(names(datasets))),
    "These come with summaries or metadata given below along with a description:",
    shQuote(metadata$description, type = "cmd"),
    "",
    "```{r}",
    paste(constructive::construct_multi(metadata$summaries)$code, collapse = "\n"),
    "```",
    "",
    "You'll be very careful to use the provided names in your explanations and code.",
    "This means you will never use generic names of undefined datasets like `x`",
    "Or `data` unless these are explicitly provided.",
    "You'll Never produce code to rebuild the input objects.",
    "Important: Your code must always return a ggplot2 plot object as the last expression.",
    "\nExamples of good code you might write:",
    " ggplot(data) + ",
    "   geom_point(aes(x = displ, y = hwy)) +",
    "   facet_wrap(~ class, nrow = 2)",
    sep = "\n"
  )
}
