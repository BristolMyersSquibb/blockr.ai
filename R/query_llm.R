# Function to query LLM
query_llm <- function(question, metadata, error = NULL, plot = FALSE) {
  # Create system message with examples
  if (plot) {
    system_msg <- plot_system_message()
  } else {
    system_msg <- transform_system_message()
  }


  # Create user message
  user_msg <- paste(
    "Here are the datasets you can work with:",
    jsonlite::toJSON(metadata, auto_unbox = TRUE, pretty = TRUE),
    "\nYour question:", question,
    if (!is.null(error)) paste("\nMy previous code generated this error:", error) else ""
  )

  # Create chat instance with instructions
  chat <- chat_openai(
    system_prompt = system_msg,
    model = "gpt-4o"
  )

  # Get structured response
  response <- chat$extract_data(
    user_msg,
    type = type_response()
  )

  return(response)
}

transform_system_message <- function() {
  paste(
    "I am an R programming assistant. I help users analyze datasets by generating R code.",
    "I will provide clear explanations in first person and generate working R code.",
    "The user is expected to provide me with metadata about 1 or more input datasets.",
    "This metadata might contain the names of the datasets and I'll be very careful",
    "to use precisely those in my explanations and code.",
    "Never produce code to rebuild the input objects, instead assume that you",
    "have them at your disposal.",
    "Important: My code must always return a dataframe as the last expression.",
    "\nExamples of good code I might write:",
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
    "\nI always ensure my code returns a dataframe."
  )
}

plot_system_message <- function() {
  paste(
    "I am an R programming assistant. I help users analyze datasets by generating R code.",
    "I will provide clear explanations in first person and generate working R code.",
    "The user is expected to provide me with metadata about 1 or more input datasets.",
    "This metadata might contain the names of the datasets and I'll be very careful",
    "to use precisely those in my explanations and code.",
    "Never produce code to rebuild the input objects, instead assume that you",
    "have them at your disposal.",
    "Important: My code must always return a ggplot2 plot object as the last expression.",
    "\nExamples of good code I might write:",
    " ggplot(data) + ",
    "   geom_point(aes(x = displ, y = hwy)) +",
    "   facet_wrap(~ class, nrow = 2)",
    sep = "\n"
  )
}
