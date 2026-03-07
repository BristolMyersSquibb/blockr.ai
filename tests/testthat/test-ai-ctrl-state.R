# Tests for state propagation through block_server
#
# These verify that externally setting state (as AI ctrl does) actually
# changes the block's result. No LLM needed — directly sets reactiveVals.

test_that("external state change propagates through block_server (filter)", {
  skip_if_not_installed("blockr.dplyr")

  block <- blockr.dplyr::new_filter_block()

  shiny::testServer(
    blockr.core::get_s3_method("block_server", block),
    {
      session$flushReact()

      # Initial: no conditions, all 150 rows
      expect_equal(nrow(session$returned$result()), 150)

      # Simulate what AI ctrl does: set conditions externally
      state <- session$returned$state
      state$conditions(list(
        list(column = "Species", values = c("virginica"), mode = "include")
      ))
      session$flushReact()

      # Should now be 50 rows — if not, the bug is reproduced
      expect_equal(nrow(session$returned$result()), 50)
    },
    args = list(x = block, data = list(data = function() iris))
  )
})

test_that("external state change with exclude mode (filter)", {
  skip_if_not_installed("blockr.dplyr")

  block <- blockr.dplyr::new_filter_block()

  shiny::testServer(
    blockr.core::get_s3_method("block_server", block),
    {
      session$flushReact()
      expect_equal(nrow(session$returned$result()), 150)

      state <- session$returned$state
      state$conditions(list(
        list(column = "Species", values = c("setosa"), mode = "exclude")
      ))
      session$flushReact()

      result <- session$returned$result()
      expect_equal(nrow(result), 100)
      expect_false("setosa" %in% result$Species)
    },
    args = list(x = block, data = list(data = function() iris))
  )
})

test_that("external state change with numeric values (filter)", {
  skip_if_not_installed("blockr.dplyr")

  block <- blockr.dplyr::new_filter_block()

  shiny::testServer(
    blockr.core::get_s3_method("block_server", block),
    {
      session$flushReact()
      expect_equal(nrow(session$returned$result()), 32)

      state <- session$returned$state
      state$conditions(list(
        list(column = "cyl", values = c(4), mode = "include")
      ))
      session$flushReact()

      result <- session$returned$result()
      expect_equal(nrow(result), 11)
      expect_true(all(result$cyl == 4))
    },
    args = list(x = block, data = list(data = function() mtcars))
  )
})
