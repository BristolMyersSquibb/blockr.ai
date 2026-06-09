# Play with Design A (the ellmer tool-calling harness) live.
#
# Serves a small board with the AI chat overlay. The only thing that makes it
# use Design A instead of the legacy loop is:  options(blockr.harness = "ellmer")
#
#   Rscript dev/play-harness-a.R     # -> http://127.0.0.1:3838
#
# Then expand "AI Assist" on a block and type, e.g.:
#   code:    "return only the first 3 rows"   /  "keep cars with 4 cylinders"
#            "add a column kpl = mpg * 0.425"  /  "average mpg by cyl"
#   filter:  "only 6 cylinder cars"
#   select:  "keep mpg, cyl, hp"
#   mutate:  "hp per cylinder"
#   slice:   "top 5 by horsepower"

readRenviron("/workspace/.Renviron")   # OPENAI_API_KEY for ellmer

suppressMessages(suppressWarnings({
  pkgload::load_all("/workspace/blockr.core",  quiet = TRUE)
  pkgload::load_all("/workspace/blockr.dock",  quiet = TRUE)
  pkgload::load_all("/workspace/blockr.dag",   quiet = TRUE)
  pkgload::load_all("/workspace/blockr.dplyr", quiet = TRUE)
  pkgload::load_all("/workspace/blockr.extra", quiet = TRUE)
  pkgload::load_all("/workspace/blockr.ai",    quiet = TRUE)
}))

# --- Design A switch ---------------------------------------------------------
options(
  blockr.harness  = "ellmer",        # <- use the new tool-calling harness
  blockr.ai_model = "gpt-5.4-nano",  # cheap/fast dev model
  shiny.port      = 3838L,
  shiny.host      = "0.0.0.0"
)

serve(
  new_dock_board(
    blocks = c(
      mtcars_data = new_dataset_block("mtcars"),
      code        = new_code_block(fn = "function(data) { data }"),
      filter      = new_filter_block(),
      select      = new_select_block(columns = c("mpg", "cyl", "hp")),
      slice       = new_slice_block(type = "head", n = 10)
    ),
    links = c(
      new_link("mtcars_data", "code",   "data"),
      new_link("mtcars_data", "filter", "data"),
      new_link("mtcars_data", "select", "data"),
      new_link("mtcars_data", "slice",  "data")
    ),
    extensions = list(dag = new_dag_extension())
  ),
  plugins = custom_plugins(ai_ctrl_block())
)
