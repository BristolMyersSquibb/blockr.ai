# Harness comparison benchmark

Compares the discovery harnesses — `legacy` (the current loop) and `ellmer`
(Design A) — on the same cases and models, grading
the **result data** so it is harness- and model-agnostic.

Cases centre on the headline class: `blockr.extra`'s `code_block` /
`function_block`, where configuration is freeform R in a single `fn` field.

## Files

- `cases.R` — `eval_cases()`: the graded test cases.
- `run-eval.R` — `run_one()`, `run_eval()`, `sweep_eval()`, `summarise_eval()`.
- `selftest.R` — headless plumbing check (no key): drives the real `code_block`
  + real validation + runner + grading with only the model faked. Run with
  `Rscript benchmarks/eval/selftest.R`.

## Headless self-test (no key)

```sh
Rscript benchmarks/eval/selftest.R
# -> SELFTEST PASSED: real code_block configured + validated + graded headless.
```

## Live sweep (needs a model key)

```r
pkgload::load_all(".")
source("benchmarks/eval/cases.R")
source("benchmarks/eval/run-eval.R")

# Models: dev tier GPT-5.4 nano, end test GPT-5.1 (set OPENAI_API_KEY).
res <- sweep_eval(
  cases     = eval_cases(),
  harnesses = c("ellmer", "legacy"),
  models    = c("gpt-5.4-nano", "gpt-5.1"),
  n         = 5
)
summarise_eval(res)
```

`summarise_eval()` reports correctness rate, success rate, and mean latency per
beat `legacy` at the *same* model — if `legacy` on a modern model already
matches them, the win was the model, not the harness (see
`blockr.design/open/rewrite-blockr-ai/3-design-comparison.md`).

## Metrics

v1 records correctness, success, and wall-clock latency. Turns-to-termination
and probe activation (the historically dominant variable) are worth adding next
— `legacy` exposes probe counts via its backend; the `ellmer` harness would need
to read ellmer's turn count.

## Models

| Tier | Model | Role |
|---|---|---|
| Dev | `gpt-5.4-nano` (fallback `gpt-5.4-mini`) | bulk of sweeps |
| End test | `gpt-5.1` | production parity |
