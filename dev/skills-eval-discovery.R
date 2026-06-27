# Can the assistant find the right template from a DESCRIPTION (no template id)?
#   cd /tmp && Rscript --vanilla /workspace/blockr.ai/dev/skills-eval-discovery.R
readRenviron("/workspace/.Renviron")
.libPaths("/workspace/blockr.dev/.devcontainer/.library")
suppressMessages({
  pkgload::load_all("/workspace/blockr.extra", quiet = TRUE)
  pkgload::load_all("/workspace/blockr.dm", quiet = TRUE)
  pkgload::load_all("/workspace/blockr.sandbox", quiet = TRUE)
  pkgload::load_all("/workspace/blockr.ai", quiet = TRUE)
})
options(blockr.skill_library = system.file("skills", package = "blockr.sandbox"))
adsl <- as.data.frame(dm::pull_tbl(readRDS("/tmp/adam_dm.rds"), "adsl"))

detail <- function(cl) {
  tn <- character(); fp <- character()
  for (t in cl$get_turns()) for (ct in t@contents) if (inherits(ct, "ellmer::ContentToolRequest")) {
    tn <- c(tn, ct@name)
    if (ct@name == "read_skill_file") fp <- c(fp, ct@arguments$path %||% "")
  }
  list(tools = paste(unique(tn), collapse = ","), tmpl = paste(fp, collapse = ";"))
}

asks <- c(
  "I want a demographics / baseline characteristics table for this data.",
  "Give me a summary of serious adverse events.",
  "I need a concomitant medications summary table."
)
for (ask in asks) {
  blk <- new_function_block(fn = function(data) data)
  cl <- ellmer::chat_openai(model = "gpt-5.1", echo = "none")
  res <- tryCatch(discover_block_args(prompt = ask, block = blk, data = adsl, client = cl),
                  error = function(e) list(success = FALSE))
  d <- detail(cl); fn <- res$args$fn %||% ""
  eff <- tryCatch(data_effect(NULL, res$result), error = function(e) "")
  cat(sprintf("\nASK: %s\n  tools: %s\n  template: %s\n  composer=%s success=%s\n  effect: %s\n",
              substr(ask, 1, 50), d$tools, if (nzchar(d$tmpl)) d$tmpl else "(none)",
              grepl("composer::", fn), isTRUE(res$success), substr(eff, 1, 90)))
}
