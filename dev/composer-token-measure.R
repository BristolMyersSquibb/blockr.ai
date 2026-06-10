# composer-token-measure.R — measure the composer-AI prompt token blowout.
#
# No OPENAI key and no prod data needed. Builds a SYNTHETIC prod-shaped wide dm
# (real public CDISC column NAMES parsed from the committed SDR log, fully
# synthetic values) and assembles the prompt pieces blockr.ai sends, then splits
# the budget into system-prompt (inlined API doc) vs schema-dump vs current-state
# and simulates the 6-turn demographics session.
#
#   cd /tmp && Rscript --vanilla /workspace/blockr.ai/dev/composer-token-measure.R
#
# Token estimate: ~4 chars/token (standard GPT-family rule of thumb; no local
# tokenizer in this container). Reported as est-tokens alongside raw chars.

.libPaths("/workspace/blockr.dev/.devcontainer/.library")
suppressMessages({
  pkgload::load_all("/workspace/blockr.ai", quiet = TRUE)   # data_preview, build_tool_system_prompt
  pkgload::load_all("/workspace/blockr.dm", quiet = TRUE)   # data_schema.dm (the schema renderer)
})

REPORT  <- "/workspace/team-ops/tasks/attachments/composer-ai-sdr/blockr-ai-report demographics.txt"
DOC_BASE<- "/workspace/blockr.extra/inst/prompts/function-block.md"
DOC_COMP<- "/workspace/blockr.sandbox/inst/prompts/composer-function-block.md"
slurp   <- function(f) paste(readLines(f, warn = FALSE), collapse = "\n")
toks    <- function(x) round(nchar(x) / 4)
fmt     <- function(label, x) sprintf("  %-26s %8d chars  ~%7d tok", label, nchar(x), toks(x))

## ---- 1. synthetic prod-shaped wide dm (column names parsed from the log) ----
parse_schema <- function(path) {
  ln  <- readLines(path, warn = FALSE)
  hdr <- grep("^## [a-z]", ln)
  out <- list()
  for (i in hdr) {
    nm <- sub("^## ", "", ln[i])
    if (!is.null(out[[nm]])) next
    cols <- trimws(strsplit(ln[i + 1L], ",")[[1]])
    out[[nm]] <- unique(cols[nzchar(cols)])
  }
  out[grepl("^ad", names(out))]   # the ADaM tables only (skip stray md headers)
}
schema <- parse_schema(REPORT)
mk_tbl <- function(cols, n = 5L) {
  cols <- union(cols, "USUBJID")
  df <- as.data.frame(setNames(lapply(cols, function(z) rep("x", n)), cols),
                      stringsAsFactors = FALSE, check.names = FALSE)
  df$USUBJID <- paste0("S", seq_len(n))
  df
}
tbls    <- lapply(schema, mk_tbl)
wide_dm <- dm::as_dm(tbls)
wide_dm <- dm::dm_add_pk(wide_dm, adsl, USUBJID)
for (child in setdiff(names(tbls), "adsl"))
  wide_dm <- dm::dm_add_fk(wide_dm, !!child, USUBJID, adsl)

cat("Synthetic wide dm (prod shape, from the SDR log):\n")
for (n in names(wide_dm)) cat(sprintf("  %-9s %3d cols\n", n, ncol(wide_dm[[n]])))

## ---- 2. prompt pieces ----
# System prompt = blockr.ai boilerplate + the inlined API doc (base + composer).
# The inlined API doc is composer_function_block_prompt() = function-block.md +
# composer-function-block.md; that doc is the "fully self-contained" payload.
api_doc      <- paste0(slurp(DOC_BASE), "\n\n", slurp(DOC_COMP))
schema_dump  <- data_preview(wide_dm)                 # per-turn schema block
demog_fn     <- slurp(textConnection(paste0(
  'function(data) {\n  adsl <- data$adsl\n  composer::table(\n    title = "Demographics",\n',
  '    data = adsl,\n    denominator = composer::make_denom(adsl, pop = "SAFFL", trt = "TRT01A")\n  ) |>\n',
  '    composer::colgroup(composer::by(variable = "TRT01A", levels = sort(unique(adsl$TRT01A)))) |>\n',
  '    composer::block_continuous(label = "Age", variable = "AGE", statistic = c("{N:xxx}","{mean:xx.x}")) |>\n',
  '    composer::compose() -> t\n  t$formatted_table\n}')))
state_block  <- format_current_state(list(fn = demog_fn))
task_block   <- "# Task\n\nUse TRT02A instead"

cat("\n=== Per-piece sizes (synthetic wide prod-shaped dm) ===\n")
cat(fmt("inlined API doc (system)", api_doc), "\n")
cat(fmt("schema dump (per turn)",   schema_dump), "\n")
cat(fmt("current-state (per turn)", state_block), "\n")
cat(fmt("task (per turn)",          task_block), "\n")

# API-doc breakdown by output family (the report's failures are ALL tables; the
# listing/figure/export references are dead weight for a table session yet ride
# along in the system prompt re-read on every API call).
comp_md <- readLines(DOC_COMP, warn = FALSE)
fam_tok <- function(a, b) round(sum(nchar(comp_md[a:b]) + 1) / 4)
cat("\n  API doc by output family (composer md):\n")
cat(sprintf("    tables    ~%5d tok  (kept)\n",   fam_tok(1, 355)))
cat(sprintf("    listings  ~%5d tok  (unused by a table task)\n", fam_tok(356, 500)))
cat(sprintf("    figures   ~%5d tok  (unused by a table task)\n", fam_tok(501, 619)))
cat(sprintf("    export    ~%5d tok  (unused by a table task)\n", fam_tok(620, length(comp_md))))

## ---- 3. multi-turn simulation (the live block reuses ONE client) ----
# ai-ctrl-block.R reuses one client across prompts (client <<- result$client);
# the system prompt / API doc is set ONCE, but each user turn re-appends
# data_preview + current_state + task. So the context window at turn N (the part
# blockr.ai controls) is:  api_doc  +  sum_turns(schema + state + task).
# The committed demographics session ran N = 6 turns.
N <- 6
per_turn_now <- paste0(schema_dump, state_block, task_block)  # full schema every turn
window_now   <- toks(api_doc) + N * toks(per_turn_now)
# AFTER (this fix): full schema only on turn 1; later turns send a one-line
# pointer (the model keeps the schema in history + can data_query). state+task
# still per turn.
ptr <- paste0("# Input Data\n\n(unchanged from the first message above -- use ",
              "data_query to inspect any table or column)\n\n")
turn1     <- paste0(schema_dump, state_block, task_block)
turn_rest <- paste0(ptr, state_block, task_block)
window_fix<- toks(api_doc) + toks(turn1) + (N - 1) * toks(turn_rest)

cat(sprintf("\n=== Multi-turn (%d turns) — blockr.ai-controlled context tokens ===\n", N))
cat(sprintf("  %-42s ~%7d tok\n", "BEFORE (schema re-sent every turn):", window_now))
cat(sprintf("    = api_doc(%d) + %d turns x [schema(%d)+state(%d)+task(%d)]\n",
            toks(api_doc), N, toks(schema_dump), toks(state_block), toks(task_block)))
cat(sprintf("  %-42s ~%7d tok   (-%d tok, schema sent once)\n",
            "AFTER  (schema sent once):", window_fix, window_now - window_fix))
cat("  NOTE: assistant replies + every data_query / validate_config tool RESULT\n")
cat("  accumulate ON TOP of this (and equally before/after); the model also re-reads\n")
cat("  the api_doc as the system message on EVERY API call. This is the floor that\n")
cat("  blockr.ai itself controls; the log shows the real session hit ~285k > 272k.\n")

## ---- 4. no-regression check ----
# The fix is in the harness (schema sent once), NOT in data_preview/data_schema:
# the first-turn message is byte-identical, so single-turn eval cases (incl. the
# whole safetyData composer-eval-live.R suite, all one-shot) generate the same fn.
# Only multi-turn sessions change, and only by NOT re-dumping the schema.
if (file.exists("/tmp/adam_dm.rds")) {
  adam <- readRDS("/tmp/adam_dm.rds")
  cat("\n=== safetyData dm (narrow) — first-turn preview is unchanged by the fix ===\n")
  cat(sprintf("  widest table: %d cols\n",
              max(vapply(names(adam), function(n) ncol(adam[[n]]), 1L))))
  cat(fmt("schema dump", data_preview(adam)), "\n")
}
