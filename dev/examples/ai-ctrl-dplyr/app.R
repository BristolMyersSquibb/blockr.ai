# AI Control Block Example
#
# The ai_ctrl_block plugin enables natural language control of blocks.
# Blocks with external_ctrl (like dataset_block) support live updates.
# Other blocks get validated suggestions but require manual recreation.

pkgload::load_all("blockr.core")
pkgload::load_all("blockr.dock")
pkgload::load_all("blockr.dag")
pkgload::load_all("blockr.dplyr")
pkgload::load_all("blockr.ai")

serve(
  new_dock_board(
    blocks = c(
      data = new_dataset_block("iris"),
      filter = new_filter_block(),
      mutate = new_mutate_expr_block(),
      summarize = new_summarize_block()
    ),
    links = c(
      new_link("data", "filter", "data"),
      new_link("data", "mutate", "data"),
      new_link("data", "summarize", "data")
    ),
    extensions = list(dag = new_dag_extension())
  ),
  plugins = custom_plugins(ai_ctrl_block())
)
