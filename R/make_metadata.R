make_metadata_default <- function(x) {
  list(
    description = "We provide below the ptypes (i.e. the output of `vctrs::vec_ptype()`) of the actual datasets that you have at your disposal:",
    summaries = lapply(x, vctrs::vec_ptype)
  )
}
