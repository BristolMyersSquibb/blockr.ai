# Telemetry: one JSON line per discover run, gated on blockr.ai_run_log.

test_that("discover appends a JSONL entry when ai_run_log is set", {
  log <- withr::local_tempfile(fileext = ".jsonl")
  withr::local_options(blockr.ai_run_log = log)

  chat <- make_fake_chat(configs = '{"value": "good"}', final_text = "Done.")
  res <- with_fake_chat(chat, {
    discover_via_ellmer_tools(
      prompt = "setosa only",
      block = fake_block(),
      data = iris,
      validate = function(args) iris[iris$Species == "setosa", ]
    )
  })
  expect_true(res$success)

  lines <- readLines(log, warn = FALSE)
  expect_length(lines, 1L)
  entry <- jsonlite::fromJSON(lines[1L])
  expect_identical(entry$block, "fake_block")
  expect_identical(entry$prompt, "setosa only")
  expect_true(entry$success)
  expect_false(entry$noop)
  expect_match(entry$effect, "100 removed")
  expect_identical(entry$nudges, 0L)

  # A second run appends (JSONL, not overwrite), and a no-config run logs the
  # failure shape.
  chat2 <- make_fake_chat(configs = character(), final_text = "Which column?")
  with_fake_chat(chat2, {
    discover_via_ellmer_tools(
      prompt = "fix it",
      block = fake_block(),
      data = iris,
      validate = function(args) iris
    )
  })
  lines <- readLines(log, warn = FALSE)
  expect_length(lines, 2L)
  entry2 <- jsonlite::fromJSON(lines[2L])
  expect_false(entry2$success)
  expect_true(entry2$question)
})

test_that("no log option means no file and no error", {
  withr::local_options(blockr.ai_run_log = NULL)
  withr::local_envvar(BLOCKR_AI_RUN_LOG = "")

  chat <- make_fake_chat(configs = '{"value": "good"}', final_text = "Done.")
  res <- with_fake_chat(chat, {
    discover_via_ellmer_tools(
      prompt = "x",
      block = fake_block(),
      data = NULL,
      validate = function(args) data.frame(a = 1)
    )
  })
  expect_true(res$success)
})

test_that("an unwritable log path never breaks discovery", {
  withr::local_options(blockr.ai_run_log = "/nonexistent-root/nope/run.jsonl")

  chat <- make_fake_chat(configs = '{"value": "good"}', final_text = "Done.")
  res <- with_fake_chat(chat, {
    discover_via_ellmer_tools(
      prompt = "x",
      block = fake_block(),
      data = NULL,
      validate = function(args) data.frame(a = 1)
    )
  })
  expect_true(res$success)
})
