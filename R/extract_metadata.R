extract_metadata <- function(data, domain, extract_codelist_vars = NULL, max_unique_values = 1e6) {
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

    return(var_meta)
  })

  # Create the metadata entry
  metadata_entry <- list(
    description = domain_label,
    variables = variable_list
  )

  return(metadata_entry)
}
