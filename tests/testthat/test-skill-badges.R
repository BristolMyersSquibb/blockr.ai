# The assistant badges for the skill tools should name WHICH skill / template was
# read, so the user can see which skill was applied.

test_that("read_skill / read_skill_file badges carry the skill + path", {
  req_file <- ellmer::ContentToolRequest(
    id = "1", name = "read_skill_file",
    arguments = list(name = "composer-tables", path = "templates/GS_CSR_DM_T_003.R")
  )
  ev <- tool_request_event(req_file)
  expect_equal(ev$label, "Reading skill file")
  expect_equal(ev$summary, "composer-tables/templates/GS_CSR_DM_T_003.R")

  done <- tool_result_event(ellmer::ContentToolResult(request = req_file, value = "x"))
  expect_equal(done$label, "Read skill file")
  expect_equal(done$summary, "composer-tables/templates/GS_CSR_DM_T_003.R")
  expect_equal(done$status, "done")

  req_skill <- ellmer::ContentToolRequest(
    id = "2", name = "read_skill", arguments = list(name = "composer-tables")
  )
  expect_equal(tool_request_event(req_skill)$summary, "composer-tables")
})

test_that("skill_file_summary handles missing pieces", {
  expect_equal(skill_file_summary(list(name = "s", path = "p")), "s/p")
  expect_equal(skill_file_summary(list(path = "p")), "p")
  expect_equal(skill_file_summary(list()), "")
})
