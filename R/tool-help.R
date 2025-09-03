get_help_topic <- function(topic, package = NULL) {

  pkg_form_path <- function(x) {
    basename(dirname(dirname(x)))
  }

  fetch_rd_db <- utils::getFromNamespace("fetchRdDB", "tools")

  get_help_file <- function(x) {

    path <- dirname(x)
    dirpath <- dirname(path)

    stopifnot(file.exists(dirpath))

    pkgname <- basename(dirpath)
    rd_db <- file.path(path, pkgname)

    stopifnot(file.exists(paste0(rd_db, ".rdx")))

    fetch_rd_db(rd_db, basename(x))
  }

  res <- tryCatch(
    utils::help((topic), (package), help_type = "text"),
    error = function(e) {
      paste0(
        "Error retrieving topic \"", topic, "\" for \"", package, "\": ",
        conditionMessage(e)
      )
    }
  )

  if (inherits(res, "help_files_with_topic")) {

    res <- format(res)

    if (length(res) == 0L) {

      paste0(
        "No help topics found for \"", topic, "\"",
        if (not_null(package)) paste0(" and package \"", package, "\""),
        ". Try different keywords or function names."
      )

    } else if (length(res) > 1L) {

      paste0(
        "Found \"", topic, "\" in ", length(res), " packages:\n",
        paste0("- ", pkg_form_path(res), collapse = "\n"),
        "\nChoose one of these packages to get more detailed information."
      )

    } else {

      pkg <- pkg_form_path(res)
      out <- character()

      tools::Rd2txt(
        get_help_file(res),
        out = textConnection("out", open = "w", local = TRUE),
        package = pkg
      )

      paste(out, collapse = "\n")
    }

  } else {

    stopifnot(is.character(res))
    paste(res, collapse = "\n")
  }
}

get_package_help <- function(package) {

  res <- tryCatch(
    utils::help(package = (package), help_type = "text"),
    error = function(e) {
      paste0(
        "Error retrieving package overview for '", package, "': ",
        conditionMessage(e)
      )
    }
  )

  if (length(res) == 0) {
    return(
      paste0(
        "Package '", package, "' is available but no overview help found. ",
        "Try specifying a topic or function name."
      )
    )
  }

  paste0(
    "R Help Documentation for Package '", package, "':\n\n",
    paste(format(res), collapse = "\n")
  )
}

new_help_tool <- function(...) {

  get_r_help <- function(topic = NULL, package = NULL) {

    if (is.null(topic) && is.null(package)) {
      return(
        paste0(
          "Error: Please provide at least one parameter:\n",
          "- \"topic\" for cross-package search\n",
          "- \"package\" for package-specific help\n",
          "- \"topic\" + \"package\" for specific function help"
        )
      )
    }

    log_debug(
      "Looking up R help for",
      if (!is.null(topic)) paste0(" topic '", topic, "'"),
      if (!is.null(package)) paste0(", package '", package, "'")
    )

    if (is.null(topic)) {
      get_package_help(package)
    } else {
      get_help_topic(topic, package)
    }
  }

  new_llm_tool(
    get_r_help,
    .description = paste(
      "Get R documentation and help. Use \"topic\" for cross-package search,",
      "\"package\" for package-specific help, or both \"package\" and",
      "\"topic\" for specific function documentation."
    ),
    topic = ellmer::type_string(
      "Optional: Search for a specific topic or function."
    ),
    package = ellmer::type_string(
      paste(
        "Optional: Restrict your search to a specific package or if no topic",
        "is specified, retrieve a package overview."
      )
    )
  )
}

