# LIVE eval of the summary table block (blockr.bi) on gpt-5.1. Class B/D: the
# RESULT is a real tibble (the display-shaped summary), so we can score res$args
# AND inspect the produced data frame. This is the "list of variables by Y"
# (Table 1 / demographics, AE counts) block. The constructor takes a single
# `state` list -> the harness state-unwrap exposes its children as top-level args
# (only the keys present in the registry EXAMPLE are exposed!).
#   cd /tmp && Rscript --vanilla /workspace/blockr.ai/dev/summary-table-eval-live.R
readRenviron("/workspace/.Renviron")
.libPaths("/workspace/blockr.dev/.devcontainer/.library")
suppressMessages({
  pkgload::load_all("/workspace/blockr.ai", quiet = TRUE)   # ai first
  pkgload::load_all("/workspace/blockr.bi", quiet = TRUE)
})
blockr.bi::register_bi_blocks()
MODEL <- "gpt-5.1"
`%||%` <- function(a, b) if (is.null(a) || (length(a) == 1 && !nzchar(as.character(a)))) b else a

# ----- data: ADaM-ish demographics (ADSL) + adverse events (ADAE) -----------
set.seed(1)
n_subj <- 80
arms <- sample(c("Placebo", "Drug 6mg", "Drug 12mg"), n_subj, TRUE)
adsl <- data.frame(
  USUBJID = sprintf("S%03d", seq_len(n_subj)),
  TRT01A  = arms,
  AGE     = round(rnorm(n_subj, 62, 9)),
  SEX     = sample(c("M", "F"), n_subj, TRUE),
  RACE    = sample(c("WHITE", "BLACK", "ASIAN"), n_subj, TRUE, c(.7, .2, .1)),
  BMIBL   = round(rnorm(n_subj, 27, 4), 1),
  SAFFL   = sample(c(TRUE, FALSE), n_subj, TRUE, c(.95, .05)),
  stringsAsFactors = FALSE
)
# Event-level AE: multiple rows per subject (the subject-dedup case).
ae_rows <- do.call(rbind, lapply(seq_len(n_subj), function(i) {
  k <- rpois(1, 2)
  if (k == 0) return(NULL)
  data.frame(
    USUBJID = adsl$USUBJID[i], TRT01A = adsl$TRT01A[i],
    AEBODSYS = sample(c("CARDIAC DISORDERS", "GI DISORDERS", "NERVOUS SYSTEM"), k, TRUE),
    AEDECOD  = sample(c("HEADACHE", "NAUSEA", "DIZZINESS", "AF", "FLUTTER"), k, TRUE),
    stringsAsFactors = FALSE
  )
}))

cat("adsl cols:", paste(names(adsl), collapse = ", "), "\n")
cat("adae cols:", paste(names(ae_rows), collapse = ", "),
    "  (", nrow(ae_rows), "rows /", n_subj, "subjects )\n\n")

# ----- cases: (prompt, data, checker on res$args) ---------------------------
cases <- list(
  list(nm = "demographics by arm", data = adsl[setdiff(names(adsl), "USUBJID")],
       ask = "Show a demographics table of age, sex and race split by treatment arm, with an overall column.",
       chk = function(a) all(c("AGE", "SEX", "RACE") %in% unlist(a$vars)) &&
                         "TRT01A" %in% unlist(a$by) && isTRUE(a$add_overall) &&
                         !nzchar(as.character(a$id_var %||% ""))),  # must NOT over-trigger dedup
  list(nm = "expanded stats", data = adsl,
       ask = "Baseline table of age and BMI by arm with full descriptive statistics (N, mean, SD, median, quartiles, min, max).",
       chk = function(a) all(c("AGE", "BMIBL") %in% unlist(a$vars)) &&
                         identical(as.character(a$stats %||% ""), "expanded")),
  list(nm = "AE SOC/PT nested", data = ae_rows,
       ask = "Adverse event counts by system organ class and preferred term, split by treatment.",
       chk = function(a) "AEBODSYS" %in% unlist(a$sections) &&
                         "AEDECOD" %in% unlist(a$vars) &&
                         "TRT01A" %in% unlist(a$by)),
  list(nm = "subject-dedup (id_var)", data = ae_rows,
       ask = paste("Count adverse events by preferred term and treatment arm, but each subject",
                   "should be counted at most once per term (distinct patients, not event rows).",
                   "The subject identifier column is USUBJID."),
       chk = function(a) identical(as.character(a$id_var %||% ""), "USUBJID")),
  list(nm = "AE flag logical", data = transform(adsl, AETERMFL = SAFFL),
       ask = "Summarise the SAFFL safety-population flag and sex by treatment arm.",
       chk = function(a) "SAFFL" %in% unlist(a$vars) && "TRT01A" %in% unlist(a$by))
)

cat("================= SUMMARY TABLE EVAL (gpt-5.1) =================\n")
n_ok <- 0
for (i in seq_along(cases)) {
  cs <- cases[[i]]
  blk <- new_summary_table_block()
  client <- ellmer::chat_openai(model = MODEL, echo = "none")
  res <- tryCatch(
    discover_block_args(prompt = cs$ask, block = blk, data = cs$data, client = client),
    error = function(e) list(success = FALSE, error = conditionMessage(e)))
  a <- res$args %||% list()
  if (!is.null(a$state)) a <- a$state   # validate tool re-wraps unwrapped children under `state`
  ok <- tryCatch(isTRUE(cs$chk(a)), error = function(e) FALSE)
  n_ok <- n_ok + ok
  cat(sprintf("\n[%d] %-6s %s\n", i, if (ok) "GOOD" else "MISS", cs$nm))
  cat("    args:", substr(gsub("\\s+", " ", paste(utils::capture.output(str(a)), collapse = " ")), 1, 200), "\n")
  if (!is.null(res$error)) cat("    error:", substr(res$error, 1, 120), "\n")
}
cat(sprintf("\n================= %d/%d GOOD =================\n", n_ok, length(cases)))
