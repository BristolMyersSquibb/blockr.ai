# Skill library: a folder of Claude-Code-style skill directories the assistant
# can consult while configuring a block. Each skill is a subdirectory containing
# a `SKILL.md` (YAML frontmatter + body) plus optional payload files (e.g.
# templates). Skills are surfaced to the model via a filtered catalog in the
# system prompt and two read tools (`read_skill`, `read_skill_file`).
#
# Read-only: nothing here writes skills. Applying a skill's payload to a block
# goes through the block's existing parameters via `validate_config`.

skill_cache <- new.env(parent = emptyenv())

#' Resolve the configured skill-library folder(s).
#'
#' Skills can live in several locations. `getOption("blockr.skill_library")` may
#' be a character vector of directories (so packages can append their own with
#' `options(blockr.skill_library = c(getOption("blockr.skill_library"), dir))`),
#' and the `BLOCKR_SKILL_LIBRARY` environment variable may list several paths
#' separated by the platform path separator (`:` on Unix). Both sources are
#' combined; non-existent paths are dropped. Returns `character()` when none
#' resolve, in which case the harness behaves exactly as it does without skills.
#'
#' @return A character vector of normalised directory paths (possibly empty).
#' @noRd
skill_library_paths <- function() {
  opt <- getOption("blockr.skill_library", default = NULL)
  env <- Sys.getenv("BLOCKR_SKILL_LIBRARY", "")

  paths <- character()
  if (!is.null(opt)) paths <- c(paths, as.character(opt))
  if (nzchar(env)) {
    paths <- c(paths, strsplit(env, .Platform$path.sep, fixed = TRUE)[[1]])
  }
  paths <- paths[nzchar(paths)]
  paths <- paths[dir.exists(paths)]
  if (!length(paths)) return(character())
  unique(normalizePath(paths, winslash = "/", mustWork = FALSE))
}

#' Parse the leading YAML frontmatter of a `SKILL.md`.
#'
#' Reads the keys we use (`name`, `description`, `applies_to`) and ignores the
#' rest, so skills authored elsewhere (e.g. BMS's library) with extra frontmatter
#' fields still parse.
#'
#' @param lines Character vector, the lines of `SKILL.md`.
#' @return A list with `name`, `description`, `applies_to`, or `NULL` when there
#'   is no frontmatter block or it fails to parse.
#' @noRd
parse_skill_frontmatter <- function(lines) {
  if (length(lines) < 2L || !grepl("^---\\s*$", lines[1L])) {
    return(NULL)
  }
  close <- which(grepl("^---\\s*$", lines))
  close <- close[close > 1L]
  if (!length(close)) {
    return(NULL)
  }
  body <- lines[2:(close[1L] - 1L)]
  fm <- tryCatch(yaml::yaml.load(paste(body, collapse = "\n")), error = function(e) NULL)
  if (!is.list(fm)) {
    return(NULL)
  }
  applies <- fm[["applies_to"]]
  list(
    name = as_scalar_chr(fm[["name"]]),
    description = as_scalar_chr(fm[["description"]]),
    applies_to = if (is.null(applies)) NULL else as.character(applies)
  )
}

as_scalar_chr <- function(x) {
  if (is.null(x) || length(x) != 1L) NULL else as.character(x)
}

#' Index a skill's bundled templates as "id - label" lines.
#'
#' Looks for `<dir>/templates/*.R` and reads each file's leading `# Label:`
#' comment. Surfacing this in the catalog lets the model pick a template by
#' description when the user does not know its id. Empty when there is no
#' `templates/` folder.
#' @noRd
skill_template_index <- function(dir) {
  tdir <- file.path(dir, "templates")
  if (!dir.exists(tdir)) return(character())
  files <- sort(list.files(tdir, pattern = "\\.[Rr]$", full.names = TRUE))
  vapply(files, function(f) {
    id <- sub("\\.[Rr]$", "", basename(f))
    lab <- sub("^#\\s*Label:\\s*", "",
               grep("^#\\s*Label:", readLines(f, warn = FALSE), value = TRUE)[1])
    if (length(lab) && !is.na(lab) && nzchar(lab)) paste0(id, " - ", lab) else id
  }, character(1), USE.NAMES = FALSE)
}

#' Read one skill directory into a record.
#'
#' @param dir Path to a candidate skill directory.
#' @return A list `list(id, dir, name, description, applies_to)`, or `NULL` when
#'   the directory has no `SKILL.md` or its frontmatter lacks `name`/
#'   `description`.
#' @noRd
read_skill_record <- function(dir) {
  md <- file.path(dir, "SKILL.md")
  if (!file.exists(md)) {
    return(NULL)
  }
  fm <- parse_skill_frontmatter(readLines(md, warn = FALSE))
  if (is.null(fm) || is.null(fm$name) || is.null(fm$description)) {
    warning("Skipping skill '", basename(dir),
            "': missing or invalid frontmatter (need name + description).",
            call. = FALSE)
    return(NULL)
  }
  list(
    id = basename(dir),
    dir = dir,
    name = fm$name,
    description = fm$description,
    applies_to = fm$applies_to,
    templates = skill_template_index(dir)
  )
}

#' Scan the skill library/libraries into a list of records (cached on
#' paths + mtimes).
#'
#' Directories are scanned in order; when two skills share a `name`, the one from
#' the earlier path wins (so a local override can shadow a packaged skill).
#'
#' @param paths Library folders; defaults to the configured ones.
#' @return A list of skill records (possibly empty).
#' @noRd
scan_skill_library <- function(paths = skill_library_paths()) {
  if (!length(paths)) {
    return(list())
  }
  key <- paste(paths, vapply(paths, function(p) as.character(file.info(p)$mtime), ""),
               collapse = "|")
  if (!identical(skill_cache$key, key)) {
    dirs <- unlist(lapply(paths, list.dirs, recursive = FALSE), use.names = FALSE)
    skills <- Filter(Negate(is.null), lapply(dirs, read_skill_record))
    seen <- character()
    kept <- list()
    for (s in skills) {
      if (!s$name %in% seen) {
        seen <- c(seen, s$name)
        kept[[length(kept) + 1L]] <- s
      }
    }
    skill_cache$key <- key
    skill_cache$skills <- kept
  }
  skill_cache$skills
}

#' Filter the library to skills that target a given block.
#'
#' A skill matches when any class in its `applies_to` is in the block's class
#' vector (so `applies_to: [function_block]` reaches `composer_function_block`
#' too). A skill with no `applies_to` is general and matches every block.
#'
#' @param block A block object.
#' @param skills Skill records; defaults to a fresh scan.
#' @return The matching subset.
#' @noRd
skills_for_block <- function(block, skills = scan_skill_library()) {
  if (!length(skills)) {
    return(list())
  }
  cls <- class(block)
  keep <- vapply(skills, function(s) {
    is.null(s$applies_to) || any(s$applies_to %in% cls)
  }, logical(1))
  skills[keep]
}

#' Skills available to a block
#'
#' Lists the skills the assistant can consult when configuring a given block,
#' from the configured skill library/libraries (see the `blockr.skill_library`
#' option). A block UI can use this to show users which skills apply -- so they
#' know to ask, e.g., "use the composer-tables skill to ...".
#'
#' @param block A block object; its class determines which skills apply (a skill
#'   targets block classes via its `applies_to` frontmatter).
#' @return A list of skills, each a list with `name`, `description` and
#'   `templates` (a character vector of "id - label" lines, possibly empty).
#'   Empty when no library is configured or none target the block.
#' @export
block_skills <- function(block) {
  lapply(skills_for_block(block), function(s) {
    s[c("name", "description", "templates")]
  })
}

#' Catalog text for the system prompt: one line per matching skill.
#'
#' @param skills Skill records already filtered to the current block.
#' @return Character string (empty when no skills).
#' @noRd
skill_catalog_text <- function(skills) {
  if (!length(skills)) {
    return("")
  }
  lines <- vapply(
    skills,
    function(s) {
      line <- paste0("- ", s$name, ": ", s$description)
      if (length(s$templates)) {
        # Surface the template menu so the model can pick one by description even
        # when the user does not name a template id.
        line <- paste0(
          line, "\n    templates (fetch with read_skill_file(\"", s$name,
          "\", \"templates/<id>.R\")):\n",
          paste0("      ", s$templates, collapse = "\n")
        )
      }
      line
    },
    character(1)
  )
  paste0(
    "SKILLS AVAILABLE FOR THIS BLOCK (extra guidance you can pull on demand):\n",
    paste(lines, collapse = "\n"), "\n\n",
    "These skills contain facts you CANNOT reliably infer from the data or from ",
    "general knowledge -- study-specific column choices, package idioms, named ",
    "templates. Whenever the task involves a choice a skill could pin down (which ",
    "column or convention to use, which template to apply), you MUST call ",
    "`read_skill(name)` and follow it BEFORE configuring the block. Do not rely ",
    "on your own assumptions for study-specific details when a skill covers them. ",
    "Use ",
    "`read_skill_file(name, path)` to fetch a file a skill references (e.g. a ",
    "named template). To apply a fetched file, read it, then call ",
    "`validate_config` with the relevant parameter set to that content (for a ",
    "function block, that is `fn`).\n\n"
  )
}

#' Drop a leading YAML frontmatter block, returning the body as one string.
#' @noRd
strip_frontmatter <- function(lines) {
  if (length(lines) >= 2L && grepl("^---\\s*$", lines[1L])) {
    close <- which(grepl("^---\\s*$", lines))
    close <- close[close > 1L]
    if (length(close)) {
      lines <- if (close[1L] < length(lines)) {
        lines[(close[1L] + 1L):length(lines)]
      } else {
        character()
      }
    }
  }
  paste(lines, collapse = "\n")
}

#' Read a skill's body by name (frontmatter stripped).
#'
#' @param skills Skill records (filtered to the current block).
#' @param name Skill name.
#' @return The skill body, or an informative message when the name is unknown.
#' @noRd
skill_read <- function(skills, name) {
  s <- skill_by_name(skills, name)
  if (is.null(s)) {
    return(paste0("No skill named '", name, "'. Available: ",
                  paste(vapply(skills, `[[`, character(1), "name"),
                        collapse = ", "), "."))
  }
  strip_frontmatter(readLines(file.path(s$dir, "SKILL.md"), warn = FALSE))
}

#' Read a payload file bundled with a skill, confined to the skill directory.
#'
#' @param skills Skill records (filtered to the current block).
#' @param name Skill name.
#' @param path Path relative to the skill directory.
#' @return The file contents, or an informative message when the skill or file is
#'   not found (including rejected path-traversal attempts).
#' @noRd
skill_read_file <- function(skills, name, path) {
  s <- skill_by_name(skills, name)
  if (is.null(s)) {
    return(paste0("No skill named '", name, "'."))
  }
  full <- normalizePath(file.path(s$dir, path), winslash = "/", mustWork = FALSE)
  # confine to the skill directory: reject path traversal / absolute escapes
  if (!startsWith(full, paste0(s$dir, "/")) || !file.exists(full)) {
    return(paste0("No file '", path, "' in skill '", name, "'."))
  }
  paste(readLines(full, warn = FALSE), collapse = "\n")
}

skill_by_name <- function(skills, name) {
  for (s in skills) {
    if (identical(s$name, name)) return(s)
  }
  NULL
}

#' Build the `read_skill` / `read_skill_file` tools for a set of skills.
#'
#' @param skills Skill records (filtered to the current block).
#' @return A list of `llm_tool` objects (empty when no skills).
#' @noRd
new_skill_tools <- function(skills) {
  if (!length(skills)) {
    return(list())
  }

  read_skill <- function(name) skill_read(skills, name)
  read_skill_file <- function(name, path) skill_read_file(skills, name, path)

  list(
    new_llm_tool(
      read_skill,
      name = "read_skill",
      description = paste(
        "Read a skill's full guidance by name. Use when the request touches a",
        "skill listed in the catalog."
      ),
      arguments = list(
        name = ellmer::type_string("Skill name, exactly as in the catalog.")
      )
    ),
    new_llm_tool(
      read_skill_file,
      name = "read_skill_file",
      description = paste(
        "Read a file bundled with a skill (e.g. a template). Paths are relative",
        "to the skill directory."
      ),
      arguments = list(
        name = ellmer::type_string("Skill name, exactly as in the catalog."),
        path = ellmer::type_string(
          "Path within the skill, e.g. 'templates/GS_CSR_DM_T_003.R'."
        )
      )
    )
  )
}
