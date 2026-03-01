# AI Control Example — Data Exploration
#
# Uses random data with opaque column names so the LLM *must* explore
# to answer correctly. The 5-row preview is not enough.
#
# Start the app, expand "AI Assist" on the filter block, and try:
#   "keep only rows where the group with the highest mean of v2"
#
# Expected: the LLM writes ```data_query``` blocks to compute
# group means before providing JSON.

pkgload::load_all("blockr.core")
pkgload::load_all("blockr.dplyr")
pkgload::load_all("blockr.ai")

# keep only the group with the highest mean of v2
options(blockr.eval_parent_env = as.environment("package:stats"))

set.seed(42)
n <- 200
demo_data <- data.frame(
  id = seq_len(n),
  grp = sample(paste0("G", 1:5), n, replace = TRUE),
  v1 = round(rnorm(n, mean = 50, sd = 15), 1),
  v2 = round(runif(n, 0, 100), 1),
  v3 = round(rexp(n, rate = 0.1), 1),
  flag = sample(c("alpha", "beta", "gamma"), n, replace = TRUE)
)

serve(
  new_board(
    blocks = c(
      data = new_static_block(demo_data),
      filter = new_filter_block()
    ),
    links = c(
      new_link("data", "filter", "data")
    )
  ),
  plugins = custom_plugins(ai_ctrl_block())
)
