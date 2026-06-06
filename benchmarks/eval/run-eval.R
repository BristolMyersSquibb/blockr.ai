# Benchmark runner for the harness comparison.
#
# Slots the harnesses (legacy / ellmer) and models into one sweep
# and grades the result data per case. Reuses the package's discover_block_args.
#
# Usage (live; needs a model key):
#   pkgload::load_all(".")
#   source("benchmarks/eval/cases.R"); source("benchmarks/eval/run-eval.R")
#   res <- sweep_eval(
#     cases    = eval_cases(),
#     harnesses = c("legacy", "ellmer"),
#     models    = c("gpt-5.4-nano", "gpt-5.1"),
#     n = 5
#   )
#   summarise_eval(res)
#
# Headless plumbing check (no key): benchmarks/eval/selftest.R

# Run one case once under a given harness. Returns a one-row data.frame.
run_one <- function(case, harness, verbose = FALSE) {
  t0 <- Sys.time()
  res <- tryCatch(
    blockr.ai::discover_block_args(
      prompt  = case$prompt,
      block   = case$make_block(),
      data    = case$data,
      harness = harness,
      verbose = verbose
    ),
    error = function(e) list(success = FALSE, error = conditionMessage(e))
  )
  secs <- as.numeric(difftime(Sys.time(), t0, units = "secs"))

  correct <- FALSE
  if (isTRUE(res$success)) {
    correct <- tryCatch(isTRUE(case$grade(res$result)),
                        error = function(e) FALSE)
  }

  data.frame(
    id      = case$id,
    harness = harness,
    success = isTRUE(res$success),
    correct = correct,
    secs    = round(secs, 2),
    error   = res$error %||% NA_character_,
    stringsAsFactors = FALSE
  )
}

`%||%` <- function(x, y) if (is.null(x)) y else x

# Run all cases under one harness/model, n times each.
run_eval <- function(cases, harness, model = NULL, n = 1L, verbose = FALSE) {
  do_run <- function() {
    rows <- list()
    for (rep in seq_len(n)) {
      for (case in cases) {
        row <- run_one(case, harness, verbose = verbose)
        row$model <- model %||% NA_character_
        row$rep <- rep
        rows[[length(rows) + 1L]] <- row
      }
    }
    do.call(rbind, rows)
  }
  if (is.null(model)) {
    do_run()
  } else {
    withr::with_options(list(blockr.ai_model = model), do_run())
  }
}

# Full sweep over harnesses x models.
sweep_eval <- function(cases, harnesses, models = list(NULL), n = 1L,
                       verbose = FALSE) {
  rows <- list()
  for (h in harnesses) {
    for (m in models) {
      rows[[length(rows) + 1L]] <- run_eval(cases, h, model = m, n = n,
                                            verbose = verbose)
    }
  }
  do.call(rbind, rows)
}

# Aggregate: correctness rate, mean latency, success rate by harness x model.
summarise_eval <- function(res) {
  key <- paste(res$harness, res$model, sep = " @ ")
  agg <- lapply(split(res, key), function(d) {
    data.frame(
      group   = paste(d$harness[1], d$model[1], sep = " @ "),
      n       = nrow(d),
      correct = round(mean(d$correct), 3),
      success = round(mean(d$success), 3),
      mean_s  = round(mean(d$secs), 2),
      stringsAsFactors = FALSE
    )
  })
  out <- do.call(rbind, agg)
  rownames(out) <- NULL
  out[order(-out$correct, out$mean_s), ]
}
