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

Make **ellmer (A) the harness**. It was first shipped as the default with legacy
as a one-flag fallback; the **legacy loop and its `backend-data.R` machinery were
then removed** once ellmer was validated beyond code/function blocks — a
cross-block smoke test (`benchmarks/eval/smoke-blocks.R`, gpt-5.1) passed on the
state-wrapper filter, select/summarize/mutate, a non-data.frame ggplot result,
conversation memory, and a `dm`. B (agent-sdk) stays an experiment on the
`feat/harness-ellmer-and-agent-sdk` branch (it needs a strong Claude model and a
sidecar/proxy to be worth its weight).

## Reconciliation with the early-2026 benchmarks

The earlier work ([benchmark-summary.md](benchmark-summary.md)) -- experiments
run in early 2026 (rounds 1–10, written up February 2026) -- concluded the
*opposite* of this — "default to the `manual` text backend; ellmer's native
tool-calling isn't clearly worth it." That is not a contradiction; three things
changed, and the old data pointed this way:

- **Different question.** Then: which data-exploration *backend* inside the JSON
  loop (the config was free-text JSON in every arm). Now: the whole *harness* —
  tool-calling where *validation itself* is a tool. The old `tools` only
  tool-ified exploration; the new design tool-ifies the entire loop.
- **Different model.** Then gpt-4o-mini / Qwen-20B; now gpt-5.4-nano / gpt-5.1.
  The old report itself said *"backend choice is model-dependent; tools is the
  only viable option on weaker models"* — i.e. it forecast that stronger models
  flip the result. Its deepest claim (probe activation + prompt + **model**
  dominate, not format) is exactly the lever that moved.
- **Different metric.** The new win is largely **reliability of producing a valid
  config** (legacy 66% vs ellmer 97% success) — legacy wedges. The old benchmark
  measured exploration-backend correctness, not failure-to-produce-config.

Two design questions from back then, revisited:

- **ellmer vs handcraft → ellmer.** Legacy *was* the handcrafted answer (a
  hand-rolled loop on `ellmer::chat()`). With ellmer's tool loop matured and
  frontier models invoking tools reliably, the control bought by handcrafting
  isn't worth the maintenance — so the handcrafted loop is gone. And the
  agent-SDK experiment shows "don't handcraft" doesn't mean "go maximal": a
  heavyweight agent framework *lost* on cheap models. The sweet spot is the
  middle — a lightweight library (ellmer) that owns the loop.
- **Structured output → mostly sidestepped, deliberately.** The winning harness
  uses tool *calling* (structure at the invocation level) but keeps the config
  payload as **free-text JSON in a `config` string**, not a schema-constrained
  object — because blockr's config is per-block and partly freeform (the code
  block is arbitrary R), and the registry carries argument *descriptions*, not
  types. So the early-2026 "structured isn't a robust win" finding still roughly holds
  for the payload. Strict structured config output is a viable *future*
  refinement only if the registry grows real per-argument types.

## Reproduce

- Headless plumbing (no key): `Rscript benchmarks/eval/selftest.R`
- Live sweep: `benchmarks/eval/run-eval.R` → `sweep_eval(...)` /
  `summarise_eval(...)` (set `OPENAI_API_KEY`; for B-on-GPT run the LiteLLM
  proxy per `inst/agent-sdk/README.md`).
