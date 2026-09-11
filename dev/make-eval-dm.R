# The dm every composer / skills / patient-profile eval in dev/ reads from
# /tmp/adam_dm.rds.
#
# It was a scratch artifact and nothing built it, so a container that had lost
# /tmp could not run any of them ("cannot open file '/tmp/adam_dm.rds'") and
# the shape had to be guessed back out of the cases. This is that shape: the
# safetyData CDISC pilot ADaM tables, keyed on USUBJID.
#
#   Rscript --vanilla /workspace/blockr.ai/dev/make-eval-dm.R
#
# Three tables, because that is what the cases reach for: adsl (254 subjects,
# TRT01A / SAFFL / ITTFL / DCDECOD / DCREASCD), adae (TRTA, AEBODSYS/AEDECOD,
# AESER — and NO AESI column, which case 8 of composer-eval.R depends on), and
# adlbc (PARAM / AVISIT / AVAL / CHG). There is deliberately NO adcm: case 7
# tests that the model reports an impossible ask instead of inventing a table.
.libPaths("/workspace/blockr.dev/.devcontainer/.library")

out <- "/tmp/adam_dm.rds"

adam <- dm::dm(
  adsl  = as.data.frame(safetyData::adam_adsl),
  adae  = as.data.frame(safetyData::adam_adae),
  adlbc = as.data.frame(safetyData::adam_adlbc)
) |>
  dm::dm_add_pk(adsl, "USUBJID") |>
  dm::dm_add_fk(adae, "USUBJID", adsl) |>
  dm::dm_add_fk(adlbc, "USUBJID", adsl)

saveRDS(adam, out)

cat("wrote", out, "\n")
for (nm in names(adam)) {
  t <- as.data.frame(adam[[nm]])
  cat(sprintf("  %-6s %5d rows  %3d cols\n", nm, nrow(t), ncol(t)))
}
cat("  arms:", paste(sort(unique(as.data.frame(adam$adsl)$TRT01A)),
                     collapse = " | "), "\n")
