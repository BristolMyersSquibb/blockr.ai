# Trace what the model SUBMITS to validate_config for the demographics story, to
# see whether it applies the template as-is (works) or over-adapts it (breaks).
readRenviron("/workspace/.Renviron")
.libPaths("/workspace/blockr.dev/.devcontainer/.library")
suppressMessages({
  pkgload::load_all("/workspace/blockr.extra", quiet = TRUE)
  pkgload::load_all("/workspace/blockr.dm", quiet = TRUE)
  pkgload::load_all("/workspace/blockr.sandbox", quiet = TRUE)
  pkgload::load_all("/workspace/blockr.ai", quiet = TRUE)
})
source("/workspace/blockr.ai/dev/skills-eval-build-lib.R")
options(blockr.skill_library = build_skill_eval_lib())
adsl <- as.data.frame(dm::pull_tbl(readRDS("/tmp/adam_dm.rds"), "adsl"))

blk <- new_function_block(fn = function(data) data)
client <- ellmer::chat_openai(model = "gpt-5.1", echo = "none")
res <- discover_block_args(
  prompt = paste("I want a composer demographic characteristics table using",
                 "template GS_CSR_DM_T_003. Produce it for this connected data."),
  block = blk, data = adsl, client = client
)

n <- 0
for (t in client$get_turns()) {
  for (ct in t@contents) {
    if (inherits(ct, "ellmer::ContentToolRequest") && identical(ct@name, "validate_config")) {
      n <- n + 1
      fn <- ct@arguments$fn %||% "(no fn arg)"
      # is this fn the raw mock shell, or rewritten?
      mock <- grepl("trt_levels|_levels <-", fn)
      cat(sprintf("\n--- validate_config attempt %d (mock-shell=%s, nchar=%d) ---\n",
                  n, mock, nchar(fn)))
      cat(substr(fn, 1, 220), "...\n")
    }
    if (inherits(ct, "ellmer::ContentToolResult")) {
      v <- paste(as.character(tryCatch(ct@value, error = function(e) "")), collapse = " ")
      if (grepl("\"ok\"|error|NULL|effect|populated", v)) {
        cat("    RESULT:", substr(gsub("\\s+", " ", v), 1, 200), "\n")
      }
    }
  }
}
cat("\n==> final success:", isTRUE(res$success), "| attempts:", n, "\n")
