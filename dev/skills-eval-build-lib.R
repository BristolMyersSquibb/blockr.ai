# Build a real skill library from the existing composer material, so a PLAIN
# function block can reproduce the composer experience purely from skill content.
# Idempotent; writes to /tmp/skill-eval-lib. Sourced by skills-eval-live.R.

build_skill_eval_lib <- function(root = "/tmp/skill-eval-lib") {
  comp_dir <- file.path(root, "composer-tables")
  tdir <- file.path(comp_dir, "templates")
  dir.create(tdir, recursive = TRUE, showWarnings = FALSE)

  # 1. Copy the composer templates verbatim as skill payloads.
  src <- "/workspace/blockr.sandbox/inst/extdata/composer-templates"
  files <- list.files(src, pattern = "\\.R$", full.names = TRUE)
  file.copy(files, tdir, overwrite = TRUE)

  # 2. Template index (id + label from the first "# Label:" line).
  idx <- vapply(files, function(f) {
    id <- sub("\\.R$", "", basename(f))
    lab <- sub("^#\\s*Label:\\s*", "", grep("^#\\s*Label:", readLines(f, warn = FALSE),
                                            value = TRUE)[1])
    paste0("- `templates/", id, ".R` (", id, ") - ", lab %||% "")
  }, character(1))

  # 3. SKILL.md = frontmatter + how-to-use-templates + the existing composer
  #    guidance body (the same ~750 lines the composer block ships statically).
  guidance <- readLines("/workspace/blockr.sandbox/inst/prompts/composer-function-block.md",
                        warn = FALSE)
  header <- c(
    "---",
    "name: composer-tables",
    "description: Write composer gt clinical tables (CSR demographics, AE, disposition, labs); named GS_/TS_ templates available.",
    "applies_to: [function_block]",
    "---",
    "",
    "# Composer clinical tables",
    "",
    "This block holds a `function(data)` that builds a clinical table with the",
    "`composer` package. When the user names a template (e.g. GS_CSR_DM_T_003),",
    "fetch it with `read_skill_file(\"composer-tables\", \"templates/<ID>.R\")`,",
    "set the block's `fn` to its contents, then adjust it to the connected data.",
    "",
    "## Available templates",
    "",
    idx,
    "",
    "## Composer API guidance",
    ""
  )
  writeLines(c(header, guidance), file.path(comp_dir, "SKILL.md"))

  # 4. A second skill carrying a study-specific fact the model cannot guess,
  #    to exercise domain-knowledge consultation (the motivating column case).
  sv <- file.path(root, "study-vars")
  dir.create(sv, showWarnings = FALSE)
  writeLines(c(
    "---",
    "name: study-vars",
    "description: Study-specific column choices you cannot infer (which treatment/population variable to use).",
    "applies_to: [function_block]",
    "---",
    "",
    "# Study variable conventions",
    "",
    "This study's ADaM data carries both a planned (`TRT01P`) and an actual",
    "(`TRT01A`) treatment column -- BOTH are present in the data, so you cannot",
    "tell from the schema which to use. The study convention: for ALL safety and",
    "demographic summaries, group by `TRT01A` (actual treatment), never `TRT01P`.",
    "",
    "The safety population is the subset where `SAFFL == \"Y\"`."
  ), file.path(sv, "SKILL.md"))

  root
}

`%||%` <- function(a, b) if (is.null(a) || !length(a) || is.na(a[1]) || !nzchar(a[1])) b else a
