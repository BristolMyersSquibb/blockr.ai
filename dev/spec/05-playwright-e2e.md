# End-to-End Testing with Playwright

> How to use the Claude Code Playwright MCP plugin to launch a blockr app,
> interact with it, and verify behavior visually.

## Overview

The Playwright plugin provides browser automation via MCP tools. It can
launch a real Chrome instance, navigate to a running Shiny app, take
snapshots/screenshots, click elements, type text, and verify results.

This is useful for:
- Verifying that `external_ctrl` + `ai_ctrl_block` renders correctly
- Testing the AI chat flow end-to-end (type prompt → send → verify result)
- Checking that block UI updates after AI-driven parameter changes
- Debugging rendering issues in dock boards or complex widgets

## Setup

The Playwright plugin must be installed:

```
/plugin playwright
```

Restart Claude Code after installation. The plugin uses the system Chrome
(`/Applications/Google Chrome.app` on macOS).

### Chrome session conflicts

Playwright uses a persistent Chrome profile at
`~/Library/Caches/ms-playwright/mcp-chrome-*`. If Chrome is already
running with the same profile, Playwright fails with "Opening in existing
browser session." Fix:

```bash
rm -rf ~/Library/Caches/ms-playwright/mcp-chrome-*
```

## Workflow

### 1. Launch the Shiny app

Use absolute paths for `pkgload::load_all()` — relative paths resolve
from the app file's directory, not the working directory.

```r
# inst/examples/ai-ctrl-crossfilter/app.R
pkgload::load_all("/Users/.../blockr.core")
pkgload::load_all("/Users/.../blockr.dm")
pkgload::load_all("/Users/.../blockr.ai")

serve(
  new_board(
    blocks = c(
      data = new_dataset_block("iris"),
      cf = blockr.dm::new_crossfilter_block()
    ),
    links = c(new_link("data", "cf", "data"))
  ),
  plugins = custom_plugins(ai_ctrl_block())
)
```

Launch in background via Bash tool:

```bash
Rscript -e 'shiny::runApp("path/to/app.R", port = 3838, launch.browser = FALSE)' &
sleep 10  # wait for app to start
```

Use a fixed port (e.g. 3838) so the URL is predictable.

### 2. Navigate and wait

```
browser_navigate → http://127.0.0.1:3838
browser_wait_for → time: 3-5 seconds
```

Dock boards need more time (5-10s) for the dockview widget to initialize.

### 3. Take a snapshot (preferred) or screenshot

**Snapshot** returns an accessibility tree with element refs — use this
for interaction:

```
browser_snapshot
```

Returns structured YAML like:

```yaml
- textbox "Describe what you want..." [ref=e65]
- button "Send message" [disabled] [ref=e66]
- combobox "Dataset" [ref=e52]
```

**Screenshot** captures the visual state — use this for verification:

```
browser_take_screenshot → type: png, filename: my-test.png
```

### 4. Interact with elements

Use refs from the snapshot:

```
browser_click → ref=e65, element="AI assist textbox"
browser_type → ref=e65, text="only setosa species"
browser_click → ref=e66, element="Send message button"
```

For dropdowns:

```
browser_select_option → ref=e52, values=["mtcars"]
```

### 5. Wait for AI response

After clicking Send, the LLM needs time to process:

```
browser_wait_for → time: 10-15 seconds
```

Then snapshot again to verify the result.

### 6. Verify results

After the AI responds, check the snapshot for:

- Chat response text (e.g. "Done!")
- Updated filter status (e.g. "50 / 150 rows")
- Updated data table content
- Active filter UI elements

## Example: Testing crossfilter AI control

Full sequence:

```
1. Bash: launch app on port 3838
2. browser_navigate: http://127.0.0.1:3838
3. browser_wait_for: 5 seconds
4. browser_take_screenshot: initial state
5. browser_snapshot: find AI textbox ref
6. browser_click: AI textbox ref
7. browser_type: "only setosa species"
8. browser_click: Send button ref
9. browser_wait_for: 15 seconds (LLM processing)
10. browser_snapshot: verify results
    - Chat shows "Done!"
    - Status shows "50 / 150 rows"
    - Species filter is active with "setosa" selected
11. browser_take_screenshot: final state
12. Bash: kill app process
13. browser_close
```

## Known Limitations

### Dock board rendering

The dockview widget (used by `new_dock_board`) sometimes shows as empty
in Playwright. This happens when:
- The widget is still `recalculating` (needs more wait time)
- The Chrome profile has stale state (fix: delete the profile dir)

Regular `new_board` renders reliably. If dock board fails, try:
1. Wait longer (10+ seconds)
2. Resize the browser: `browser_resize → width: 1300, height: 900`
3. Delete Chrome profile and retry

### Accessibility tree vs visual elements

Canvas-based widgets (G6 graph in dock board DAG) don't appear in
accessibility snapshots. Use `browser_run_code` with custom JS to
inspect these:

```js
async (page) => {
  return await page.locator('[class*=block]').evaluateAll(
    nodes => nodes.map(n => ({ id: n.id, className: n.className }))
  );
}
```

### Console errors

Check for Shiny errors that prevent rendering:

```
browser_console_messages → level: error
```

Common issues:
- `duckplyr::as_duckdb_tibble` fails on factor columns (convert to
  character first)
- Missing packages (check `pkgload::load_all` paths)
- Port already in use (pick a different port or kill stale processes)

## Cleanup

Always clean up after testing:

```bash
kill <PID>  # kill the Shiny app process
```

```
browser_close
```

## Tips

- **Parallel snapshots**: Take a snapshot AND screenshot together — the
  snapshot gives refs for interaction, the screenshot gives visual proof.
- **Element search**: If the snapshot is large, use `browser_run_code` to
  query specific CSS selectors.
- **Slow typing**: Use `slowly: true` in `browser_type` if the app has
  debounced key handlers.
- **Full page screenshots**: Use `fullPage: true` for long pages that
  scroll.
- **Multiple tabs**: Dock board renders blocks in tab panels — use
  `browser_click` on tab headers to switch between blocks.
