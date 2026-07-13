# Native shinychat tool cards in the AI ctrl block (feat/shinychat-native-tool-cards)
#
# Run from the workspace root (inside or outside the dev container):
#   Rscript blockr.ai/dev/examples/ai-ctrl-tool-cards/app.R [port]
#
# Port: positional arg, else BLOCKR_PORT, else 3838.
# Needs OPENAI_API_KEY (picked up from the workspace-root .Renviron when
# launched from the root).
#
# Try, on the Select block's sparkle panel:
#   "look at the data and keep only the two most informative columns plus species"
# The chat shows native shinychat tool cards: one "Explored data" card per
# data probe (expand for the R code), an "Applied configuration" card with the
# validate_config call + its effect, then the model's reply.
#
# NOTE: filter/summarize blocks currently fail with an OpenAI schema 400
# (pre-existing typed-schema bug, independent of the tool-card work) -- use
# the select block to see the success path.

port <- suppressWarnings(as.integer(commandArgs(trailingOnly = TRUE)[1]))
if (is.na(port)) port <- as.integer(Sys.getenv("BLOCKR_PORT", "3838"))
options(shiny.port = port, shiny.host = "127.0.0.1")

options(blockr.ai_model = "gpt-5.1")

pkgload::load_all("blockr.core")
# blockr.dock@main does not evaluate blocks against blockr.core@main (the
# on-screen contract mismatch); prefer the 304-defer-offscreen-docks worktree
# when present.
pkgload::load_all(
  if (dir.exists("_scratch/dock-304")) "_scratch/dock-304" else "blockr.dock"
)
pkgload::load_all("blockr.dag")
pkgload::load_all("blockr.dplyr")
pkgload::load_all("blockr.ai")

serve(
  new_dock_board(
    blocks = c(
      data = new_dataset_block("iris"),
      select = new_select_block(),
      summarize = new_summarize_block()
    ),
    links = c(
      new_link("data", "select", "data"),
      new_link("select", "summarize", "data")
    ),
    extensions = list(dag = new_dag_extension())
  ),
  plugins = custom_plugins(ai_ctrl_block())
)
