# --- extract_data_query ---

test_that("extract_data_query extracts code from tagged block", {
  text <- "Let me check the data.\n\n```data_query\nstr(data)\nhead(data, 5)\n```"
  result <- extract_data_query(text)
  expect_equal(result, "str(data)\nhead(data, 5)")
})

test_that("extract_data_query returns NULL when no data_query block", {
  text <- "Here is the JSON:\n```json\n{\"x\": 1}\n```"
  expect_null(extract_data_query(text))
})

test_that("extract_data_query returns NULL for plain text", {
  expect_null(extract_data_query("Just some text without code blocks"))
})

test_that("extract_data_query extracts last block when multiple present", {
  text <- paste0(
    "```data_query\nstr(data)\n```\n\n",
    "```data_query\nnames(data)\n```"
  )
  result <- extract_data_query(text)
  expect_equal(result, "names(data)")
})


# --- data_schema ---

test_that("data_schema.data.frame delegates to format_df_preview", {
  df <- data.frame(x = 1:3, y = letters[1:3])
  result <- data_schema(df)
  expect_type(result, "character")
  expect_match(result, "3 rows x 2 cols")
  expect_match(result, "x \\(integer\\)")
})

test_that("data_schema.default includes class name", {
  obj <- list(a = 1, b = "hello")
  result <- data_schema(obj)
  expect_match(result, "Object of class: list")
})

test_that("data_schema.default handles environments", {
  e <- new.env(parent = emptyenv())
  e$x <- 42
  result <- data_schema(e)
  expect_match(result, "Object of class: environment")
})


# --- normalize_datasets ---

test_that("normalize_datasets returns empty list for NULL", {
  expect_equal(normalize_datasets(NULL), list())
})

test_that("normalize_datasets wraps data.frame", {
  df <- data.frame(x = 1)
  result <- normalize_datasets(df)
  expect_equal(result, list(data = df))
})

test_that("normalize_datasets passes through named list", {
  ds <- list(iris = iris, mtcars = mtcars)
  expect_equal(normalize_datasets(ds), ds)
})


# --- data_exploration_backend factory ---

test_that("data_exploration_backend creates none backend", {
  be <- data_exploration_backend("none")
  expect_null(be$setup(NULL, NULL))
  expect_null(be$process("some response", NULL))
})

test_that("data_exploration_backend accepts custom backend list", {
  custom <- list(
    setup = function(client, data) "custom_setup",
    process = function(response, data) NULL
  )
  be <- data_exploration_backend(custom)
  expect_equal(be$setup(NULL, NULL), "custom_setup")
})


# --- data_backend_manual probe counting ---

test_that("manual backend setup returns prompt addition", {
  be <- data_backend_manual(max_probes = 2)
  prompt_add <- be$setup(NULL, data.frame(x = 1))
  expect_match(prompt_add, "DATA EXPLORATION")
  expect_match(prompt_add, "data_query")
  expect_match(prompt_add, "2 times")
})

test_that("manual backend process returns NULL for non-data_query", {
  be <- data_backend_manual(max_probes = 2)
  expect_null(be$process("Here is JSON: {}", data.frame(x = 1)))
})

test_that("manual backend process executes data_query code", {
  be <- data_backend_manual(max_probes = 2)
  response <- "```data_query\nnames(data)\n```"
  result <- be$process(response, data.frame(x = 1, y = 2))
  expect_match(result, "Data exploration result")
  expect_match(result, "1 remaining")
})

test_that("manual backend enforces max_probes", {
  be <- data_backend_manual(max_probes = 1)
  # First probe
  result1 <- be$process("```data_query\nnames(data)\n```", data.frame(x = 1))
  expect_match(result1, "provide your JSON answer")

  # Second probe should be blocked

  result2 <- be$process("```data_query\nstr(data)\n```", data.frame(x = 1))
  expect_match(result2, "Maximum data exploration rounds")
})

test_that("manual backend handles errors in code", {
  be <- data_backend_manual(max_probes = 2)
  response <- "```data_query\nnonexistent_function(data)\n```"
  result <- be$process(response, data.frame(x = 1))
  expect_type(result, "character")
  # Should still produce output (error gets captured)
  expect_match(result, "Data exploration result")
})

test_that("manual backend probes_used tracks count", {
  be <- data_backend_manual(max_probes = 5)
  expect_equal(be$probes_used(), 0L)
  be$process("```data_query\nnames(data)\n```", data.frame(x = 1))
  expect_equal(be$probes_used(), 1L)
  be$process("```data_query\nstr(data)\n```", data.frame(x = 1))
  expect_equal(be$probes_used(), 2L)
})


# --- structured manual backend ---

test_that("structured backend setup mentions JSON action format", {
  be <- data_backend_manual(max_probes = 3, structured = TRUE)
  prompt_add <- be$setup(NULL, data.frame(x = 1))
  expect_match(prompt_add, "DATA EXPLORATION")
  expect_match(prompt_add, '"action"')
  expect_match(prompt_add, '"explore"')
})

test_that("structured backend detects explore action in json block", {
  be <- data_backend_manual(max_probes = 3, structured = TRUE)
  response <- '```json\n{"action": "explore", "code": "names(data)", "explanation": "checking columns"}\n```'
  result <- be$process(response, data.frame(x = 1, y = 2))
  expect_match(result, "Data exploration result")
  expect_equal(be$probes_used(), 1L)
})

test_that("structured backend returns NULL for answer JSON (no action)", {
  be <- data_backend_manual(max_probes = 3, structured = TRUE)
  response <- '```json\n{"conditions": [{"column": "x", "values": ["1"]}]}\n```'
  expect_null(be$process(response, data.frame(x = 1)))
  expect_equal(be$probes_used(), 0L)
})

test_that("structured backend returns NULL for plain text", {
  be <- data_backend_manual(max_probes = 3, structured = TRUE)
  expect_null(be$process("I have a question for you", data.frame(x = 1)))
})

test_that("structured backend enforces max_probes", {
  be <- data_backend_manual(max_probes = 1, structured = TRUE)
  resp <- '```json\n{"action": "explore", "code": "1+1"}\n```'
  be$process(resp, data.frame(x = 1))
  result2 <- be$process(resp, data.frame(x = 1))
  expect_match(result2, "Maximum data exploration rounds")
})


# --- probes_used on other backends ---

test_that("none backend probes_used returns 0", {
  be <- data_backend_none()
  expect_equal(be$probes_used(), 0L)
})

test_that("tools backend probes_used returns NA before setup", {
  be <- data_backend_tools()
  expect_true(is.na(be$probes_used()))
})

test_that("tools backend probes_used returns 0 after setup", {
  be <- data_backend_tools()
  mock_client <- list(set_tools = function(tools) NULL)
  be$setup(mock_client, data.frame(x = 1))
  expect_equal(be$probes_used(), 0L)
})


# --- data_preview refactored ---

test_that("data_preview works with data.frame", {
  result <- data_preview(data.frame(x = 1:3))
  expect_match(result, "# Input Data")
  expect_match(result, "3 rows x 1 cols")
})

test_that("data_preview works with named list of data.frames", {
  result <- data_preview(list(a = data.frame(x = 1), b = data.frame(y = 2)))
  expect_match(result, "## a")
  expect_match(result, "## b")
})

test_that("data_preview returns empty string for NULL", {
  expect_equal(data_preview(NULL), "")
})

test_that("data_preview returns empty string for empty list", {
  expect_equal(data_preview(list()), "")
})
