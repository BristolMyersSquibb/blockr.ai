# Harness comparison — findings

> Design B (agent-sdk) implementation, the LiteLLM proxy setup, and the full
> three-way reproduction live on the `feat/harness-ellmer-and-agent-sdk` branch.
> This branch ships **Design A only**, with `ellmer` as the default harness.

What changed and why: `discover_block_args()` gained a swappable `harness`. This
documents the head-to-head between the three options and the decision that came
out of it.

- **legacy** — the original hand-rolled loop (prompt → JSON → validate → "DONE
  or fix" → repeat).
- **ellmer (Design A)** — native ellmer tool calling: `validate_config` is a
  tool, ellmer drives the loop, the last valid call is the apply.
- **agent-sdk (Design B)** — the real Claude Code loop (`claude -p`, headless)
  driving the same two tools over MCP (`mcptools`).

See `dev/agent-boundary.md` and the spec at
`blockr.design/open/rewrite-blockr-ai/` for the design.

## Method

- **Cases:** 6 graded `blockr.extra` `code_block` / `function_block` tasks
  (`benchmarks/eval/cases.R`) — the freeform-R class, where the constrained loop
  is weakest. Grading is on the **result data**, so it's harness- and
  model-agnostic.
- **Isolation run:** all three harnesses on the **same model**, `gpt-5.4-nano`,
  **n = 20** per case (120 runs/harness, 360 total). B reaches nano through a
  LiteLLM proxy, so this is all OpenAI — no Claude subscription spend.
- **Ceiling reference:** B also run on `claude-sonnet-4-5` (native CLI auth),
  n = 3, to see its best case.
- Metrics: correctness (binomial CI, `prop.test`), success (produced *a* valid
  config), wall-clock.

## Results — same model (gpt-5.4-nano), n = 20

| harness | correct | success | mean s | 95% CI (correct) |
|---|---|---|---|---|
| **ellmer (A)** | **85.8%** | **96.7%** | 4.6 | [78%, 92%] |
| legacy | 65.0% | 65.8% | 2.4 | [56%, 73%] |
| agent-sdk (B) | 49.2% | 50.0% | 9.8 | [40%, 58%] |

All pairwise correctness differences are significant: A vs legacy p = 3.2e-4;
A vs B p = 3.1e-9; B vs legacy p = 0.019.

**By case:**

| case | A | legacy | B |
|---|---|---|---|
| code_head3 | 1.00 | 0.95 | 0.10 |
| code_filter_cyl4 | 0.95 | 0.85 | 0.95 |
| code_add_ratio | 1.00 | 0.60 | 1.00 |
| code_group_mean | 0.90 | 0.55 | 0.00 |
| code_gmail_substring | 0.35 | 0.60 | 0.90 |
| fn_top5_mpg | 0.95 | 0.35 | 0.00 |

**B ceiling (claude-sonnet-4-5, n = 3):** 100% correct, ~26 s/run.

## Interpretation

- **At equal cheap model, A wins decisively** — best correctness (86%), by far
  best reliability (97% success), provider-agnostic, and the lightest to ship
  (in-process; no sidecar/proxy/MCP).
- **B on a cheap model is the worst of the three** — significantly below even
  legacy, and it fails to produce a valid config half the time. The heavier
  Claude Code protocol + MCP round-trips overwhelm nano on the simple cases (it
  can't complete `head3`/`group_mean`/`top5_mpg`), though its harness *is* best
  on the one genuinely hard case (`gmail_substring`, 0.90 vs A's 0.35).
- **B's value is conditional:** it only pays off with a strong Claude model
  (100% on Sonnet) — at ~5x the latency and on a Claude subscription. The
  harness is not a substitute for model capability.
- A is the only harness strong across the board.

## A related fix: validity ≠ goodness

The comparison surfaced that `validate_config` checked *validity* ("does the
block still evaluate?") but not *effect* ("did it do what was asked?"). A valid
config can do nothing — a filter that removes no rows — and the model would
report success. Fixed by `data_effect()` (`R/effect.R`): the validate tool now
returns the row/column diff (`rows: 32 -> 32 (UNCHANGED)`), and the prompt
treats `ok=true` as valid-not-done, so the model must verify the effect. See
`R/effect.R` + `tests/testthat/test-effect.R`.

## Caveats

- Cases are **code/function-block only** — the freeform-R class. Not yet tested:
  the `state`-wrapper filter, `dm` blocks, plots, summarize, images,
  multi-prompt conversation memory. A's win is established for code-shaped
  config, not yet the whole block universe.
- B-on-nano is doubly handicapped (cheap model *and* lost Claude tuning via the
  proxy) — the fair equal-model test, but not B's intended configuration.
- **The untested cell:** A vs B both on a strong model. ellmer-on-Claude needs
  an `ANTHROPIC_API_KEY` (the CLI's OAuth can't drive ellmer). Given A hits 86%
  on nano, A on a strong model is very likely excellent and far faster than B.

## Decision

Make **ellmer (A) the default harness**, keep **legacy as a one-flag fallback**
(`blockr.harness`), and remove legacy later once A is validated across the full
block set in real use. Not a direct replacement yet — flip default → soak →
delete. B stays an experiment (it needs a strong Claude model and infra to be
worth its weight).

## Reproduce

- Headless plumbing (no key): `Rscript benchmarks/eval/selftest.R`
- Live sweep: `benchmarks/eval/run-eval.R` → `sweep_eval(...)` /
  `summarise_eval(...)` (set `OPENAI_API_KEY`; for B-on-GPT run the LiteLLM
  proxy per `inst/agent-sdk/README.md`).
