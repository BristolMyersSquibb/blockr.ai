test_that("name_unnamed_datasets", {
  data_list1 <- list(1, 2) |> name_unnamed_datasets()
  data_list2 <- list(a = 1, 2) |> name_unnamed_datasets()
  data_list3 <- list(a = 1, b = 2) |> name_unnamed_datasets()
  expect_equal(names(data_list1), c("data1", "data2"))
  expect_equal(names(data_list2), c("a", "data2"))
  expect_equal(names(data_list3), c("a", "b"))
})
