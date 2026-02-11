# Dev script: test AI control of crossfilter_block
#
# Run interactively to verify discover_block_args works with crossfilter blocks.

pkgload::load_all("../blockr.core")
pkgload::load_all("../blockr.dm")
pkgload::load_all(".")

# --- crossfilter_block with iris ---

blk <- blockr.dm::new_crossfilter_block()

# Categorical filter
cat("=== Categorical filter: only setosa ===\n")
res <- discover_block_args(
  prompt = "only setosa species",
  block = blk,
  data = iris,
  verbose = TRUE
)
cat("Success:", res$success, "\n")
cat("Args:\n"); str(res$args)
cat("Result rows:", nrow(res$result), "(expect 50)\n\n")

# Numeric range filter
cat("=== Range filter: sepal length between 5 and 6 ===\n")
res2 <- discover_block_args(
  prompt = "sepal length between 5 and 6",
  block = blk,
  data = iris,
  verbose = TRUE
)
cat("Success:", res2$success, "\n")
cat("Args:\n"); str(res2$args)
cat("Result rows:", nrow(res2$result), "\n\n")

# Combined filter
cat("=== Combined: setosa with sepal width > 3.5 ===\n")
res3 <- discover_block_args(
  prompt = "setosa species with sepal width between 3.5 and 5",
  block = blk,
  data = iris,
  verbose = TRUE
)
cat("Success:", res3$success, "\n")
cat("Args:\n"); str(res3$args)
cat("Result rows:", nrow(res3$result), "\n")
