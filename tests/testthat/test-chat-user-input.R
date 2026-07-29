# Wire shapes of `input$<id>_user_input`.
#
# The AI ctrl block reads shinychat's user-input directly instead of going
# through `chat_mod_server()`, so a change in what shinychat's
# `shinychat.userInput` handler returns lands here. It has changed once
# already: shinychat ad7d568 (posit-dev/shinychat#272) made the browser
# always send `{text, attachments, seq}`, so the handler returns a list of
# contents even when attachments are off. Reading `$text` off that gives
# NULL, the submit handler treats it as an empty prompt and returns without
# a word -- the chat sits on its typing dots forever.

test_that("bare string (shinychat <= e74ed26, attachments off)", {
  expect_equal(
    parse_chat_user_input("only setosa"),
    list(prompt = "only setosa", images = NULL)
  )
})

test_that("contents list (shinychat >= ad7d568)", {
  expect_equal(
    parse_chat_user_input(list("only setosa")),
    list(prompt = "only setosa", images = NULL)
  )
})

test_that("contents list of ellmer ContentText", {
  skip_if_not_installed("ellmer")

  expect_equal(
    parse_chat_user_input(list(ellmer::ContentText("only setosa"))),
    list(prompt = "only setosa", images = NULL)
  )
})

test_that("contents list keeps non-text content as images", {
  skip_if_not_installed("ellmer")

  img <- ellmer::ContentImageInline(type = "image/png", data = "abc")
  res <- parse_chat_user_input(list("what is this", img))

  expect_equal(res$prompt, "what is this")
  expect_length(res$images, 1L)
  expect_true(inherits(res$images[[1L]], "ellmer::Content"))
})

test_that("named list(text=, images=)", {
  res <- parse_chat_user_input(
    list(text = "what is this", images = list(list(type = "image/png", data = "abc")))
  )

  expect_equal(res$prompt, "what is this")
  expect_length(res$images, 1L)
})

test_that("empty and unusable input yield an empty prompt", {
  expect_equal(parse_chat_user_input(NULL), list(prompt = "", images = NULL))
  expect_equal(parse_chat_user_input(list()), list(prompt = "", images = NULL))
  expect_equal(parse_chat_user_input(42), list(prompt = "", images = NULL))
})

test_that("a submitted prompt reaches the harness through the observer", {
  # End-to-end through the module: the contents-list shape must produce an
  # actual discovery call, not a silent return.
  skip_if_not_installed("blockr.dplyr")

  seen <- NULL
  local_mocked_bindings(
    discover_block_args = function(prompt, ...) {
      seen <<- prompt
      list(success = TRUE, message = "ok", streamed = TRUE)
    }
  )

  block <- blockr.dplyr::new_select_block()
  shiny::testServer(
    ai_ctrl_server,
    {
      session$setInputs(chat_user_input = list("only setosa"))
      expect_equal(seen, "only setosa")
    },
    args = list(
      x = block,
      vars = list(columns = shiny::reactiveVal(character())),
      data = shiny::reactive(iris),
      eval = shiny::reactive(iris)
    )
  )
})
