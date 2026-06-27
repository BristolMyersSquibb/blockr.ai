# The actual user story: a PLAIN function block connected to pharmaverseadam adsl.
# User: "I want a composer demographics table, template GS_CSR_DM_T_003, produce
# it for this data." The assistant should pick the template via the skill AND
# adapt it to the data (template uses TRTA; this data has TRT01A) so it RENDERS.
#
#   cd /tmp && Rscript --vanilla /workspace/blockr.ai/dev/skills-eval-story.R
readRenviron("/workspace/.Renviron")
.libPaths("/workspace/blockr.dev/.devcontainer/.library")
suppressMessages({
  pkgload::load_all("/workspace/blockr.extra", quiet = TRUE)
  pkgload::load_all("/workspace/blockr.dm", quiet = TRUE)
  pkgload::load_all("/workspace/blockr.sandbox", quiet = TRUE)  # for composer + data_effect
  pkgload::load_all("/workspace/blockr.ai", quiet = TRUE)
})
source("/workspace/blockr.ai/dev/skills-eval-build-lib.R")
options(blockr.skill_library = build_skill_eval_lib())
MODEL <- "gpt-5.1"

adsl <- as.data.frame(dm::pull_tbl(readRDS("/tmp/adam_dm.rds"), "adsl"))
cat("adsl:", nrow(adsl), "rows;",
    "treatment cols:", paste(grep("^TRT", names(adsl), value = TRUE), collapse = ", "),
    "\n\n")

blk <- new_function_block(fn = function(data) data)
client <- ellmer::chat_openai(model = MODEL, echo = "none")
res <- discover_block_args(
  prompt = paste("I want a composer demographic characteristics table using",
                 "template GS_CSR_DM_T_003. Produce it for this connected data."),
  block = blk, data = adsl, client = client
)

# What tools did it use, and what did it finally set as fn?
tc_names <- character()
for (t in tryCatch(client$get_turns(), error = function(e) list())) {
  for (ct in tryCatch(t@contents, error = function(e) NULL)) {
    if (inherits(ct, "ellmer::ContentToolRequest")) tc_names <- c(tc_names, ct@name)
  }
}
fn <- res$args$fn %||% ""

cat("================= USER-STORY RESULT =================\n")
cat("success     :", isTRUE(res$success), "\n")
cat("tools used  :", paste(unique(tc_names), collapse = ", "), "\n")
cat("adapted cols: TRT01A present in fn =", grepl("TRT01A", fn),
    "| TRTA still present =", grepl("TRTA", fn), "\n")
if (!is.null(res$result)) {
  eff <- tryCatch(data_effect(NULL, res$result), error = function(e) paste("eff-err:", conditionMessage(e)))
  cat("data_effect :", substr(eff, 1, 160), "\n")
  cat("result class:", paste(class(res$result), collapse = "/"), "\n")
}
if (!isTRUE(res$success)) cat("model said  :", substr(res$question %||% res$error %||% "", 1, 400), "\n")
cat("\n----- FINAL fn (first 1500 chars) -----\n", substr(fn, 1, 1500), "\n")
saveRDS(list(res = res, fn = fn, tools = tc_names), "/tmp/skills-eval-story.rds")
