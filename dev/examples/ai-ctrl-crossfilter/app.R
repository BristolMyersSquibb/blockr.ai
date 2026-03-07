# AI Control Example — Crossfilter Block (Dock Board)
#
# A crossfilter block with AI control on iris data using dock board.
# Expand "AI Assist" on the crossfilter block,
# and type e.g. "only setosa" or "sepal length between 5 and 6".

pkgload::load_all("/Users/christophsax/git/blockr/blockr.core")
pkgload::load_all("/Users/christophsax/git/blockr/blockr.dock")
pkgload::load_all("/Users/christophsax/git/blockr/blockr.dag")
pkgload::load_all("/Users/christophsax/git/blockr/blockr.dm")
pkgload::load_all("/Users/christophsax/git/blockr/blockr.ai")

pkgload::load_all("/Users/christophsax/git/blockr/blockr.extra")

options(blockr.html_table_preview = TRUE)

serve(
  new_dock_board(
    blocks = c(
      data = new_dataset_block("iris"),
      cf = blockr.dm::new_crossfilter_block()
    ),
    links = c(
      new_link("data", "cf", "data")
    ),
    extensions = list(dag = new_dag_extension())
  ),
  plugins = custom_plugins(ai_ctrl_block())
)
