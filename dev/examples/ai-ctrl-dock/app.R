# AI Control Example with Dock Board
#
# A dataset block feeding a filter block with AI control in a dock layout.
# Start the app, expand "AI Assist" on the filter block,
# and type e.g. "only setosa" or "sepal length above 5".

pkgload::load_all("blockr.core")
pkgload::load_all("blockr.dock")
pkgload::load_all("blockr.dag")
pkgload::load_all("blockr.dplyr")
pkgload::load_all("blockr.ai")
library(blockr.extra)

# always include on prod
options(
  blockr.eval_parent_env = asNamespace("stats"),
  blockr.html_table_preview = TRUE
)

serve(
  new_dock_board(
    blocks = c(
      data = new_dataset_block("iris"),
      filter = new_filter_block()
    ),
    links = c(
      new_link("data", "filter", "data")
    ),
    extensions = list(dag = new_dag_extension())
  ),
  plugins = custom_plugins(ai_ctrl_block())
)
