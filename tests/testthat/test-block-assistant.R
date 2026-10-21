# The per-block assistant on blockr.assistant's tools. No model is called: the
# tools are registered on a client with a dummy key and invoked directly, the
# way the model would call them.

offline_client <- function() {
  ellmer::chat_openai(
    model = "gpt-4.1-nano",
    credentials = function() list(Authorization = "Bearer test"),
    echo = "none"
  )
}

call_tool <- function(client, name, ...) {
  tl <- client$get_tools()[[name]]
  expect_false(is.null(tl), info = name)
  shiny::isolate(tl(...))
}

tool_text <- function(x) {
  if (inherits(x, "ellmer::ContentToolResult")) {
    paste(c(x@value, x@error), collapse = "\n")
  } else {
    paste(as.character(x), collapse = "\n")
  }
}

# A select block on iris, as the control plugin hands it over.
select_scope <- function() {
  blk <- blockr.dplyr::new_select_block()
  vars <- list(
    columns = shiny::reactiveVal(character()),
    exclude = shiny::reactiveVal(FALSE),
    distinct = shiny::reactiveVal(FALSE),
    block_name = shiny::reactiveVal("Select")
  )
  eval <- shiny::reactive({
    cols <- vars$columns()
    if (!length(cols)) return(iris)
    if (!all(cols %in% names(iris))) stop("Column(s) not found: ", paste(setdiff(cols, names(iris)), collapse = ", "))
    if (isTRUE(vars$exclude())) iris[setdiff(names(iris), cols)] else iris[cols]
  })
  scope <- new_block_scope(blk, vars, eval)
  scope$set_inputs(list(data = iris))
  list(block = blk, vars = vars, scope = scope)
}

test_that("the assistant's read tools see the block and its input", {
  skip_if_not_installed("blockr.dplyr")
  s <- select_scope()
  cl <- new_block_client(s$scope, s$block, s$vars, client = offline_client())

  listed <- call_tool(cl, "list_blocks")
  expect_setequal(listed$id, c("data", "this_block"))

  out <- tool_text(call_tool(cl, "inspect_results", code = "c(nrow(data), ncol(this_block))"))
  expect_match(out, "150 +5")

  expect_match(block_system_prompt(s$scope, cl), "## Scope")
})

test_that("commit writes the staged change into the block's state", {
  skip_if_not_installed("blockr.dplyr")
  s <- select_scope()
  cl <- new_block_client(s$scope, s$block, s$vars, client = offline_client())

  expect_true("modify_select_block" %in% names(cl$get_tools()))

  call_tool(cl, "modify_select_block", id = "this_block",
            columns = c("Species", "Sepal.Length"))
  expect_equal(shiny::isolate(s$vars$columns()), character())

  review <- tool_text(call_tool(cl, "commit"))
  expect_equal(shiny::isolate(s$vars$columns()), c("Species", "Sepal.Length"))
  expect_equal(ncol(s$scope$result()), 2L)
  expect_match(review, "Effect on `this_block`")
})

test_that("a change to another block is refused at staging", {
  skip_if_not_installed("blockr.dplyr")
  s <- select_scope()
  cl <- new_block_client(s$scope, s$block, s$vars, client = offline_client())

  pending <- attr(cl, "blockr_pending")
  bad <- pending()
  bad$blocks$mod <- list(data = list(dataset = "mtcars"))
  expect_error(pending(bad), "only change this block")
})

test_that("a commit whose evaluation fails is rolled back and reported", {
  skip_if_not_installed("blockr.dplyr")
  s <- select_scope()
  cl <- new_block_client(s$scope, s$block, s$vars, client = offline_client())

  call_tool(cl, "modify_select_block", id = "this_block", columns = "nope")
  review <- tool_text(call_tool(cl, "commit"))

  expect_equal(shiny::isolate(s$vars$columns()), character())
  expect_match(review, "nope")
  expect_equal(s$scope$conditions()$severity, "error")
})

test_that("a commit that changes nothing says so", {
  skip_if_not_installed("blockr.dplyr")
  s <- select_scope()
  cl <- new_block_client(s$scope, s$block, s$vars, client = offline_client())

  call_tool(cl, "modify_select_block", id = "this_block", distinct = TRUE)
  review <- tool_text(call_tool(cl, "commit"))

  expect_match(review, "did nothing to the result")
})

test_that("records ellmer turned into a data frame are staged as records", {
  skip_if_not_installed("blockr.dplyr")
  s <- select_scope()
  cl <- new_block_client(s$scope, s$block, s$vars, client = offline_client())
  pending <- attr(cl, "blockr_pending")

  p <- pending()
  p$blocks$mod <- list(this_block = list(
    columns = data.frame(column = c("cyl", "mpg"),
                         direction = factor(c("asc", "desc")))
  ))
  pending(p)

  expect_identical(
    pending()$blocks$mod$this_block$columns,
    list(list(column = "cyl", direction = "asc"),
         list(column = "mpg", direction = "desc"))
  )
})
