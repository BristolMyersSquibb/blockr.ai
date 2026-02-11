# Minimal AI Control Example — Dataset Block
#
# A single dataset block with AI control. Start the app, expand "AI Assist",
# and type e.g. "use mtcars" or "switch to CO2" to reconfigure the block.

pkgload::load_all("../blockr.core")
pkgload::load_all("../blockr.ai")

serve(
  new_board(
    blocks = c(data = new_dataset_block("iris"))
  ),
  plugins = custom_plugins(ai_ctrl_block())
)
