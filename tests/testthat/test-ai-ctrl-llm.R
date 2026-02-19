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
  data <- shiny::reactive(list())
  eval <- shiny::reactive({
    eval(
      as.call(c(as.symbol("::"), quote(datasets), as.name(dataset_rv()))),
      blockr.core::eval_env(list())
    )
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
    args = list(x = blk, vars = vars, data = data, eval = eval)
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
  data <- shiny::reactive(list(data = iris))
  eval <- shiny::reactive({
    expr <- blockr.dplyr:::parse_value_filter(
      conditions_rv(), preserve_order = preserve_order_rv()
    )
    blockr.core:::eval_impl(blk, expr, list(data = iris))
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
      result <- shiny::isolate(eval())
      expect_equal(nrow(result), 50)
      expect_true(all(result$Species == "setosa"))
    },
    args = list(x = blk, vars = vars, data = data, eval = eval)
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
  data <- shiny::reactive(list(data = iris))

  # Match the live app chain: the eval reactive now wraps exprs_to_lang + eval_impl
  eval <- shiny::reactive({
    raw <- blockr.dplyr:::parse_value_filter(
      conditions_rv(),
      preserve_order = preserve_order_rv()
    )
    lang <- blockr.core:::exprs_to_lang(raw)
    blockr.core:::eval_impl(blk, lang, list(data = iris))
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
      result <- shiny::isolate(eval())
      expect_equal(nrow(result), 50)
      expect_true(all(result$Species == "setosa"))
    },
    args = list(x = blk, vars = vars, data = data, eval = eval)
  )
})
