# Why `data_effect` exists (and why two `data_schema` calls can't replace it)

Design note, 2026-07-05. Records the resolution of a recurring question:

> `data_schema` makes sense — a supercharged `str()` for the LLM. But
> `data_effect` looks redundant: instead of a specialized diff function, we
> could give the LLM `data_schema(input)` and `data_schema(result)` and let it
> work out the difference itself. One generic, one method per type, and it
> extends naturally to non-data.frame results (ggplot, composed_table) where
> a diff doesn't apply.

The proposal is reasonable and rests on three intuitions. Two of them are
based on misreadings of the code, and the third is already how the code
behaves. This note walks through all three, then states what `data_effect`
actually is for.

## The two generics have different consumers

This is the core of the answer, so it comes first.

- `data_schema(x)` describes **one object** for the **LLM**. It is really a
  *preview* (the data.frame method is literally `format_df_preview()`):
  dimensions, column types, first rows, per-column value summaries. Its job
  is to orient the model.

- `data_effect(input, result)` produces the **did-it-do-anything signal** for
  the **harness**. Its one-line string is shown to the LLM too, but its
  load-bearing consumer is `effect_is_noop()` (harness-ellmer.R), which
  greps it for three sentinel markers:

  - `"no rows or columns changed"`
  - `"not populated"`
  - `"DEGENERATE"`

  That single bit drives deterministic machinery:

  1. the **no-op nudge loop** — a config that validates but changes nothing
     triggers "your config validated but did nothing; fix it or say this
     block can't do it";
  2. the **`noop` field** in the discover result (a caller can distinguish
     *valid* from *effective*);
  3. **telemetry** (`blockr.ai_run_log`) and the **golden-task eval**
     (`dev/eval/`), which score `outcome_ok` separately from `applied`.

Replace the effect with two previews and every one of those consumers goes
blind: the harness would have to diff two prose blobs to recover the no-op
bit. The deterministic way to diff them is to compare the underlying
objects — which is exactly what `data_effect` already is. You don't delete
the diff function; you reimplement it inside the harness, weaker.

This is the valid≠correct lesson: "hope the model notices the two previews
differ" is probabilistic; the whole point of the effect infrastructure was to
make no-op detection deterministic and measurable.

## Objection 1: "a diff function needs a method per input×output type pair"

It doesn't. `data_effect(input, result)` dispatches on **`result` only**:

```r
data_effect <- function(input, result, ...) {
  UseMethod("data_effect", result)
}
```

There is no df→ggplot method and never needs to be one. The input side is
handled once, generically: `effect_primary_df()` picks the single comparable
input data frame (or gives up and describes the output instead). So the
maintenance burden has exactly the same shape as `data_schema`: **one
optional method per result type**. The `(input, result)` signature invites
the pairwise misreading, but the dispatch isn't pairwise.

Current footprint: `data.frame`, `dm`, a default returning `""` (blockr.ai);
`composed_table` / `gt_tbl` / `flextable` (blockr.sandbox, runtime-registered).
That is probably the complete set — see the closing section.

## Objection 2: "for heterogeneous outputs (df→ggplot), a diff is meaningless"

Correct — and already the design. `data_effect.default` returns `""`, and the
validate tool always returns `preview = data_schema(result)` **alongside** the
effect. For a result type with no effect method, the model learns about the
output from the preview, exactly as the proposal suggests. Nobody is forced
to write effect methods for non-diffable types.

For passthrough blocks (drilldown chart, patient profile) where even a df→df
diff is blind — the data goes through unchanged *by design* — there is
`config_effect(block, args, data)`, dispatched on the **block**, so the type
owner can describe what the config set up instead.

So for the cases the objection cites, the code already does schema-only
feedback. `data_effect` methods exist only where a silent no-op is possible
and common.

## Objection 3: "the one-line rows/cols summary is only useful for filters"

This mistakes the `data.frame` *method* for the *generic*. The generic's
contract is not "report a row/column diff"; it is **"report, in whatever
terms are meaningful for this result type, whether the config took
effect"**. Each type answers its own version:

| Result type | What "effect" means there |
|---|---|
| `data.frame` | rows added/removed; columns added/removed; columns **modified in place** |
| `dm` | per-table row deltas; tables removed |
| `composed_table` / `gt_tbl` / `flextable` | populated vs. template vs. DEGENERATE |
| `ggplot`, passthrough blocks | `""` — preview only, or `config_effect` on the block |

Two cases show the method family earning its keep beyond filters:

**Mutate.** `mutate(bmi = wt / ht^2)` → `columns added: bmi`. An in-place
rewrite `mutate(AGE = AGE * 2)` keeps names, types, and row count — invisible
to any schema — but `effect_modified_cols()` compares shared columns with
`identical()` and reports `columns modified: AGE: values changed`. A preview
*might* reveal this one (the value summaries would shift), but a change that
flips one value in row 87, or a re-sort, is invisible in a 5-row preview and
caught by `identical()` on the full columns.

**Composed tables — the strongest case.** The composed_table method
(blockr.sandbox/R/composer.R) does no row diff at all. It returns the
**population status** of the rendered table:

- `NOT populated: 12 cell(s) still show format placeholders (e.g. 'xx.x')`
- `populated but DEGENERATE: every numeric value in the table is zero;
  hint: a grouping/by variable may be a factor (coerce with as.character())…`
- `populated: real numbers present (34 of 40 non-empty cells)`

The DEGENERATE case is the proof that preview-comparison cannot substitute:
a table full of `0 (0.0)` cells *looks* populated in a preview — an LLM
comparing input schema to output preview happily reports success. Catching
it requires composer-specific knowledge: that `xx.x` is the template
placeholder convention, that all-zero counts are the factor-as-grouping
signature, and what the fix is. That knowledge lives in the type owner's
effect method — which is the whole point of `data_effect` being a generic.
Each package teaches the harness what "did nothing" looks like *for its
type*, including the remediation hint the nudge quotes verbatim.

## What is `data_effect` comparing?

The block's **input** against the **result of the current config attempt** —
within a single `validate_config` call. `new_validate_tool(validate, block,
data)` captures the upstream input once; every candidate config is evaluated
and diffed against that same fixed input. It is *not* previous-result vs.
latest-result: the no-op question ("is this valid config doing nothing?") is
only well-defined against the input. Prev-vs-latest answers a different
question ("did my edit change anything") and misfires in both directions —
two different no-ops read as "changed nothing" without saying the block is
still inert, and re-submitting an already-correct config reads as failure.

Note this makes the schema-comparison proposal and `data_effect` the *same
comparison pair* (input vs. current result). The difference is who does the
comparing and on what: the LLM impressionistically, on truncated previews —
or the harness deterministically, on the full objects.

## Boundaries and accepted rough edges

- **Don't grow the method set.** `data.frame`, `dm`, and the composer table
  types are the types where value-level silent no-ops are both possible and
  common. For everything else, `""` + preview is the designed answer, not a
  gap. Do not encourage effect methods broadly.

- **Naming.** `data_schema` is a misnomer — it returns a *preview* (values,
  distributions), not just structure; the tool field is even called
  `preview`. A rename is cosmetic and low priority.

- **The sentinel-grep contract.** The machine-readable bit is smuggled into
  prose via magic markers (`"DEGENERATE"` etc.). If this ever bites, the
  refinement is *not* to drop the generic but to make the contract explicit —
  e.g. methods return `list(noop = TRUE/FALSE, text = "…")` so type owners
  set the bit directly. Same dispatch, same one-method-per-type, no grep.

## Summary

`data_schema` and `data_effect` are not two views of the same information.
The preview describes an object for the model; the effect is a per-type
tripwire that makes silent no-ops (and semantically-empty successes like the
all-zero table) *certainly detected* rather than *plausibly noticeable* —
feeding the nudge loop, the `noop` result field, telemetry, and eval scoring.
Dropping it in favor of two previews would keep the description and lose the
detection.
