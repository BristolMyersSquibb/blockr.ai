# Composer + AI eval loop — onboarding for the configuring Claude

You (Claude Code) have been pointed at `blockr.ai` to **improve the composer
function block's AI** until it reliably produces populated, correct TLFs from
*production-shaped* ADaM data — not just the small `safetyData` example.

This doc is your map. Read it fully before touching code. The human driving you
(Olajoke) has prod access and knows the SDR study tables; you do not have prod
access and must never try to get it (see Guardrails).

## The problem, diagnosed (don't re-discover this)

Testing on the real SDR study surfaced **three distinct failure classes**. Only
one is about data:

1. **Token blowout — the dominant failure.** A multi-turn editing session dies
   with `context_length_exceeded` (~285k > 272k tokens). Cause: every turn
   re-dumps the *entire* schema — all columns of all tables — plus the full
   current `fn` and the system prompt. Prod ADaM tables are wide (adsl ~178
   cols, adqs2 ~103, adae ~132), so 2–3 refinements overflow. This is why
   "follow-up prompts break a working table" and "keep prompts short": it is not
   the model getting confused, it is the context filling up. **The schema-dump
   renderer is in `blockr.ai/R/utils-llm.R`.** This is the highest-leverage fix
   and needs no prod data — start here.

2. **A real composer bug, not an AI bug.** The disposition table fails with
   `Can't subset columns with spec$.name ... empty string at location 1`, inside
   composer's column-spec code. The model correctly gives up. If you hit this,
   log it as a composer defect and move on — do not try to prompt around it.

3. **Data-realism gap.** `safetyData` is small, narrow, single-period. Prod SDR
   is a crossover Alzheimer's study: **two-period treatment vars (`TRT01x` AND
   `TRT02x`)**, study-specific endpoints (`NPCIHDDT`, `CGISTOT`, `CMAITOT`, …),
   `BASETYPE = SINGLE-BLIND / DOUBLE-BLIND`, wide tables. The example never
   exercises any of this, so it cannot reproduce (1) or (2) either.

## Where things live

| Thing | Path |
|---|---|
| Base function-block prompt (composer inherits + prepends) | `blockr.extra/R/function-block-prompt.R` (`function_block_prompt()`) |
| Composer-specific prompt + the block | `blockr.sandbox` (composer function block) |
| Schema/data-context renderer (the token culprit) | `blockr.ai/R/utils-llm.R` |
| Headless eval — pilot, self-scored | `blockr.ai/dev/composer-eval.R` |
| Headless eval — **drives a live model** (use this) | `blockr.ai/dev/composer-eval-live.R` |
| Prod data profiler (run on prod, by Olajoke) | `blockr.sandbox/dev/describe.R` + `sas_describe.R` |

All packages are in the `/workspace` monorepo; load with `pkgload::load_all()`
(see the eval scripts' headers for the exact `.libPaths` + load order).

## The workflow

The point is a **fast, headless, shared** loop. Do the slow prod step once, turn
it into committed synthetic artifacts, then iterate on the prompt against those.

```
describe.R on prod (Olajoke, once)
   -> glossary CSVs (columns.csv / tables.csv / subject_id.csv)   [redacted, safe to commit]
        -> make_fake.R  (you write this)
             -> fake SDR-shaped dm  (committed .rds — synthetic, no real values)
                  -> composer-eval-live.R cases  (Jaqui's table list)
                       -> score -> tweak prompt (extra/sandbox/ai) -> re-score
```

### Step 1 — get the glossary (Olajoke runs `describe.R` on prod)

Only the redacted glossary CSVs leave prod. You receive `columns.csv` (the
fake-data recipe: per column `r_type`, `n_distinct`, `max_char_len`, `is_id`),
`tables.csv` (sizes), `subject_id.csv` (join-key unification). Confirm with
Olajoke these are reviewed before you use them.

### Step 2 — write `make_fake.R`

Turn the glossary into a synthetic `dm` that matches prod **shape**: same tables,
same column names + types, faithful cardinalities and char widths, the
**two-period treatment structure**, real CDISC controlled-terminology level
values where Olajoke confirmed they're safe (standard CT is not confidential;
drug/site/verbatim terms stay masked). The data must be fully synthetic — you
are reproducing the *shape and vocabulary* that breaks the AI, not real records.
Commit the generated dm as an `.rds` so the loop is shared.

Skeleton:

```r
# make_fake.R — glossary CSVs -> synthetic prod-shaped dm (commit the .rds)
make_fake_dm <- function(columns_csv, tables_csv,
                         n_subjects = 676,        # from tables.csv adsl n_rows
                         ct = list()) {            # real CDISC levels Olajoke OK'd, per column
  cols <- utils::read.csv(columns_csv)
  # for each table: build columns by r_type; ids join on USUBJID;
  # n_distinct -> #levels, max_char_len -> string width, ct[[col]] -> real levels.
  # Two-period: ensure TRT01* and TRT02* both present where prod has them.
  # ... returns a dm::dm() with PK/FK on USUBJID matching subject_id.csv
}
```

### Step 3 — add Jaqui's tables as eval cases

Mirror the case shape already in `composer-eval-live.R`. Each case = the mock
template `fn` + the connected fake dm + the expected populated result. Score =
the composer placeholder check (any `xxx`/`xx.x` left ⇒ fail) plus a structure
check (Big-N and arms tie to the intended population/denominator).

### Step 4 — iterate on the prompt

Run `composer-eval-live.R`, read failures, edit the prompt
(`function-block-prompt.R` base, the composer prepend, and/or the schema
renderer in `utils-llm.R`), re-run. **Two hard rules:** the fake-prod score must
go UP, and the `safetyData` score must NOT regress. Keep a baseline number for
both before you change anything.

## What "improved" means (the bar)

- Fake-prod eval score rises across runs; safetyData score holds.
- A multi-turn session on a wide table no longer blows the token budget (the
  schema dump is trimmed/summarised — verify the token count, don't guess).
- Each fix is backed by a before/after eval number, not a vibe.

## Guardrails

- **Never exfiltrate prod data.** Only the redacted glossary CSVs leave prod, and
  only after Olajoke reviews them. The committed dm is 100% synthetic.
- **Don't prompt around the composer `spec$.name` bug** — file it separately.
- Commit hygiene per the repo CLAUDE.md (no Claude attribution; use
  `/usr/lib/git-core/git`).
- Treat every AI-generated table as a draft to verify, not a finished TLF.
