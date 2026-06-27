# The skill tools are built in the shared harness contract (build_harness_tools)
# and injected into the system prompt (build_tool_system_prompt). These tests
# check the wiring without invoking an LLM.

lib <- function() test_path("fixtures", "skill-lib")
stub_block <- function(...) structure(list(), class = c(..., "block"))

test_that("build_harness_tools surfaces skill tools for a matching block", {
  withr::local_options(blockr.skill_library = lib())
  block <- stub_block("function_block")

  ts <- suppressWarnings(build_harness_tools(block, data = NULL))
  expect_true(length(ts$skill_tools) == 2L)
  got <- vapply(ts$skills, `[[`, character(1), "name")
  expect_setequal(got, c("composer-tables", "general-style"))
})

test_that("no library configured means no skill tools (harness unchanged)", {
  withr::local_options(blockr.skill_library = NULL)
  withr::local_envvar(BLOCKR_SKILL_LIBRARY = "")
  block <- stub_block("function_block")

  ts <- build_harness_tools(block, data = NULL)
  expect_length(ts$skill_tools, 0L)
  expect_length(ts$skills, 0L)
})

test_that("build_tool_system_prompt injects the catalog when skills match", {
  withr::local_options(blockr.skill_library = lib())
  block <- stub_block("function_block")
  skills <- suppressWarnings(skills_for_block(block))

  prompt <- build_tool_system_prompt("fn", block, skills)
  expect_match(prompt, "SKILLS AVAILABLE FOR THIS BLOCK")
  expect_match(prompt, "composer-tables")

  # A block with no matching skills gets no catalog section.
  empty <- build_tool_system_prompt("x", stub_block("unmatched_block"), list())
  expect_no_match(empty, "SKILLS AVAILABLE FOR THIS BLOCK")
})
