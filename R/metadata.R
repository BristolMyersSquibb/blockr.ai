#' Extract metadata from a data frame
#'
#' This function extracts metadata information from a data frame, including
#' variable names, labels, types, and unique values.
#'
#' @param data A data frame to extract metadata from
#' @param domain The domain name (used if data has no label attribute)
#' @param extract_codelist_vars A character vector of patterns to include/exclude
#'        when extracting codelist variables. Patterns starting with "-" are excluded.
#' @param max_unique_values The maximum number of unique values to extract (default: 1e6)
#'
#' @return A list containing metadata information
#' @export
extract_metadata <- function(
    data,
    domain,
    extract_codelist_vars = c(
      # SDTM Remove
      "-.*DTC$", "-STUDYID", "-USUBJID", "-DOMAIN", "-SUBJID", "-SITEID", "-COUNTRY", "-.*ID$", "-.*NAM$",
     # CDW Remove
    "-.*DAT$", "-.*DAT_RAW$","-.*DAT_INT$", "-.*ORRES$", "-.*TIM$", "-LBORESS.*$"
    ),
    max_unique_values = 80
) {
  # Determine the domain label
  domain_label <- ifelse(
    is.null(attr(data, "label")),
    domain,
    attr(data, "label")
  )

  # Extract variable names, labels, and types
  var_names <- names(data)
  var_labels <- sapply(data, function(col) attr(col, "label"))
  var_types <- sapply(data, class)
  all_vars <- names(data)

  # Default max unique values if not provided
  if (is.null(max_unique_values)) max_unique_values <- 1e6

  # Extract codelist variables based on provided patterns
  if (!is.null(extract_codelist_vars)) {
    positive_patterns <- extract_codelist_vars[
      !grepl("^-", extract_codelist_vars)
    ]
    negative_patterns <- gsub(
      "^-",
      "",
      extract_codelist_vars[grepl("^-", extract_codelist_vars)]
    )

    selected_vars <- all_vars

    if (length(positive_patterns) > 0) {
      selected_vars <- unique(unlist(lapply(
        positive_patterns,
        function(pat) grep(pat, all_vars, value = TRUE)
      )))
    }

    exclude_vars <- unique(unlist(lapply(
      negative_patterns,
      function(pat) grep(pat, all_vars, value = TRUE)
    )))
    selected_vars <- setdiff(selected_vars, exclude_vars)
  } else {
    selected_vars <- all_vars
  }

  # Generate metadata for each variable
  variable_list <- lapply(seq_along(var_names), function(i) {
    var_meta <- list(
      name = var_names[i],
      label = var_labels[i],
      type = var_types[i]
    )

    if (var_names[i] %in% selected_vars) {
      if (
        is.character(data[[i]]) &&
        (is.null(max_unique_values) ||
         length(unique(data[[i]])) <= max_unique_values)
      ) {
        var_meta$unique_values <- unique(data[[i]])
      } else if (is.factor(data[[i]])) {
        var_meta$levels <- levels(data[[i]])
      }
    }

    return(var_meta)
  })

  # Create the metadata entry
  metadata_entry <- list(
    description = domain_label,
    variables = variable_list
  )

  return(metadata_entry)
}

#' Generate metadata from reactive datasets
#'
#' This function generates metadata for a collection of named datasets.
#'
#' @param datasets A list of named datasets
#' @param extract_codelist_vars A character vector of patterns to include/exclude
#'        when extracting codelist variables
#' @param max_unique_values The maximum number of unique values to extract (default: 900)
#' @param tips Additional tips to include in the context
#'
#' @return A list containing metadata for all datasets
#' @export
make_metadata <- function(
    datasets,
    extract_codelist_vars = c(
      # SDTM Remove
      "-.*DTC$", "-STUDYID", "-USUBJID", "-DOMAIN", "-SUBJID", "-SITEID", "-COUNTRY", "-.*ID$", "-.*NAM$",
      # SDTM Keep
      "PARAM", "LBTEST",
      # CDW Remove
      "-.*DAT$", "-.*DAT_RAW$","-.*DAT_INT$", "-.*ORRES$", "-.*TIM$", "-LBORESS.*$"
    ),
    max_unique_values = 80,
    tips = ""
) {
  metadata_list <- list()

  for (domain in names(datasets)) {
    # Read the data
    data <- datasets[[domain]]
    # Generate metadata
    metadata_list[[domain]] <- extract_metadata(
      data,
      domain,
      extract_codelist_vars,
      max_unique_values
    )
  }

  study_metadata <- list(
    context = paste(
      "Treatment group information and population flags (sometimes called sets) are on DM and must be merged. Variables that end with FL are flag variables and are 'Y' when true. Visits should be displayed using VISIT, but ordered by VISITNUM. Unscheduled VISITs start with 'UNSCHEDULED'. ",
      tips
    ),
    datasets = metadata_list
  )

  return(study_metadata)
}

#' Extract metadata for a specific domain
#'
#' This function extracts metadata for a specific domain from the global environment.
#' It attempts to retrieve the dataset using get() and returns an error message if not found.
#'
#' @param domain The domain name to extract metadata for
#' @param max_unique_values The maximum number of unique values to extract per variable
#'
#' @return A JSON string containing the metadata for the requested domain, or an error message if not found
#' @export
get_domain_metadata <- function(domain, max_unique_values = 100) {
  # Attempt to retrieve the dataset from the global environment
  if (!exists(domain, envir = .GlobalEnv)) {
    return(jsonlite::toJSON(
      list(error = paste0("Domain '", domain, "' not found in environment")),
      auto_unbox = TRUE
    ))
  }

  domain_data <- get(domain, envir = .GlobalEnv)
  metadata <- extract_metadata(domain_data, domain, max_unique_values = max_unique_values)

  return(jsonlite::toJSON(metadata, auto_unbox = TRUE, pretty = TRUE))
}

#' Register metadata extraction tools
#'
#' This function registers the metadata extraction tool with an ellmer chat instance.
#'
#' @param chat An ellmer chat object to register the tool with
#' @return The chat object with the metadata extraction tool registered
#' @export
register_metadata_tools <- function(chat) {
  if (is.null(chat)) {
    return(NULL)
  }

  # Register the tool using the simplified get_domain_metadata function
  metadata_tool <- ellmer::tool(
    get_domain_metadata,
    "Extract detailed metadata for a specific domain/dataset, including variable names, types, and unique values.",
    domain = ellmer::type_string("The name of the domain/dataset to extract metadata for"),
    max_unique_values = ellmer::type_number("The maximum number of unique values to extract per variable")
  )

  chat$register_tool(metadata_tool)

  return(chat)
}
