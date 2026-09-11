# Composer function-block adjustment eval — PILOT (8 cases).
#
# Build the fixture first, once per container:
#   Rscript --vanilla /workspace/blockr.ai/dev/make-eval-dm.R
#
# I (acting as the configuring model) adjusted each mock template to the real
# safetyData ADaM dm, using only what the prompt + lean dm preview give. The
# scorer reports the composer population status (placeholders => "not populated"
# is the fail signal). Run with:
#   cd /tmp && Rscript --vanilla /workspace/blockr.ai/dev/composer-eval.R
.libPaths("/workspace/blockr.dev/.devcontainer/.library")
suppressMessages({
  pkgload::load_all("/workspace/blockr.extra", quiet = TRUE)
  pkgload::load_all("/workspace/blockr.dm", quiet = TRUE)
  pkgload::load_all("/workspace/blockr.sandbox", quiet = TRUE)
  pkgload::load_all("/workspace/blockr.ai", quiet = TRUE)
})
adam_dm <- readRDS("/tmp/adam_dm.rds")

ARMS <- 'c("Placebo", "Xanomeline Low Dose", "Xanomeline High Dose")'

cases <- list()

# 1. TEAE summary (adae) — adsl TRT01A -> adae TRTA mapping via make_denom(as=)
cases$teae <- 'function(data) {
  adsl <- data$adsl; adae <- data$adae
  adsl$TRTA <- adsl$TRT01A   # the column group is TRTA; the denominator needs it
  composer::table(
    title = "Treatment-emergent Adverse Event Summary",
    population = "Safety Analysis Set", bigN_format = "xxx", total_col = "nested",
    data = adae,
    denominator = composer::make_denom(adsl, "SAFFL == \'Y\'", "Safety Analysis Set")
  ) |>
    composer::colgroup(composer::by(variable = "TRTA", levels = __ARMS__)) |>
    composer::block_count(label = "TOTAL SUBJECTS WITH AN EVENT", statistic = "{n:xx} ({pct:xx.x})", blank_after = TRUE) |>
    composer::block_hierarchy(label = NULL, groups = c("AEBODSYS", "AEDECOD"), statistic = "{n:xx} ({pct:xx.x})", sort = list(AEBODSYS = "descending", AEDECOD = "descending")) |>
    composer::compose()
}'

# 2. Demographics Table 1 (adsl) — TRT01A; REGION1/COUNTRY block DROPPED (absent)
cases$demographics <- 'function(data) {
  adsl <- data$adsl
  composer::table(
    title = "Demographic Characteristics Summary",
    population = "Intent-to-Treat Analysis Set", bigN_format = "xxx", total_col = "nested",
    data = adsl,
    denominator = composer::make_denom(adsl, "ITTFL == \'Y\'", "Intent-to-Treat Analysis Set")
  ) |>
    composer::colgroup(composer::by(variable = "TRT01A", levels = __ARMS__)) |>
    composer::block_continuous(label = "AGE (YEARS)", variable = "AGE",
      statistic = c("N"="{N:xxx}","Mean"="{mean:xx.x}","SD"="{sd:xx.xx}","Median"="{median:xx.x}","Min"="{min:xx}","Max"="{max:xx}"), blank_after = TRUE) |>
    composer::block_categorical(label = "SEX n (%)", variable = "SEX", levels = c("M","F"), statistic = "{n:xx} ({pct:xx.x})", blank_after = TRUE) |>
    composer::block_categorical(label = "RACE n (%)", variable = "RACE", levels = sort(unique(adsl$RACE)), statistic = "{n:xx} ({pct:xx.x})", blank_after = TRUE) |>
    composer::block_categorical(label = "AGE GROUP n (%)", variable = "AGEGR1", levels = c("<65","65-80",">80"), statistic = "{n:xx} ({pct:xx.x})", blank_after = TRUE) |>
    composer::compose()
}'

# 3. Biomarker/lab change-from-baseline (adlbc) -- block_summary was REMOVED in
#    composer 2.1.0; this is its replacement, block_continuous(orientation =
#    "cols"). Every variable must carry the SAME number of stats: a ragged
#    `variables` list fails with "Decimal format not specified for stat 'n'".
#    `page_by` is gone too -- it makes compose() return one table per level,
#    which reads as "not populated" here and is banned in a blockr block
#    anyway; the parameter is picked and the frame cut instead.
cases$lab <- 'function(data) {
  adsl <- data$adsl; adlbc <- data$adlbc
  adsl$TRTA <- adsl$TRT01A   # the column group is TRTA; the denominator needs it
  param <- sort(unique(adlbc$PARAM))[1]
  composer::table(
    title = paste("Laboratory Change from Baseline Summary --", param),
    population = "Safety Analysis Set",
    data = adlbc[adlbc$PARAM == param, , drop = FALSE],
    denominator = composer::make_denom(adsl, "SAFFL == \'Y\'", "Safety Analysis Set")
  ) |>
    composer::block_continuous(orientation = "cols",
      variables = list(AVAL = c("{N:xxx}","{mean:xx.x}","{sd:xx.xxx}","{median:xx.xx}","{min:xx.x}","{max:xx.x}"),
                       CHG  = c("{N:xxx}","{mean:xx.x}","{sd:xx.xxx}","{median:xx.xx}","{min:xx.x}","{max:xx.x}")),
      by = c("AVISIT","TRTA")) |>
    composer::compose()
}'

# 4. Disposition (adsl) — ADAPT: EOSSTT/DCSREAS absent -> DCDECOD/DCREASCD
cases$disposition <- 'function(data) {
  adsl <- data$adsl
  composer::table(
    title = "Subject Disposition Summary", population = "Safety Analysis Set",
    bigN_format = "xxx", total_col = "nested",
    data = adsl, denominator = composer::make_denom(adsl, "SAFFL == \'Y\'", "Safety Analysis Set")
  ) |>
    composer::colgroup(composer::by(variable = "TRT01A", levels = __ARMS__)) |>
    composer::block_count(label = "COMPLETED STUDY", filter = "DCDECOD == \'COMPLETED\'", statistic = "{n:xx} ({pct:xx.x})", blank_after = TRUE) |>
    composer::block_count(label = "DISCONTINUED STUDY", filter = "DCDECOD != \'COMPLETED\'", statistic = "{n:xx} ({pct:xx.x})") |>
    composer::block_categorical(label = "REASON FOR DISCONTINUATION", variable = "DCREASCD", filter = "DCDECOD != \'COMPLETED\'", levels = sort(unique(adsl$DCREASCD)), statistic = "{n:xx} ({pct:xx.x})", blank_after = TRUE) |>
    composer::compose()
}'

# 5. UI: demographics with arms exposed as a MULTI-SELECT (list() default)
cases$ui_multiselect <- 'function(data, arms = list("Placebo" = "Placebo", "Xanomeline Low Dose" = "Xanomeline Low Dose", "Xanomeline High Dose" = "Xanomeline High Dose")) {
  adsl <- data$adsl
  composer::table(
    title = "Demographic Characteristics Summary", population = "Intent-to-Treat Analysis Set",
    bigN_format = "xxx", total_col = "nested",
    data = adsl, denominator = composer::make_denom(adsl, "ITTFL == \'Y\'", "Intent-to-Treat Analysis Set")
  ) |>
    composer::colgroup(composer::by(variable = "TRT01A", levels = arms)) |>
    composer::block_continuous(label = "AGE (YEARS)", variable = "AGE",
      statistic = c("N"="{N:xxx}","Mean"="{mean:xx.x}","SD"="{sd:xx.xx}"), blank_after = TRUE) |>
    composer::block_categorical(label = "SEX n (%)", variable = "SEX", levels = c("M","F"), statistic = "{n:xx} ({pct:xx.x})") |>
    composer::compose()
}'

# 6. Serious AEs filter (adae, AESER == "Y" exists)
cases$serious_ae <- 'function(data) {
  adsl <- data$adsl; adae <- data$adae
  adsl$TRTA <- adsl$TRT01A   # the column group is TRTA; the denominator needs it
  composer::table(
    title = "Serious Adverse Event Summary", population = "Safety Analysis Set",
    bigN_format = "xxx", total_col = "nested",
    data = adae, denominator = composer::make_denom(adsl, "SAFFL == \'Y\'", "Safety Analysis Set")
  ) |>
    composer::colgroup(composer::by(variable = "TRTA", levels = __ARMS__)) |>
    composer::block_count(label = "SUBJECTS WITH A SERIOUS AE", filter = "AESER == \'Y\'", statistic = "{n:xx} ({pct:xx.x})", blank_after = TRUE) |>
    composer::block_hierarchy(label = NULL, groups = c("AEBODSYS", "AEDECOD"), filter = "AESER == \'Y\'", statistic = "{n:xx} ({pct:xx.x})") |>
    composer::compose()
}'

# 7. CM summary — IMPOSSIBLE: dm has no adcm. Naive attempt (data$adcm = NULL).
cases$cm_missing_table <- 'function(data) {
  adsl <- data$adsl; adcm <- data$adcm
  adsl$TRTA <- adsl$TRT01A   # the column group is TRTA; the denominator needs it
  composer::table(title = "Concomitant Medication Summary", population = "Safety Analysis Set",
    data = adcm, denominator = composer::make_denom(adsl, "SAFFL == \'Y\'", "Safety Analysis Set")) |>
    composer::colgroup(composer::by(variable = "TRTA", levels = __ARMS__)) |>
    composer::block_hierarchy(label = NULL, groups = c("CMCLAS", "CMDECOD"), statistic = "{n:xx} ({pct:xx.x})") |>
    composer::compose()
}'

# 8. AESI — IMPOSSIBLE-ish: adae has no AESI column. Naive filter on absent col.
cases$aesi_missing_col <- 'function(data) {
  adsl <- data$adsl; adae <- data$adae
  adsl$TRTA <- adsl$TRT01A   # the column group is TRTA; the denominator needs it
  composer::table(title = "AE of Special Interest Summary", population = "Safety Analysis Set",
    bigN_format = "xxx", total_col = "nested",
    data = adae, denominator = composer::make_denom(adsl, "SAFFL == \'Y\'", "Safety Analysis Set")) |>
    composer::colgroup(composer::by(variable = "TRTA", levels = __ARMS__)) |>
    composer::block_count(label = "SUBJECTS WITH AN AESI", filter = "AESI == \'Y\'", statistic = "{n:xx} ({pct:xx.x})") |>
    composer::compose()
}'

# --- scorer -----------------------------------------------------------------
score_fn <- function(fn_text, dm) {
  fn_text <- gsub("__ARMS__", ARMS, fn_text, fixed = TRUE)
  fn <- tryCatch(eval(parse(text = fn_text)), error = function(e) e)
  if (inherits(fn, "error")) return(data.frame(stage = "PARSE-ERR", detail = conditionMessage(fn)))
  res <- tryCatch(suppressWarnings(suppressMessages(fn(dm))), error = function(e) e)
  if (inherits(res, "error")) return(data.frame(stage = "EVAL-ERR", detail = substr(conditionMessage(res), 1, 160)))
  eff <- tryCatch(data_effect(NULL, res), error = function(e) paste("eff-err:", conditionMessage(e)))
  pop <- grepl("^populated", eff)
  data.frame(stage = if (pop) "OK-POPULATED" else "RAN-NOT-POP",
             detail = substr(eff, 1, 140))
}

cat("================= COMPOSER ADJUSTMENT PILOT (8) =================\n")
for (nm in names(cases)) {
  s <- score_fn(cases[[nm]], adam_dm)
  cat(sprintf("\n[%-16s] %s\n   %s\n", nm, s$stage, s$detail))
}
cat("\n================= END =================\n")
