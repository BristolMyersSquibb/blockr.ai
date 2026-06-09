# blockr.ai assistant — eval test-case registry

Living list of the blocks/scenarios we use to evaluate and tune the per-block AI
(`discover_block_args` → `discover_via_ellmer_tools`). Goal: the assistant
reliably configures real blocks against real data. Keep this current; it's the
source of truth for what "working" must cover.

**Methodology + lessons:** see [`harness-prompting-lessons.md`](harness-prompting-lessons.md)
(how to run evals, the failure-mode taxonomy, and the central lesson that the
registry `example` anchors model behavior more than the `prompt` prose).

## How to run (headless, no Shiny/browser)

- Scripts: `dev/composer-eval.R` (hand-authored fns, token-free, tests the
  *prompt's sufficiency*) and `dev/composer-eval-live.R` (real model via
  `discover_block_args(client = ellmer::chat_openai("gpt-5.1"))`, tests what the
  model *actually does*). **Both are needed** — the live one revealed failures
  the hand-authored one masked.
- Run `Rscript --vanilla` from `/tmp` (package dirs have renv that hijacks
  pkgload). `--vanilla` skips `.Renviron`, so load the key explicitly:
  `readRenviron("/workspace/.Renviron")` (OPENAI_API_KEY lives there).
- Load order: blockr.extra → blockr.dm → blockr.sandbox → blockr.ai (sandbox
  needs extra's `code_editor_refresh_js`; type-owner packages register their
  `data_schema`/`data_effect` methods onto blockr.ai's generics at load).
- ADaM dm: `eval(blockr.dm:::safetydata_adam_expr())` (10 tables; saved
  `/tmp/adam_dm.rds`, needs `library(dm)` to access tables). Study 2 for
  data-variety: `pharmaverseadam_expr()`.

## Scoring instruments (already built)

- `data_effect(NULL, result)` — the "did it work" signal. Composer's method
  (blockr.sandbox/composer-ai-view.R) detects format placeholders: `xx.x` cells
  => "NOT populated" (the composer analogue of UNCHANGED). data.frame method =
  row/col diff incl. in-place changes.
- `data_schema(result)` — the preview the model sees.
- A case PASSES when the model applies a config (lands a `validate_config` call)
  AND the effect shows real output (populated / rows changed as intended).

## THE CORE FINDING (2026-06-08, gpt-5.1)

The dominant failure is **the tool interface, not prompt wording.**
`validate_config` takes `config` as a **JSON-object STRING** the model must
hand-serialize (`{"fn":"function(data){ …nested quotes… }"}`). For big,
quote-heavy params the model can't escape it reliably and: dumps the config as
prose ("here is a config you can paste") without calling the tool; or wrongly
declares the task impossible; or applies a mock (no `data=`). Live composer run:
0/8 populated (vs 5/5 when I hand-authored fns). See the redesign plan below.

## Block roster — by CHALLENGE CLASS (not by package)

The cases split into three distinct problems; one fix does not solve all.

### A. ENCODING — big free-text param (composer function block; also generic function/code blocks)
- **Block:** `blockr.sandbox::new_composer_function_block` (the future composer
  surface; guided composer_block is deprecated). Single param `fn` = a large
  composer R function.
- **Cases (template → ADaM dm adjustment):** user picks a template
  (`composer_template_fn(id)`), asks "adjust to the connected data". Must pick
  the right table, map treatment var/levels (adae `TRTA` vs adsl `TRT01A` →
  `make_denom(adsl, trt="TRT01A", as="TRTA")`), wire `data=`+`denominator=` to
  populate, and ADAPT absent columns. Pilot ids: teae, demographics (drop absent
  REGION block), disposition (EOSSTT→DCDECOD), lab/biomarker (block_summary),
  serious_ae (AESER filter), ui_multiselect (`arms=list(...)`), cm (no adcm →
  must report), aesi (no AESI col → must adapt). + Study 2 (pharmaverseadam,
  different arm labels/table names) for data-variety.
- **Status:** hand-authored 5/5 populate; live gpt-5.1 0/8 (encoding blocker).
- **Fix:** redesign Phase 1 (native typed `fn` arg). See plan.

### B. BASELINE — small structured config (blockr.dplyr blocks)
- **Blocks:** all of blockr.dplyr (filter, select, mutate, summarize, arrange,
  join, etc.). Config = a few small scalar/array params → the JSON-object string
  is *not* a problem here.
- **Cases:** one representative ask per block type against a simple data.frame /
  the ADaM dm (e.g. "keep only SAFFL=='Y'", "select USUBJID/AGE/SEX", "add a BMI
  column", "count subjects by TRT01A"). Should "just work".
- **Why include:** the control/baseline. If dplyr passes and composer fails, the
  problem is isolated to big-fn encoding (confirms the core finding). Also a
  regression guard for the redesign.
- **Status:** not yet run. Expected high pass rate.

### C. CLINICAL PROMPT QUALITY (patient profile, blockr.pharma)
- **Block:** `blockr.pharma::new_patient_profile_block` — THE key demo block
  (R/Medicine talk; see blockr.ideas). Config likely structured (subject id,
  which domains/tracks to show) → encoding is NOT the issue; getting a
  clinically *good* answer is.
- **Cases (need clinical framing):** "show the safety profile for subject X
  focusing on AEs and labs around the treatment-emergent window"; "build a
  profile a clinician would want for an SAE narrative". Score = applies + the
  domain/track selection is clinically sensible (needs a rubric, possibly an
  LLM-judge, not just data_effect).
- **Status:** EVALUATED (dev/patient-profile-eval-live.R). STRONGEST block so far:
  4/6 clinical cases GOOD first-try, 2 partial (under-selection). It ships a rich
  75-line clinical registry prompt + populated example, and config is a clean
  structured vocabulary. NOTE it is ALSO a Class D observability block (result =
  identity(dm) passthrough; score res$args `selected`/`viz_settings`, not
  data_effect). Single-patient dm = filter the safetyData adam_dm to one USUBJID.
  Refinement: nudge to include each named domain as its own viz.

### D. OBSERVABILITY — output is not the meaningful artifact
- **D1. drilldown block (blockr.bi)** — HARDEST. The block returns a **filtered
  expr / passthrough data**, not the chart; the meaningful artifact (chart +
  drill bindings) lives in the JS CONTROL, not the R result
  (set_block_visibility(control=FALSE) hides it). So `data_effect` on the result
  is a no-op/row-diff and can't tell the model whether its chart config is right.
  Drill is gated off by default (needs `drill=`).
  **Ideas for feedback (see redesign §3):** (a) describe the CHART/DRILL CONFIG
  as the data_schema (encoding x/y/metric + drill dims + that bindings reference
  REAL columns) — verify config-correctness, not output; (b) exercise a
  representative drill and measure the downstream filtered data (data_effect on
  the applied filter); (c) image feedback — render the chart via the block's
  render path / Playwright and pass to `discover_block_args(images=)`.
- **D2. crossfilter block (blockr.bi)** — reported CONTROL/wiring issues, "more
  technical than prompting". Likely block-side, not the AI. Needs investigation
  before writing AI cases; may be a prerequisite bug, not a prompt-tuning target.
- **Status:** DONE. drilldown 5/5 config GOOD from its rich registry prompt;
  built the OBSERVABILITY MECHANISM `config_effect(block, args, data)` (blockr.ai
  effect.R generic; type-owner methods in blockr.bi/R/drilldown-ai-effect.R) —
  describes the chart spec + flags invalid column bindings + drill OFF; the
  validate tool uses it instead of the blind data effect. crossfilter (in
  blockr.dm, not blockr.bi) 3/3 GOOD — the "control issue" flag was unfounded;
  its output IS the filtered data so data_effect works directly; model produces
  the correct nested per-table filter structure. ALL roster classes now covered.

## validate_config redesign — re-planned across the roster

The first instinct ("native string arg for single-fn blocks") was too narrow.
The roster shows the real shape:

**Phase 1 — targeted, unblocks composer now (class A).**
When a block's configurable params are a single large free-text field (detect:
`block_ctor_inputs(block)` is one param that's a code/expr string — fn/code/expr
blocks), expose `validate_config` with that param as a DIRECT ellmer
`type_string` argument. The model writes raw R as the argument value; ellmer/the
API handle JSON escaping. Removes the hand-built JSON-object wrapper that gpt-5.1
fails on. Re-run composer live to confirm populate-rate lift.

**STATUS (2026-06-08): Phase 2 BUILT (R/param-schema.R + new_validate_tool) and
the eval-error-feedback fix (R/discover.R collect_block_errors). Typed schema
removed the JSON-escape wall (model now calls the tool); surfacing the real eval
error ("Element X doesn't exist") let it iterate. Four compounding fixes took live
composer from 0 → 4 POPULATED (of 8): (1) typed schema [encoding], (2) surface
real eval errors [discover.R collect_block_errors], (3) mock→real enforcement
[effect_is_noop + re-prompt nudge on no-op], (4) **populated example anchor** —
the registry `examples$fn` was a MOCK so the model copied mocks; swapping in a
populated `composer_example_fn()` (data=+make_denom) jumped 1→4. Remaining of 8:
2 correct declines (cm=no adcm, aesi=no AESI col) + 2 real misses (UI-param case:
model looked for a "composer filter API" instead of adding a function parameter;
disposition column-adaptation). dplyr not regressed; blockr.ai 93 tests pass.
LESSON: the AI's *example* anchors behaviour more than prose — keep it populated.**

**Phase 2 — general, helps everyone (classes A + B + C).**
Replace the `config`-as-JSON-STRING design with a TYPED ellmer schema built from
the block's params (names from `block_ctor_inputs`, types inferred from formal
defaults — same inference the function-block UI already does: list()→array,
c()→enum, scalar→string/number/bool). The model emits NATIVE structured tool
arguments; the API does all escaping, for composer AND dplyr AND patient profile.
Big-fn becomes one string FIELD (still big, but API-escaped, not hand-escaped).
Biggest single lever; bigger change → do after Phase 1 proves the diagnosis.
Watch-outs: nested/`state`-wrapped params (see the assistant state-wrapper bug),
heterogeneous param types.

**Not solved by encoding fixes — separate work:**
- Class C (patient profile): needs clinical prompting + a quality rubric, not
  encoding.
- Class D (drilldown/crossfilter): needs the OBSERVABILITY fix — a config-/
  spec-describing `data_schema` for blocks whose value is in the control/expr,
  not the passthrough data (the architecture principle: describe the meaningful
  PROJECTION of the result — for a drill block that's the chart/drill spec, not
  the data). Possibly image feedback via `discover_block_args(images=)`.

## Other harness changes already made this session
- System prompt forbids prose-configs; "adjust to data" = ACTION → call the tool.
- Re-prompt loop in `discover_via_ellmer_tools`: nudge ≤2x if no config landed
  (moved composer applies 0→2, but still mock — Phase 1 is the real fix).
- Base function-block prompt authored once in blockr.extra
  (`function_block_prompt()`); composer prompt = base + composer extras.
- Composer prompt: populate REQUIRES data=+denominator=; block_continuous(cols)
  needs label + colgroup; block_summary swap is not drop-in.
