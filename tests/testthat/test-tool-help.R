test_that("get_package_help retrieves base package help", {
  result <- get_package_help("base")
  expect_type(result, "character")
  expect_true(nchar(result) > 0)
  expect_match(result, "R Help Documentation")
})

test_that("get_package_help handles non-existent package", {
  result <- get_package_help("nonexistent_package_xyz")
  expect_type(result, "character")
  expect_match(result, "Error.*package")
})

test_that("get_help_topic retrieves specific function help", {
  result <- get_help_topic("mean", "base")
  expect_type(result, "character")
  expect_true(nchar(result) > 0)
  expect_match(result, "mean.*R Documentation")
})

test_that("get_help_topic retrieves topic help with no package", {
  result <- get_help_topic("plot")
  expect_type(result, "character")
  expect_true(nchar(result) > 0)
  expect_match(result, "Found.*packages.*Choose")
})

test_that("get_help_topic handles nonexistent package", {
  result <- get_help_topic("plot", "nonexistent_package_xyz")
  expect_type(result, "character")
  expect_true(nchar(result) > 0)
  expect_match(result, "Error retrieving topic")
})

test_that("get_package_help works with dplyr package", {
  skip_if_not_installed("dplyr")
  
  result <- get_package_help("dplyr")
  expect_type(result, "character")
  expect_true(nchar(result) > 0)
  expect_true(grepl("dplyr", result, ignore.case = TRUE))
  
  # Should contain package documentation content
  expect_false(grepl("Error", result))
  expect_false(grepl("not found", result))
})