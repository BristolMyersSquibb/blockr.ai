#'@export
make_metadata <- function(
    reactive_datasets,
    extract_codelist_vars = c("-.*DTC$", "-STUDYID", "-USUBJID", "-DOMAIN", "-SUBJID", "-SITEID", "-COUNTRY", "-.*ID$", "-.*NAM$"),
    max_unique_values = 130,
    tips = "") {
  metadata_list <- list()

  for (domain in names(reactive_datasets)) {
    # Read the data
    data <- reactive_datasets[[domain]]
    # Generate metadata
    metadata_list[[domain]] <- extract_metadata(data, domain, extract_codelist_vars, max_unique_values)
  }

  study_metadata <- list(
    context = paste("Treatment group information and population flags (sometimes called sets) are on DM and must be merged. Variables that end with FL are flag variables and are 'Y' when true. Visits should be displayed using VISIT, but ordered by VISITNUM. Unscheduled VISITs start with 'UNSCHEDULED'. ", tips),
    datasets = metadata_list
  )

  return(study_metadata)
}
