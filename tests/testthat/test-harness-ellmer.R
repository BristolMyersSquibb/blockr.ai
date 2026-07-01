# Tests for the ellmer tool-calling harness (Design A).
#
# These do NOT need an LLM key. The validate tool is exercised directly, and the
# orchestration is driven by a fake chat client injected via the existing
# `blockr.chat_function` option hook, so the whole tool-call loop is
# deterministic.

# A minimal block-like object: discover only needs attr(.,"ctor") for var names
# and class() for (best-effort, NULL-tolerant) registry lookups.
fake_block <- function(ctor = function(value = "x", ...) NULL) {
  structure(list(), class = c("fake_block", "block"), ctor = ctor)
}

# A validate function independent of any real block/testServer: "good" succeeds
# and returns a data.frame; anything else throws.
good_validate <- function(args) {
  if (identical(args$value, "good")) {
    return(data.frame(a = 1:3, b = letters[1:3]))
  }
  stop("value must be 'good', got: ", args$value %||% "NULL")
}

# Fake ellmer chat client: replays a sequence of validate_config calls, then
# returns final text. Implements only the methods the harness uses.
make_fake_chat <- function(configs = character(), final_text = "Done.") {
  tools <- NULL
  list(
    set_system_prompt = function(p) invisible(NULL),
    set_tools = function(t) {
      tools <<- t
      invisible(NULL)
    },
    get_tools = function() tools,
    chat = function(msg, ...) {
      vt <- Find(function(td) isTRUE(td@name == "validate_config"), tools)
      for (cfg in configs) {
        if (!is.null(vt)) {
          # Mimic the model: validate_config now takes the block's params as
          # native arguments, so decode the JSON config and call with them.
          args <- tryCatch(jsonlite::fromJSON(cfg, simplifyVector = FALSE),
                           error = function(e) NULL)
          if (is.list(args) && length(args)) do.call(vt, args) else vt(config = cfg)
        }
      }
      final_text
    }
  )
}

with_fake_chat <- function(chat, expr) {
  withr::with_options(
    list(blockr.chat_function = list("gpt-4o-mini" = function() chat)),
    expr
  )
}


test_that("new_validate_tool: valid config returns ok + preview and records args", {
  vt <- new_validate_tool(good_validate, fake_block())

  res <- vt$invoke('{"value": "good"}')
  expect_true(res$ok)
  expect_true(nzchar(res$preview))
  expect_equal(vt$last_ok(), list(value = "good"))
  expect_s3_class(vt$last_result(), "data.frame")
})

test_that("new_validate_tool: invalid JSON returns ok=FALSE without recording", {
  vt <- new_validate_tool(good_validate, fake_block())

  res <- vt$invoke("this is not json")
  expect_false(res$ok)
  expect_match(res$error, "JSON", ignore.case = TRUE)
  expect_null(vt$last_ok())
})

test_that("new_validate_tool: validator error is surfaced, not recorded", {
  vt <- new_validate_tool(good_validate, fake_block())

  res <- vt$invoke('{"value": "bad"}')
  expect_false(res$ok)
  expect_match(res$error, "must be 'good'")
  expect_null(vt$last_ok())
})

test_that("new_validate_tool: last_ok reflects the last successful call", {
  vt <- new_validate_tool(good_validate, fake_block())
  vt$invoke('{"value": "bad"}')   # fails
  vt$invoke('{"value": "good"}')  # succeeds
  expect_equal(vt$last_ok(), list(value = "good"))
})

test_that("new_validate_tool: records last_error and clears it on success", {
  vt <- new_validate_tool(good_validate, fake_block())
  expect_null(vt$last_error())
  vt$invoke('{"value": "bad"}')                    # fails
  expect_match(vt$last_error(), "must be 'good'")
  vt$invoke('{"value": "good"}')                   # succeeds -> clears
  expect_null(vt$last_error())
})

test_that("new_validate_tool: appends escalation guidance after repeated failures", {
  vt <- new_validate_tool(good_validate, fake_block())

  r1 <- vt$invoke('{"value": "bad"}')              # 1st failure: raw error only
  expect_false(r1$ok)
  expect_false(grepl("[harness]", r1$error, fixed = TRUE))

  r2 <- vt$invoke('{"value": "bad"}')              # 2nd failure: guidance appended
  expect_true(grepl("[harness]", r2$error, fixed = TRUE))
  expect_true(grepl("cannot do this", r2$error, fixed = TRUE))  # escalate, don't quit
  expect_match(r2$error, "must be 'good'")                      # still carries the real error

  vt$invoke('{"value": "good"}')                   # success resets the streak
  r4 <- vt$invoke('{"value": "bad"}')              # back to a 1st failure -> no guidance
  expect_false(grepl("[harness]", r4$error, fixed = TRUE))
})


test_that("build_harness_tools: returns shared validate (+data) tools", {
  ts <- build_harness_tools(fake_block(), data = iris, validate = good_validate)
  expect_equal(get_tool(ts$validate)@name, "validate_config")
  expect_false(is.null(ts$data))
  expect_equal(get_tool(ts$data)@name, "data_tool")
  expect_true(is.function(ts$validate_fn))

  ts0 <- build_harness_tools(fake_block(), data = NULL, validate = good_validate)
  expect_null(ts0$data)
  expect_equal(get_tool(ts0$validate)@name, "validate_config")
})

test_that("validate tool reports effect: no-op vs real change", {
  no_op <- new_validate_tool(
    function(args) iris, fake_block(), data = iris      # returns all rows
  )
  r1 <- no_op$invoke('{"value": "x"}')
  expect_true(r1$ok)
  expect_match(r1$effect, "UNCHANGED")

  effective <- new_validate_tool(
    function(args) iris[iris$Species == "setosa", ], fake_block(), data = iris
  )
  r2 <- effective$invoke('{"value": "x"}')
  expect_true(r2$ok)
  expect_match(r2$effect, "100 removed")   # 150 -> 50
})

test_that("validate tool rejects unknown keys but allows block_name", {
  vt <- new_validate_tool(good_validate, fake_block(), data = NULL)

  # block_name is a universal controllable var -> accepted, not rejected
  r0 <- vt$invoke('{"value": "good", "block_name": "X"}')
  expect_true(r0$ok)

  # the wrapped save-format shape is rejected (valid param is 'value')
  r2 <- vt$invoke('{"state": {"value": "good"}}')
  expect_false(r2$ok)
  expect_match(r2$error, "state")

  # a genuinely unknown key is rejected
  rb <- vt$invoke('{"bogus": 1}')
  expect_false(rb$ok)
  expect_match(rb$error, "Unknown parameter")

  # a clean flat config still applies
  r3 <- vt$invoke('{"value": "good"}')
  expect_true(r3$ok)
})

test_that("ellmer harness: retries past a bad config and applies the good one", {
  chat <- make_fake_chat(
    configs = c('{"value": "bad"}', '{"value": "good"}'),
    final_text = "Set value to good."
  )

  res <- with_fake_chat(chat, {
    discover_via_ellmer_tools(
      prompt = "make it good",
      block = fake_block(),
      data = NULL,
      validate = good_validate
    )
  })

  expect_true(res$success)
  expect_equal(res$args, list(value = "good"))
  expect_s3_class(res$result, "data.frame")
  expect_equal(res$message, "Set value to good.")
  expect_null(res$error)
})

test_that("ellmer harness: result carries the effect and flags a persistent no-op", {
  # Validator returns the input unchanged -> every applied config is a no-op.
  # The fake chat never "fixes" it, so the nudge cap is hit and the result must
  # say so: success (a config IS applied) but noop=TRUE with the effect visible.
  chat <- make_fake_chat(
    configs = '{"value": "good"}',
    final_text = "Applied."
  )

  res <- with_fake_chat(chat, {
    discover_via_ellmer_tools(
      prompt = "do nothing much",
      block = fake_block(),
      data = iris,
      validate = function(args) iris
    )
  })

  expect_true(res$success)
  expect_true(res$noop)
  expect_match(res$effect, "no rows or columns changed")

  # An effective config reports its effect and noop=FALSE.
  chat2 <- make_fake_chat(configs = '{"value": "good"}', final_text = "Done.")
  res2 <- with_fake_chat(chat2, {
    discover_via_ellmer_tools(
      prompt = "setosa only",
      block = fake_block(),
      data = iris,
      validate = function(args) iris[iris$Species == "setosa", ]
    )
  })
  expect_true(res2$success)
  expect_false(res2$noop)
  expect_match(res2$effect, "100 removed")

  # No config applied -> effect NULL, noop FALSE.
  chat3 <- make_fake_chat(configs = character(), final_text = "Which column?")
  res3 <- with_fake_chat(chat3, {
    discover_via_ellmer_tools(
      prompt = "fix it",
      block = fake_block(),
      data = iris,
      validate = function(args) iris
    )
  })
  expect_false(res3$success)
  expect_null(res3$effect)
  expect_false(res3$noop)
})

test_that("ellmer harness: no validate call -> failure with the reply as question", {
  chat <- make_fake_chat(
    configs = character(),
    final_text = "Which column did you mean?"
  )

  res <- with_fake_chat(chat, {
    discover_via_ellmer_tools(
      prompt = "fix it",
      block = fake_block(),
      data = NULL,
      validate = good_validate
    )
  })

  expect_false(res$success)
  expect_null(res$args)
  expect_equal(res$question, "Which column did you mean?")
})

test_that("ellmer harness: surfaces the last validation error when the model gives up", {
  # model tries a bad config (fails validation) then replies "cannot do this".
  chat <- make_fake_chat(
    configs = '{"value": "bad"}',
    final_text = "This block genuinely cannot do this."
  )

  res <- with_fake_chat(chat, {
    discover_via_ellmer_tools(
      prompt = "make it good",
      block = fake_block(),
      data = NULL,
      validate = good_validate
    )
  })

  expect_false(res$success)
  # the ACTUAL blocker is surfaced (previously this was NULL / a generic string)
  expect_false(is.null(res$error))
  expect_match(res$error, "must be 'good'")
})

test_that("discover_block_args dispatches to the ellmer harness", {
  chat <- make_fake_chat(
    configs = '{"value": "good"}',
    final_text = "ok"
  )

  res <- with_fake_chat(chat, {
    discover_block_args(
      prompt = "make it good",
      block = fake_block(),
      data = NULL,
      validate = good_validate
    )
  })

  expect_true(res$success)
  expect_equal(res$args, list(value = "good"))
})

# --- Live integration tests (need a real model key) -------------------------
# Enable with BLOCKR_TEST_LLM=true and an OpenAI key. These exercise the real
# ellmer tool-call loop end to end, including the headline code_block case.

skip_live <- function() {
  skip_on_cran()
  skip_on_ci()
  skip_if(
    !identical(Sys.getenv("BLOCKR_TEST_LLM"), "true"),
    "LLM integration tests disabled (set BLOCKR_TEST_LLM=true to enable)"
  )
  skip_if_not_installed("blockr.extra")
}

test_that("ellmer harness (live): configures the code block (freeform R)", {
  skip_live()

  blk <- blockr.extra::new_code_block()
  res <- discover_block_args(
    prompt = "return only the first 3 rows",
    block = blk,
    data = iris
  )

  expect_true(res$success)
  expect_s3_class(res$result, "data.frame")
  expect_equal(nrow(res$result), 3L)
  # the produced fn is freeform R operating on `data`
  expect_true(grepl("data", res$args$fn))
})

test_that("ellmer harness (live): configures a filter via tool calls", {
  skip_live()
  skip_if_not_installed("blockr.dplyr")

  blk <- blockr.dplyr::new_filter_block()
  res <- discover_block_args(
    prompt = "only setosa species",
    block = blk,
    data = iris
  )

  expect_true(res$success)
  expect_true(all(res$result$Species == "setosa"))
  expect_equal(nrow(res$result), 50L)
})
