# Function to query LLM
query_llm <- function(question, metadata, error = NULL) {
  # Create system message with examples
  system_msg <- paste(
    "I am an R programming assistant. I help users analyze datasets by generating R code.",
    "I will provide clear explanations in first person and generate working R code.",
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
