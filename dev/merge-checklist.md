# blockr.ai Merge Checklist

Status: **In progress**

## Open — Needs discussion with Nicolas

- [ ] **`:::` usage for blockr.core internals**
  `ai_ctrl_ui()` calls `blockr.core:::block_external_ctrl_vars(x)` (R/ai-ctrl-block.R:63)
  and `get_block_registry_info()` calls `blockr.core:::block_registry` (R/utils-llm.R:418).
  Neither function/object is exported by blockr.core.
  Options: export from core, replace with public API (`registry_metadata()`), or
  extract directly from block attributes. Discuss best approach with Nicolas.

## Open — Cleanup

- [ ] **Delete blockr.core `experiment/ai` branch** — 4 ahead, 38 behind main.
  This branch is stale. Main already has the ctrl_block plugin API (PR #134).
  blockr.ai is built against main's API, not experiment/ai's.

## Done / Not blocking

- [x] **API compatibility** — `ai_ctrl_server(id, x, vars, data, eval)` matches
  blockr.core main's ctrl_block plugin interface (PR #134).

- [x] **Code quality** — No TODOs, FIXMEs, `browser()` calls in blockr.ai.

- [x] **Tests** — 15 test files in blockr.ai covering discover, ctrl, registry,
  backends, tool eval, tool help.

- [x] **Man pages** — 15 .Rd files covering exported functions.

## Done — Dependency cleanup

- [x] **rlang** — Removed. `abort` and `names2` were imported but never called.
- [x] **dplyr** — Moved to Suggests. Only used in LLM prompt strings.
- [x] **dm** — Moved to Suggests. Only `inherits(x, "dm")` checks, no function calls.

17 Imports remain, all with confirmed runtime usage.

## Nice to have (not blocking merge)

- [ ] Add vignette(s) for ai_ctrl_block usage
- [ ] Add NEWS.md
- [ ] Address 4 failing Playwright tests in blockr.dplyr external-ctrl test report
  (arrange_block, select_block exclude mode, rename multi-rename, UI sync)
