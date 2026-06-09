# Headless plumbing check for the benchmark runner (no model key needed).
#
# Drives the REAL code_block + real validation + runner + grading, faking only
# the model: a fake chat scripts a correct `fn`, and we assert the runner grades
# it correct. Proves the eval pipeline end to end minus the LLM.
#
#   Rscript benchmarks/eval/selftest.R

suppressMessages(suppressWarnings({
  pkgload::load_all(".", quiet = TRUE)
  library(blockr.extra)
}))
source("benchmarks/eval/cases.R")
source("benchmarks/eval/run-eval.R")

# Fake ellmer client: on chat(), call validate_config with a correct fn.
make_fake_chat <- function(config) {
  tools <- NULL
  list(
    set_system_prompt = function(p) invisible(NULL),
    set_tools = function(t) { tools <<- t; invisible(NULL) },
    chat = function(msg, ...) {
      vt <- Find(function(td) isTRUE(td@name == "validate_config"), tools)
      if (!is.null(vt)) vt(config = config)
      "Returned the first 3 rows."
    }
  )
}

fake <- make_fake_chat('{"fn": "function(data) { utils::head(data, 3) }"}')
options(blockr.chat_function = list("selftest-model" = function() fake))

case <- Find(function(c) c$id == "code_head3", eval_cases())
res <- run_eval(list(case), harness = "ellmer", model = "selftest-model", n = 1L)

cat("\n=== selftest result ===\n")
print(res[, c("id", "harness", "model", "success", "correct", "secs")])

if (!isTRUE(res$correct[1])) {
  stop("SELFTEST FAILED: real code_block pipeline did not grade correct\n",
       "error: ", res$error[1])
}
cat("\nSELFTEST PASSED: real code_block configured + validated + graded headless.\n")
