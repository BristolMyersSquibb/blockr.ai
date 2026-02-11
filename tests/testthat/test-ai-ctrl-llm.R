test_that("ai_ctrl_server reconfigures dataset block to cars", {
  skip_on_cran()
  skip_on_ci()
  skip_if(
    !identical(Sys.getenv("BLOCKR_TEST_LLM"), "true"),
    "LLM integration tests disabled (set BLOCKR_TEST_LLM=true to enable)"
  )

  # Mock chat_append — no browser in testServer
  local_mocked_bindings(
    chat_append = function(...) invisible(),
    .package = "shinychat"
  )

  blk <- blockr.core::new_dataset_block("iris")

  # Construct the same reactive args that block_server passes to ctrl_block servers
  dataset_rv <- shiny::reactiveVal("iris")
  vars <- list(dataset = dataset_rv)
  dat  <- shiny::reactive(list())
  expr <- shiny::reactive({
    as.call(c(as.symbol("::"), quote(datasets), as.name(dataset_rv())))
  })

  shiny::testServer(
    blockr.ai::ai_ctrl_server,
    {
      # Simulate user typing in the chat
      session$setInputs(chat_user_input = "use the cars dataset")
      session$flushReact()

      # Verify the reactiveVal was updated by ai_ctrl_server
      expect_equal(dataset_rv(), "cars")
    },
    args = list(x = blk, vars = vars, dat = dat, expr = expr)
  )
})

test_that("ai_ctrl_server reconfigures filter block to setosa only", {
  skip_on_cran()
  skip_on_ci()
  skip_if(
    !identical(Sys.getenv("BLOCKR_TEST_LLM"), "true"),
    "LLM integration tests disabled (set BLOCKR_TEST_LLM=true to enable)"
  )

  local_mocked_bindings(
    chat_append = function(...) invisible(),
    .package = "shinychat"
  )

  blk <- blockr.dplyr::new_filter_block()

  conditions_rv <- shiny::reactiveVal(list())
  preserve_order_rv <- shiny::reactiveVal(FALSE)
  vars <- list(conditions = conditions_rv, preserve_order = preserve_order_rv)
  dat  <- shiny::reactive(list(data = iris))
  expr <- shiny::reactive({
    blockr.dplyr:::parse_value_filter(conditions_rv(), preserve_order = preserve_order_rv())
  })

  shiny::testServer(
    blockr.ai::ai_ctrl_server,
    {
      session$setInputs(chat_user_input = "only setosa species")
      session$flushReact()

      # Verify conditions were set
      conds <- conditions_rv()
      expect_true(length(conds) > 0)
      expect_equal(conds[[1]]$column, "Species")
      expect_true("setosa" %in% conds[[1]]$values)

      # Verify expression evaluates to filtered data
      result <- eval(expr(), blockr.core::eval_env(list(data = iris)))
      expect_equal(nrow(result), 50)
      expect_true(all(result$Species == "setosa"))
    },
    args = list(x = blk, vars = vars, dat = dat, expr = expr)
  )
})

test_that("ai_ctrl_server works with exprs_to_lang chain (like live app)", {
  skip_on_cran()
  skip_on_ci()
  skip_if(
    !identical(Sys.getenv("BLOCKR_TEST_LLM"), "true"),
    "LLM integration tests disabled (set BLOCKR_TEST_LLM=true to enable)"
  )

  local_mocked_bindings(
    chat_append = function(...) invisible(),
    .package = "shinychat"
  )

  blk <- blockr.dplyr::new_filter_block()

  conditions_rv <- shiny::reactiveVal(list())
  preserve_order_rv <- shiny::reactiveVal(FALSE)
  vars <- list(conditions = conditions_rv, preserve_order = preserve_order_rv)
  dat  <- shiny::reactive(list(data = iris))

  # Match the live app chain: lang <- reactive(exprs_to_lang(exp$expr()))
  # In the live app, expr passed to ctrl_block_server is `lang`, not the raw
  # expression. exprs_to_lang wraps the expression in a `{` call when needed.
  expr <- shiny::reactive({
    raw <- blockr.dplyr:::parse_value_filter(
      conditions_rv(),
      preserve_order = preserve_order_rv()
    )
    blockr.core:::exprs_to_lang(raw)
  })

  shiny::testServer(
    blockr.ai::ai_ctrl_server,
    {
      session$setInputs(chat_user_input = "only setosa species")
      session$flushReact()

      # Verify conditions were set
      conds <- conditions_rv()
      expect_true(length(conds) > 0)
      expect_equal(conds[[1]]$column, "Species")
      expect_true("setosa" %in% conds[[1]]$values)

      # Verify expression evaluates to filtered data via eval_impl
      result <- shiny::isolate(
        blockr.core:::eval_impl(blk, expr(), list(data = iris))
      )
      expect_equal(nrow(result), 50)
      expect_true(all(result$Species == "setosa"))
    },
    args = list(x = blk, vars = vars, dat = dat, expr = expr)
  )
})
