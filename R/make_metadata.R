
make_metadata_default <- function(x) {
  names(x) <- create_dataset_aliases(names(x))$names
  list(
    description = "We provide below the ptypes (i.e. the output of `vctrs::vec_ptype()`) of the actual datasets that you have at your disposal:",
    summaries = lapply(x, vctrs::vec_ptype)
  )
}

make_metadata_bms <- function(
    reactive_datasets,
    extract_codelist_vars = c("-.*DTC$", "-STUDYID", "-USUBJID", "-DOMAIN", "-SUBJID", "-SITEID", "-COUNTRY", "-.*ID$", "-.*NAM$"),
    max_unique_values = 130,
    tips = "") {
  metadata_list <- list()

  for (domain in names(reactive_datasets)) {
    # Read the data
    data <- reactive_datasets[[domain]]
    # Generate metadata
    metadata_list[[domain]] <- extract_metadata_bms(data, domain, extract_codelist_vars, max_unique_values)
  }

  # Use aliases in metadata
  names(metadata_list) <- create_dataset_aliases(names(reactive_datasets))$names

  study_metadata <- list(
    context = paste("Treatment group information and population flags (sometimes called sets) are on DM and must be merged. Variables that end with FL are flag variables and are 'Y' when true. Visits should be displayed using VISIT, but ordered by VISITNUM. Unscheduled VISITs start with 'UNSCHEDULED'. ", tips),
    datasets = metadata_list
  )

  return(study_metadata)
}

extract_metadata_bms <- function(data, domain, extract_codelist_vars = NULL, max_unique_values = 1e6) {
  # Determine the domain label
  domain_label <- ifelse(is.null(attr(data, "label")), domain, attr(data, "label"))

  # Extract variable names, labels, and types
  var_names <- names(data)
  var_labels <- sapply(data, function(col) attr(col, "label"))
  var_types <- sapply(data, class)
  all_vars <- names(data)

  # Default max unique values if not provided
  if (is.null(max_unique_values)) max_unique_values <- 1e6

  # Extract codelist variables based on provided patterns
  if (!is.null(extract_codelist_vars)) {
    positive_patterns <- extract_codelist_vars[!grepl("^-", extract_codelist_vars)]
    negative_patterns <- gsub("^-", "", extract_codelist_vars[grepl("^-", extract_codelist_vars)])

    selected_vars <- all_vars

    if (length(positive_patterns) > 0) {
      selected_vars <- unique(unlist(lapply(positive_patterns, function(pat) grep(pat, all_vars, value = TRUE))))
    }

    exclude_vars <- unique(unlist(lapply(negative_patterns, function(pat) grep(pat, all_vars, value = TRUE))))
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
      if (is.character(data[[i]]) && (is.null(max_unique_values) || length(unique(data[[i]])) <= max_unique_values)) {
        var_meta$unique_values <- unique(data[[i]])
      } else if (is.factor(data[[i]])) {
        var_meta$levels <- levels(data[[i]])
      }
    }

    var_meta
  })

  # Create the metadata entry
  metadata_entry <- list(
    description = domain_label,
    variables = variable_list
  )

  metadata_entry
}
