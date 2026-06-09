# LIVE composer-adjustment eval — runs the real blockr.ai assistant (gpt-5.1)
# via discover_block_args against the safetyData ADaM dm. Each case sets the
# picked template as the block's current fn, then asks the model to adjust it to
# the data. Scored by composer data_effect (placeholder => not populated).
#
#   cd /tmp && Rscript --vanilla /workspace/blockr.ai/dev/composer-eval-live.R
readRenviron("/workspace/.Renviron")                 # OPENAI_API_KEY (--vanilla skips .Renviron)
.libPaths("/workspace/blockr.dev/.devcontainer/.library")
suppressMessages({
  pkgload::load_all("/workspace/blockr.extra", quiet = TRUE)
  pkgload::load_all("/workspace/blockr.dm", quiet = TRUE)
  pkgload::load_all("/workspace/blockr.sandbox", quiet = TRUE)
  pkgload::load_all("/workspace/blockr.ai", quiet = TRUE)
})
adam_dm <- readRDS("/tmp/adam_dm.rds")
MODEL <- "gpt-5.1"

# Each case: the template the user picked + the natural-language adjust request.
cases <- list(
  list(id = "GS_CSR_AE_T_001_teae",      ask = "Adjust this treatment-emergent adverse event summary to the connected data."),
  list(id = "GS_CSR_DM_T_003",           ask = "Adjust this demographics table to the connected data."),
  list(id = "GS_CSR_DS_T_003",           ask = "Adjust this subject disposition summary to the connected data."),
  list(id = "GS_CSR_FI_T_003_biomarker", ask = "Adjust this lab change-from-baseline summary to the connected data."),
  list(id = "GS_CSR_AE_T_001_serious",   ask = "Adjust this serious adverse event summary to the connected data."),
  list(id = "GS_CSR_DM_T_003",           ask = "Adjust this demographics table to the data, AND expose the treatment arms as a multi-select so the user can drop an arm."),
  list(id = "GS_CSR_CM_T_003",           ask = "Adjust this concomitant medication summary to the connected data."),
  list(id = "GS_CSR_AE_T_001_aesi",      ask = "Adjust this adverse-events-of-special-interest summary to the connected data.")
)

`%||%` <- function(a, b) if (is.null(a) || !nzchar(as.character(a)[1])) b else a

score_result <- function(res) {
  if (isTRUE(res$success) && !is.null(res$result)) {
    eff <- tryCatch(data_effect(NULL, res$result), error = function(e) paste("eff-err:", conditionMessage(e)))
    pop <- grepl("^populated", eff)
    return(list(stage = if (pop) "OK-POPULATED" else "RAN-NOT-POP", detail = substr(eff, 1, 130)))
  }
  list(stage = if (!is.null(res$question)) "ASKED" else "FAILED",
       detail = substr(res$question %||% res$message %||% res$error %||% "(no detail)", 1, 200))
}

cat("================= LIVE COMPOSER EVAL (gpt-5.1) =================\n")
results <- list()
for (i in seq_along(cases)) {
  cs <- cases[[i]]
  blk <- new_composer_function_block(fn = composer_template_fn(cs$id))
  client <- ellmer::chat_openai(model = MODEL, echo = "none")
  res <- tryCatch(
    discover_block_args(prompt = cs$ask, block = blk, data = adam_dm, client = client),
    error = function(e) list(success = FALSE, error = conditionMessage(e))
  )
  s <- score_result(res)
  results[[i]] <- list(id = cs$id, stage = s$stage, detail = s$detail, fn = res$args$fn)
  cat(sprintf("\n[%d] %-26s %s\n    %s\n", i, cs$id, s$stage, s$detail))
}
saveRDS(results, "/tmp/composer-eval-live-results.rds")
cat("\n================= END (saved /tmp/composer-eval-live-results.rds) =================\n")
