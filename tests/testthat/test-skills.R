lib <- function() test_path("fixtures", "skill-lib")

stub_block <- function(...) structure(list(), class = c(..., "block"))

test_that("skill_library_paths resolves option, env, and missing dirs", {
  norm <- function(p) normalizePath(p, winslash = "/")

  withr::local_options(blockr.skill_library = lib())
  expect_equal(skill_library_paths(), norm(lib()))

  withr::local_options(blockr.skill_library = NULL)
  withr::local_envvar(BLOCKR_SKILL_LIBRARY = lib())
  expect_equal(skill_library_paths(), norm(lib()))

  withr::local_envvar(BLOCKR_SKILL_LIBRARY = "")
  expect_equal(skill_library_paths(), character())

  withr::local_options(blockr.skill_library = "/no/such/dir")
  expect_equal(skill_library_paths(), character())
})

test_that("skill_library_paths supports multiple locations", {
  norm <- function(p) normalizePath(p, winslash = "/")
  d2 <- withr::local_tempdir()

  # option vector + env (path-sep list) combine; non-existent dropped; deduped
  withr::local_options(blockr.skill_library = c(lib(), "/no/such/dir"))
  withr::local_envvar(
    BLOCKR_SKILL_LIBRARY = paste(d2, lib(), sep = .Platform$path.sep)
  )
  got <- skill_library_paths()
  expect_setequal(got, c(norm(lib()), norm(d2)))
  expect_equal(anyDuplicated(got), 0L)
})

test_that("scan merges multiple libraries; earlier path wins on name clash", {
  d2 <- withr::local_tempdir()
  dir.create(file.path(d2, "general-style"))
  writeLines(c("---", "name: general-style",
               "description: OVERRIDE from second library.", "---", "x"),
             file.path(d2, "general-style", "SKILL.md"))
  dir.create(file.path(d2, "extra-only"))
  writeLines(c("---", "name: extra-only", "description: only in d2.", "---", "y"),
             file.path(d2, "extra-only", "SKILL.md"))

  # lib() listed first -> its general-style shadows d2's override
  withr::local_options(blockr.skill_library = c(lib(), d2))
  skills <- suppressWarnings(scan_skill_library())
  by <- stats::setNames(skills, vapply(skills, `[[`, "", "name"))
  expect_true("extra-only" %in% names(by))
  expect_match(by[["general-style"]]$description, "any block")  # from lib(), not OVERRIDE
})

test_that("parse_skill_frontmatter reads our keys and ignores extras", {
  lines <- c("---", "name: x", "description: d",
             "applies_to: [a, b]", "extra: ignored", "---", "body")
  fm <- parse_skill_frontmatter(lines)
  expect_equal(fm$name, "x")
  expect_equal(fm$description, "d")
  expect_equal(fm$applies_to, c("a", "b"))

  expect_null(parse_skill_frontmatter(c("no frontmatter", "here")))
  expect_null(parse_skill_frontmatter(c("---", "name: x")))  # unterminated
})

test_that("scan_skill_library returns valid records and skips malformed", {
  withr::local_options(blockr.skill_library = lib())
  skills <- suppressWarnings(scan_skill_library())
  names <- vapply(skills, `[[`, character(1), "name")
  expect_setequal(names, c("composer-tables", "patient-vars", "general-style"))
  expect_false("broken" %in% vapply(skills, `[[`, character(1), "id"))
})

test_that("read_skill_record warns and drops a skill without frontmatter", {
  expect_warning(
    rec <- read_skill_record(file.path(lib(), "broken")),
    "missing or invalid frontmatter"
  )
  expect_null(rec)
})

test_that("skills_for_block matches by class vector and inheritance", {
  withr::local_options(blockr.skill_library = lib())
  skills <- suppressWarnings(scan_skill_library())

  composer <- stub_block("composer_function_block", "function_block")
  got <- vapply(skills_for_block(composer, skills), `[[`, character(1), "name")
  expect_setequal(got, c("composer-tables", "general-style"))

  pp <- stub_block("patient_profile_block")
  got <- vapply(skills_for_block(pp, skills), `[[`, character(1), "name")
  expect_setequal(got, c("patient-vars", "general-style"))

  plain <- stub_block("some_other_block")
  got <- vapply(skills_for_block(plain, skills), `[[`, character(1), "name")
  expect_equal(got, "general-style")
})

test_that("skill_catalog_text lists matching skills or is empty", {
  withr::local_options(blockr.skill_library = lib())
  skills <- suppressWarnings(scan_skill_library())
  txt <- skill_catalog_text(skills_for_block(
    stub_block("function_block"), skills
  ))
  expect_match(txt, "composer-tables")
  expect_match(txt, "read_skill")
  expect_equal(skill_catalog_text(list()), "")
})

test_that("a skill's templates are indexed and surfaced in the catalog", {
  withr::local_options(blockr.skill_library = lib())
  skills <- suppressWarnings(scan_skill_library())
  comp <- skills[[which(vapply(skills, `[[`, "", "name") == "composer-tables")]]

  # fixture has templates/DEMO_T_001.R with "# Label: Demographics summary ..."
  expect_match(comp$templates, "DEMO_T_001 - Demographics summary")

  txt <- skill_catalog_text(list(comp))
  expect_match(txt, "templates \\(fetch with read_skill_file")
  expect_match(txt, "DEMO_T_001")

  # a skill with no templates/ folder yields none and no template block
  gen <- skills[[which(vapply(skills, `[[`, "", "name") == "general-style")]]
  expect_equal(gen$templates, character())
  expect_no_match(skill_catalog_text(list(gen)), "templates \\(fetch")
})

test_that("skill_read returns body without frontmatter; unknown name reported", {
  withr::local_options(blockr.skill_library = lib())
  skills <- suppressWarnings(scan_skill_library())

  body <- skill_read(skills, "composer-tables")
  expect_match(body, "Composer tables")
  expect_no_match(body, "extra_field")
  expect_no_match(body, "^---")

  expect_match(skill_read(skills, "nope"), "No skill named 'nope'")
})

test_that("skill_read_file reads payloads and rejects traversal", {
  withr::local_options(blockr.skill_library = lib())
  skills <- suppressWarnings(scan_skill_library())

  tmpl <- skill_read_file(skills, "composer-tables", "templates/DEMO_T_001.R")
  expect_match(tmpl, "function\\(data\\)")

  expect_match(
    skill_read_file(skills, "composer-tables", "../patient-vars/SKILL.md"),
    "No file"
  )
  expect_match(skill_read_file(skills, "nope", "x"), "No skill named 'nope'")
})

test_that("block_skills exposes name/description/templates for a block", {
  withr::local_options(blockr.skill_library = lib())
  got <- block_skills(stub_block("function_block"))
  nms <- vapply(got, `[[`, "", "name")
  expect_setequal(nms, c("composer-tables", "general-style"))
  comp <- got[[which(nms == "composer-tables")]]
  expect_named(comp, c("name", "description", "templates"))
  expect_match(comp$templates, "DEMO_T_001")

  withr::local_options(blockr.skill_library = NULL)
  withr::local_envvar(BLOCKR_SKILL_LIBRARY = "")
  expect_equal(block_skills(stub_block("function_block")), list())
})

test_that("new_skill_tools builds llm_tools (and nothing when empty)", {
  withr::local_options(blockr.skill_library = lib())
  skills <- suppressWarnings(scan_skill_library())
  tools <- new_skill_tools(skills_for_block(stub_block("function_block"), skills))
  expect_length(tools, 2L)
  expect_true(all(vapply(tools, is_llm_tool, logical(1))))
  expect_length(new_skill_tools(list()), 0L)
})
