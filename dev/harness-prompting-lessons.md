# Tuning the blockr.ai assistant: harness + prompting lessons

How to test and improve the way the per-block AI (`discover_block_args` →
`discover_via_ellmer_tools`) configures blocks. Distilled from evaluating the
whole block roster (composer, dplyr, patient profile, drilldown chart + table,
crossfilter, topline flextable) against gpt-5.1.

Companion doc: [`ai-eval-cases.md`](ai-eval-cases.md) — the per-block test-case
registry and status. This doc is the **methodology + lessons**.

---

## TL;DR — the things that actually matter

1. **The registry `example` anchors model behavior far more than the `prompt`
   prose.** Proven ~6× this session. Every time a prompt nudge failed to change
   gpt-5.1, populating/fixing the registry `examples` fixed it. Make examples
   populated, correct, multi-line, `list()`-where-multi, and showing every field
   you want set. This is the single highest-leverage lever.
2. **Run the model, don't just reason about the prompt.** Hand-authoring a config
   masks the failures that dominate in practice (the model not calling the tool,
   mis-shaping arguments, giving up). The live run is where the truth is.
3. **Single runs are noisy.** gpt-5.1 swings GOOD↔PARTIAL run-to-run on subjective
   picks. For a real pass rate, average a few runs; never conclude a prompt change
   worked/failed from one run.
4. **The tool interface matters more than wording.** The biggest composer blocker
   was that the model couldn't hand-serialize a big R function into a JSON-string
   `config`. Fixed by a typed schema (native args), not by prompting.
5. **The AI surface IS the full set of block arguments — always.** There is no
   "expose this to the assistant or not" decision. If something is a block
   argument (configurable state the user can choose), the assistant gets it; the
   only real question is whether it should be a block argument at all (a
   block-DESIGN decision). Don't selectively hide args from the AI; instead shape
   the block's args so the whole surface is clean and writable (flat where
   possible, strings/arrays-of-records over nested ASTs/data-keyed maps). The
   model block proved this: its formula was a nested AST the model could never
   produce (0/5). Making `formula` a plain string and lifting `weights`/`offset`
   to their own top-level args — nothing dropped from the surface — took it to
   5/5.

---

## How to run an eval (practical setup)

- **Always `Rscript --vanilla` from `/tmp`** (the package dirs have renv that
  hijacks `pkgload`). `--vanilla` skips `.Renviron`, so load the key explicitly:
  `readRenviron("/workspace/.Renviron")` (has `OPENAI_API_KEY`).
- **Set the lib:** `.libPaths("/workspace/blockr.dev/.devcontainer/.library")`.
- **Load order matters:** `blockr.extra` → `blockr.dm` → `blockr.sandbox`/`blockr.viz`
  → **`blockr.ai` last is wrong for runtime S3 registration**; load `blockr.ai`
  BEFORE the type-owner package whose `.onLoad` registers methods onto blockr.ai's
  generics (composer-ai-view, drilldown-ai-effect). When in doubt, call the
  package's `register_*` function explicitly after loading both.
- **Background long runs** with a plain `Rscript ... > log 2>&1 &` in a normal
  Bash call (NOT `nohup`, NOT `run_in_background` — those get reaped here), then
  poll the log for an `END` marker with an `until`/`for` loop.
- **Existing eval scripts** in `dev/`: `composer-eval.R` (hand-authored, token-
  free), `composer-eval-live.R`, `dplyr-eval-live.R`, `function-block-eval-live.R`,
  `patient-profile-eval-live.R`, `drilldown-eval-live.R`,
  `drilldown-table-eval-live.R`, `crossfilter-eval-live.R`, `topline-eval-live.R`,
  `topline-select-eval.R`. Copy the closest one.

### Two-tier evaluation
- **Hand-authored (token-free):** *you* write the config and score it. Tests
  whether the PROMPT + data preview contain enough info to succeed. Its failures
  are real prompt gaps; its successes don't prove the model will do it.
- **Live (`discover_block_args` + `chat_openai("gpt-5.1")`):** the real model
  drives the harness. This is the truth. Always confirm here. (You can also act as
  the model yourself for a token-free first pass — your *failures* are real prompt
  gaps regardless of model.)

---

## Classify the block first (the challenge classes)

| Class | Shape | Examples | Scoring |
|---|---|---|---|
| **A Encoding** | one big free-text param (`fn`/code/expr) | composer fn block | populated? (placeholder detector) |
| **B Structured** | small flat/nested params | dplyr, topline flextable | `data_effect` and/or `res$args` |
| **C Clinical/quality** | structured config, but "good" is domain-judged | patient profile | `res$args` + a rubric |
| **D Observability** | result is a passthrough; the CONFIG is the artifact | drilldown chart/table, patient profile, crossfilter-when-empty | `res$args` + `config_effect` |

How to tell D: if the block's result reactive is `identity(data)` / a
passthrough filter, `data_effect` is blind — score `res$args`, and give the model
a `config_effect` (below).

---

## Scoring

- **Transforms (output IS the data):** `data_effect(input, result)` — rows/cols
  diff (incl. the in-place change detector). Works for dplyr, crossfilter (when
  filters set).
- **Composer / rendered tables:** the placeholder/population detector in
  blockr.sandbox `composer-ai-view.R` — residual `xx.x` cells = "NOT populated"
  (the composer analogue of UNCHANGED). This is the pass/fail signal for "did the
  mock template get wired to real data".
- **Control/viz blocks (Class D):** score `res$args` (the config) against what the
  prompt asked — `discover_block_args` records the last applied config even if the
  model ends in prose, so `res$args` is readable regardless of `res$success`.
- **`config_effect`:** for these blocks, the model's in-loop feedback should be the
  config description (see below), not the blind data effect.

---

## The harness (what's shared across all blocks)

All in blockr.ai unless noted. Type-owner packages extend the generics.

- **Typed schema** (`R/param-schema.R`, `block_param_types`): exposes the block's
  params as a native ellmer schema so the model emits structured tool args (the
  API escapes them) instead of hand-building a JSON-string `config`. Inference:
  scalar→string/number/bool, named list→nested object (forces correct `state`
  nesting), char vector / list→array/enum, polymorphic array→JSON-string leaf +
  `reparse_json_strings`. **Prefers the registry `examples` SHAPE over the formal
  default** (decisive when the default is `NULL`/`character()`/`list()` or an
  ambiguous unnamed vector). The fallback to a single JSON-string `config` remains
  for blocks with no inferable params.
- **`data_schema` / `data_effect`** generics: type owners provide methods
  (blockr.dm → dm, blockr.sandbox → composer/gt/flextable). blockr.ai keeps only
  data.frame/default/(ggplot). Before adding a method here, grep the type owner —
  it probably already has it (and leaner).
- **`config_effect(block, args, data)`** (`R/effect.R`): the OBSERVABILITY seam.
  For passthrough/control blocks, describe the CONFIG (and flag invalid column
  bindings) instead of the blind data effect; the validate tool uses it when
  non-NULL. Type owners implement it (e.g. blockr.viz `drilldown-ai-effect.R`).
- **Real error surfacing** (`R/discover.R`, `collect_block_errors`): a block that
  errors evaluating its expr returns NULL with the real error in
  `session$returned$cond$<stage>$error` (a `block_cnd` = a CHARACTER vector with a
  class, NOT a standard condition — use `as.character`, `conditionMessage` has no
  method). Surface it ("Element X doesn't exist") so the model can iterate.
- **Re-prompt loop + mock→real enforcement** (`R/harness-ellmer.R`): models
  routinely describe a config in prose ("here is a config you can paste") and
  never call the tool; or apply a valid-but-empty config. The loop nudges (≤3×)
  when no config landed OR `effect_is_noop(last_effect)` (matches "not populated"
  / "no rows or columns changed" — NOT bare UNCHANGED). Has an escape hatch for
  intended no-ops and honest "this block can't do it".
- **Prompts are shared by inheritance:** base function-block prompt
  (`blockr.extra::function_block_prompt()` / `inst/prompts/function-block.md`);
  the composer prompt = base + composer extras. **UI/formatting/parameter
  guidance belongs in the base** so every function-style block inherits it.

---

## The failure-mode taxonomy (what goes wrong, and the fix)

Ordered roughly by how fundamental. Most were discovered live.

| Failure | Symptom | Fix | Lever |
|---|---|---|---|
| **Encoding** | model can't escape a big R fn into a JSON-string `config`; dumps prose, claims "can't do it" | typed schema → native args | harness |
| **Prose, no tool call** | "here is a config you can paste", `success=FALSE` | re-prompt loop forcing the tool call | harness |
| **Swallowed errors** | "Block evaluation returned NULL"; model can't fix | `collect_block_errors` surfaces the real error | harness |
| **Mock config** | composer renders `xx.x` placeholders (no `data=`/`make_denom`) | populated example + mock→real enforcement | **example** + harness |
| **Wrong arg shape** | multi-value param sent as a string / single enum value | typed schema prefers the example's shape | **example** + harness |
| **Under-specification** | omits a param, relies on a permissive default (`value_cols`, viz selection) | populate the registry example with that field set | **example** |
| **Single-line code** | unreadable one-liner in the editor | multi-line example + drop "single line is fine" prose | **example** |
| **Wrong vocab** | `c()` where `list()` (multi-select) is needed | example shows `list()` | **example** |
| **Refusal not honored** | block can't filter; model applies a no-op instead of declining | UNSOLVED by prose; needs a harness-side "no-op = didn't do it" detector | open |

Notice the **lever** column: when it says **example**, the prose nudge alone did
NOT work — populating/fixing the registry `examples` did.

---

## Onboarding a NEW block (checklist)

1. **Recon:** constructor signature + `block_ctor_inputs` (defaults → types), what
   data it consumes, what the RESULT is (data? rendered table? passthrough?), the
   registry `*_arguments()` (`prompt` + `examples`), and how to build it headlessly
   (a dev/test/demo to copy).
2. **Classify** (A/B/C/D) → pick the scoring approach.
3. **If Class D** (passthrough result): add a `config_effect.<block_class>` in the
   type-owner package, registered onto blockr.ai's generic at `.onLoad` (defensive
   `requireNamespace` pattern — see `composer-ai-view.R` / `drilldown-ai-effect.R`).
4. **Check the registry `examples` FIRST** — populated? correct shape (arrays for
   multi-value, `list()` for multi-select)? multi-line code if it's a code field?
   shows every field you want set? Fix these before touching prose. This is where
   most wins are.
5. **Write 3–6 cases**, run **live**, score, repeat a couple times (variance).
6. **Iterate:** read the failures, map to the taxonomy above, apply the fix
   (example first, prose second, harness last), re-run.

---

## Open problems / what prose can't fix

- **Honest refusal.** When a block genuinely can't do what's asked (topline
  flextable asked to filter rows), gpt-5.1 tends to apply a vacuous no-op config
  and report success rather than decline — even with explicit "do NOT call
  validate_config, refuse and suggest X" guidance. Likely needs a harness-side
  detector ("config applied but result unchanged AND the request implied a data
  change → re-prompt / mark unsuccessful"), not prose.
- **Variance.** No cheap fix; budget multiple runs for anything you want to claim a
  rate on.
- **Deep clinical/semantic quality** (patient profile): config-correctness is
  scorable by rule, but "is this a clinically good profile" needs a rubric or an
  LLM-judge. Not yet built.

---

## Per-block results snapshot (gpt-5.1, single-run, indicative not precise)

| Block | Class | Result | Key fix |
|---|---|---|---|
| composer fn | A | 0 → 4/8 populated | typed schema + populated example + error surfacing + enforcement |
| dplyr (filter/select/arrange) | B | works, no regression | (baseline / control) |
| function block | B | adds params, multi-line, `list()` multi-select | base prompt + multi-line `list()` example |
| patient profile | C/D | 4/6 (strongest) | already had a rich prompt + example |
| drilldown chart | D | 5/5 config | existing rich prompt + `config_effect` |
| drilldown table | D | 3/3 (after example fix) | populated `examples` (value_cols/label_col/drill) |
| crossfilter | B/D | 3/3 | already fine; "control issue" flag was unfounded |
| topline flextable | B | columns 3/3; row-filter refusal unsolved | example-preference (arrays); refusal open |
| stats model | B | 0 → 5/5 | reshaped block: formula AST → string + weights/offset as top-level args |
| summary table | B | 3/5 → 5/5 (4 runs) | example carried only 6 of 9 `state` keys → `id_var`/`indent_details`/`nest_hierarchies` were INVISIBLE (state-unwrap exposes only example keys); added all 9 + sections-nesting + id_var-gating prose |

Keep this and `ai-eval-cases.md` updated as more blocks are tested.

### Summary-table lesson: the state-unwrap exposes ONLY the example's keys
For a `state = list(...)` block, `block_param_types` builds the state object type
from the registry **example**, then unwraps its children as the AI's top-level
args. A constructor field that is absent from `examples$state` is therefore
absent from the AI schema entirely — the model cannot set it however you prompt.
The summary table's `id_var` (distinct-subject counts — a core pharma feature),
`indent_details`, and `nest_hierarchies` were all missing from the example and so
unreachable. Fix = put EVERY settable field in the example (use the EXCEPTION
value, e.g. `id_var = ""`, not a populated one, to avoid over-triggering — a
populated `id_var = "USUBJID"` made the model set it on every table). Two
gating rules then carried the rest: (1) outer-categorical-goes-in-`sections`
when one var nests in another (SOC>PT), and (2) set `id_var` only on an EXPLICIT
distinct-patient request, never just because a USUBJID column exists.
Eval script: `dev/summary-table-eval-live.R`.
