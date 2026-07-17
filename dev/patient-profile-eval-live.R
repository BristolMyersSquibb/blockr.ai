# LIVE eval of the PATIENT PROFILE / patient builder block (blockr.pharma). Class C (clinical quality) + Class D (observability: result is the dm
# passed through; the real artifact is the CONFIG -- `selected` viz IDs +
# viz_settings). So we score res$args (config-correctness vs the clinical ask),
# NOT data_effect. Input: a single-patient safetyData ADaM dm (the CDISC
# Alzheimer's pilot -- has ADAS/NPI-X/labs the block needs).
#   cd /tmp && Rscript --vanilla /workspace/blockr.ai/dev/patient-profile-eval-live.R
readRenviron("/workspace/.Renviron")
.libPaths("/workspace/blockr.dev/.devcontainer/.library")
suppressMessages({
  library(dm)
  pkgload::load_all("/workspace/blockr.dm", quiet = TRUE)
  pkgload::load_all("/workspace/blockr.pharma", quiet = TRUE)
  pkgload::load_all("/workspace/blockr.ai", quiet = TRUE)
})
MODEL <- "gpt-5.4"
# Do NOT build a client here and pass it to discover_block_args(): the system
# prompt is only assembled when `client` is NULL, so a hand-built client ran
# the model with NO block guidance at all and this eval silently measured
# nothing. discover_via_ellmer_tools() now errors on that; select the model
# with the option instead and let the harness build the client.
options(blockr.ai_model = MODEL)
# The AI probes data through blockr.core::eval_env(), which attaches nothing
# beyond base unless this is set. Prod sets it (blockr.sandbox/app.R).
options(blockr.attach_default_packages = TRUE)
`%||%` <- function(a, b) if (is.null(a) || (length(a) == 1 && !nzchar(as.character(a)))) b else a

# --- single-patient dm from the safetyData ADaM universe --------------------
full <- readRDS("/tmp/adam_dm.rds")
tbls <- dm::dm_get_tables(full)
# pick a patient with AEs and labs
ae_ids <- unique(tbls$adae$USUBJID)
one <- ae_ids[1]
keep <- c("adsl", "adae", "adlbc", "adlbh", "advs", "adqsadas", "adqsnpix")
filt <- lapply(tbls[keep], function(t) if ("USUBJID" %in% names(t)) t[t$USUBJID == one, , drop = FALSE] else t)
# safetyData ships no ACTARM and the block now requires an arm (board option
# or ACTARM), so every case failed 0/6 on the arm error alone -- nothing to do
# with the model. TRT01A is this study's arm.
filt$adsl$ACTARM <- filt$adsl$TRT01A
pp_dm <- do.call(dm::dm, filt)
cat("single-patient dm:", one, "| adae rows:", nrow(filt$adae),
    "| adlbc PARAMCDs:", length(unique(filt$adlbc$PARAMCD)), "\n\n")

# --- clinical cases: prompt -> viz IDs a good config should include ---------
cases <- list(
  list(ask = "Show this patient's liver function and any adverse events.",        want = c("liver_panel", "ae_gantt")),
  list(ask = "I'm worried about renal/kidney toxicity for this patient.",          want = c("renal_panel")),
  list(ask = "Show the cognitive trajectory (ADAS-Cog) over time.",                want = c("adas_trajectory")),
  list(ask = "Show blood pressure and pulse over the course of the study.",        want = c("blood_pressure", "pulse")),
  list(ask = "Give me a safety overview: treatment timeline and adverse events.",  want = c("patient_overview", "ae_gantt")),
  list(ask = "Check this patient's electrolyte balance (sodium, potassium).",      want = c("electrolytes"))
)

cat("================= PATIENT PROFILE EVAL (", MODEL, ") =================\n")
for (i in seq_along(cases)) {
  cs <- cases[[i]]
  blk <- new_patient_profile_block()
  res <- tryCatch(discover_block_args(prompt = cs$ask, block = blk, data = pp_dm),
                  error = function(e) list(success = FALSE, error = conditionMessage(e)))
  sel <- unlist(res$args$selected %||% character())
  hit <- cs$want[cs$want %in% sel]
  miss <- setdiff(cs$want, sel)
  verdict <- if (length(sel) == 0) "NO-CONFIG" else if (!length(miss)) "GOOD" else "PARTIAL"
  cat(sprintf("\n[%d] %-28s %s\n", i, verdict, substr(cs$ask, 1, 50)))
  cat("    selected:", paste(sel, collapse = ", "), "\n")
  cat("    want:", paste(cs$want, collapse = ", "), "| hit:", paste(hit, collapse = ","),
      if (length(miss)) paste("| MISSING:", paste(miss, collapse = ",")) else "", "\n")
}
cat("\n================= END =================\n")
