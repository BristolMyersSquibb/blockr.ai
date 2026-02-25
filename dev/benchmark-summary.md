# Data Exploration Benchmarks — Summary

> Six benchmark rounds (5–10) tested data exploration backends on
> gpt-4o-mini with 8 synthetic filter tests and 9 mixed block tests.
> This page summarises the key findings. For full details see the
> individual design-spec docs and the archived scripts.

## Test Suite

**Filter tests** (F1–F8, used in all rounds):

| # | Test | What it probes |
|---|------|----------------|
| F1 | partial vendor match | prefix matching on coded values |
| F2 | top store by revenue | aggregation — impossible with a filter block |
| F3 | quarter format discovery | `YYYY-QN` format recognition |
| F4 | semantic: emergency cases | semantic column mapping (`case_label`) |
| F5 | above-avg price | compute mean then filter |
| F6 | substring: gmail users | email-domain substring match |
| F7 | Q1 across all years | suffix pattern matching |
| F8 | emergency + high priority | compound condition with semantic labels |

**Mixed block tests** (benchmark 8 only): 3 mutate, 3 function, 2 function-dropdown.

## Benchmark Evolution

| Round | Doc | What changed | Key result |
|-------|-----|-------------|------------|
| 5 | `5-benchmark.md` | Initial 3-backend run (none/manual/structured), then 4-way with equalized prompts | Prompt wording (aggressive preamble) was the dominant factor, not backend format. All exploration backends ~67% with equal prompts. |
| 6 | `6-benchmark-4way.md` | Tools prompt also equalized; 4-way re-run | Structured 75%, manual 55%, tools 58% — but gap not robust at n=5. Probe activation rate identified as the real variable. |
| 7 | `7-benchmark-balanced.md` | Balanced (softer) preamble tested | No speed savings on easy tests (LLM already skipped probes). Structured got faster but less accurate — net efficiency flat. Aggressive prompt retained. |
| 8 | `8-benchmark-mixed.md` | Mutate + function blocks added; dropdown prompt tuned | Mutate 100% without exploration. Function blocks mirror filter on semantic tasks. Named-vector emphasis fixed dropdown tests. |
| 9a | `9-benchmark-tools-vs-manual.md` | Manual vs tools h2h, n=10 | Manual 50% vs tools 45%, manual 1.32x faster. Tools lacks probe counting. |
| 9b | `9-benchmark-gpt-oss-20b.md` | Same tests on local Qwen-2.5 20B | Text-based backends fail on weaker model (25%). Tools only viable option (50%). Backend choice is model-dependent. |
| 10 | `10-benchmark-definitive.md` | Manual vs tools, n=20, probe counting fixed for tools | Manual 54% vs tools 49% (p=0.434, not significant). Manual 1.68x faster. Probe activation confirmed as dominant variable. |

## Final Numbers (Benchmark 10, n=20)

| Backend | Correct | Rate | Avg Time | Avg Probes | Probe Act% |
|---------|---------|------|----------|------------|------------|
| manual | 86/160 | 54% | 13.2s | 0.7 | 47% |
| tools | 78/160 | 49% | 22.2s | 0.7 | 52% |

Correctness difference: p = 0.434 (Fisher exact, two-sided). Not significant.

Speed: manual is **1.68x faster** overall. The gap is driven by F5 (above-avg price) where tools is 2.44x slower with high variance.

## Core Insight: Probe Activation Dominates

The strongest signal across all rounds is not *which* backend the LLM uses, but *whether it probes at all*:

| Test | Correct when probed | Correct when not probed |
|------|--------------------|-----------------------|
| F1 (vendor match) | 100% | 0% |
| F5 (above-avg price) | 94% | 33% |
| F6 (gmail users) | 74% | 0% |

Backend format (code blocks vs JSON envelope vs tool calling) is secondary. The aggressive exploration preamble is responsible for the bulk of the improvement over `none`.

## Per-Test Best Results (across all rounds)

| Test | Best rate | Backend | Round |
|------|-----------|---------|-------|
| F1. partial vendor match | 100% | tools | 5 (run 2) |
| F2. top store by revenue | 0% | all | — (impossible) |
| F3. quarter format discovery | 100% | all | all |
| F4. semantic: emergency cases | 60% | structured | 6 |
| F5. above-avg price | 100% | manual/structured | 5 (run 2), 6 |
| F6. substring: gmail users | 80% | tools/structured | 5 (run 2), 6 |
| F7. Q1 across all years | 100% | all | all |
| F8. emergency + high priority | 80% | structured | 6 |
| Mutate (all 3) | 100% | none/manual | 8 |
| Function (structural) | 100% | none/manual | 8 |
| Function (semantic) | 20% | both | 8 |
| Dropdown (after fix) | 100% | manual | 8 |

## Recommendations

1. **Default backend: `manual`** — equivalent accuracy to tools, 1.68x faster, visible probe round-trips for debugging.
2. **For open-source/local models: `tools`** — text-based exploration fails on weaker models; native tool calling is the only viable option.
3. **A/B testing**: use `BLOCKR_DATA_EXPLORATION=tools` env var to compare backends in production.
4. **Prompt wording matters most** — the aggressive "IMPORTANT: Before answering, explore the data" preamble is retained. The balanced variant provided no benefit.

## References

- **Design specs**: `blockr.design/open/data-exploration/5-benchmark.md` through `10-benchmark-definitive.md`
- **Scripts and output**: `benchmarks/data-exploration/`
- **Backend implementation**: `blockr.ai/R/backend-data.R`
- **Configuration docs**: `blockr.ai/dev/spec/07-data-exploration.md`
