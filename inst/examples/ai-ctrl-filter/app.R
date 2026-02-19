# AI Control Example — Filter Block
#
# A dataset block feeding a filter block with AI control.
# Start the app, expand "AI Assist" on the filter block,
# and type e.g. "only setosa" or "sepal length above 5".

pkgload::load_all("blockr.core")
pkgload::load_all("blockr.dplyr")
pkgload::load_all("blockr.ai")

serve(
  new_board(
    blocks = c(
      data = new_dataset_block("iris"),
      filter = new_filter_block()
    ),
    links = c(
      new_link("data", "filter", "data")
    )
  ),
  plugins = custom_plugins(ai_ctrl_block())
)
