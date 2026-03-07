library(shiny)
# pkgload::load_all("shinychat/pkg-r")

# install.packages("shinychat/pkg-r", repos = NULL, type = "source")
library(shinychat)
library(ellmer)

# Change the model here:
#   chat_openai(model = "gpt-4o-mini")  — cheap, good with images
#   chat_openai(model = "gpt-4o")       — best OpenAI vision
#   chat_anthropic()                     — Claude
chat <- chat_openai(
  model = "gpt-4o-mini",
  system_prompt = paste(
    "You are a helpful data analysis assistant.",
    "When the user shares an image, describe what you see in it and help them",
    "find or work with relevant datasets. For example, if they paste a photo of",
    "an animal, suggest R datasets or packages that contain data about that animal.",
    "Be helpful and specific. This is about data exploration, not person identification."
  )
)

ui <- bslib::page_fluid(
  tags$h3("Image Chat"),
  chat_ui("chat", placeholder = "Paste an image or type a message...")
)

server <- function(input, output, session) {
  observeEvent(input$chat_user_input, {
    raw <- input$chat_user_input

    # Parse structured input (with images) vs plain string
    if (is.list(raw)) {
      prompt <- raw$text %||% ""
      images <- raw$images
    } else {
      prompt <- raw
      images <- NULL
    }

    if (nchar(trimws(prompt)) == 0 && length(images) == 0) return()

    # Build content turns for ellmer
    if (!is.null(images) && length(images) > 0) {
      img_contents <- lapply(images, function(img) {
        ellmer::ContentImageInline(type = img$type, data = img$data)
      })
      # Stream response with text + images
      stream <- do.call(chat$stream_async, c(list(prompt), img_contents))
    } else {
      stream <- chat$stream_async(prompt)
    }

    shinychat::chat_append("chat", stream)
  })
}

shinyApp(ui, server)
