# Live AI eval for blockr.stats new_model_block AFTER the formula->string +
# weights/offset-as-top-level-args reshape. The whole block surface (model_type,
# formula, weights, offset) is AI-accessible; the model writes formula as a
# plain string instead of the old nested AST (which it could never produce).
#   cd /tmp && Rscript --vanilla /workspace/blockr.ai/dev/model-block-eval-live.R
readRenviron("/workspace/.Renviron")
.libPaths("/workspace/blockr.dev/.devcontainer/.library")
suppressMessages({
  library(blockr.core)
  library(blockr.stats)
  pkgload::load_all("/workspace/blockr.ai", quiet = TRUE)
})
MODEL <- "gpt-5.1"
`%||%` <- function(a, b) if (is.null(a) || !nzchar(as.character(a)[1])) b else a

# mtcars: mpg continuous, am 0/1 (logistic), carb/gear counts (poisson), cyl weight
cases <- list(
  list(ask = "Model mpg as a linear function of horsepower and weight.",
       want = "lm: mpg ~ hp + wt"),
  list(ask = "Predict whether a car has a manual transmission (am, 0/1) from mpg and weight.",
       want = "logistic: am ~ mpg + wt"),
  list(ask = "Model mpg from horsepower and weight, including their interaction.",
       want = "lm: mpg ~ hp * wt"),
  list(ask = "Model the number of carburetors (carb) as a count outcome of hp and weight.",
       want = "poisson: carb ~ hp + wt"),
  list(ask = "Model mpg from horsepower, weighting each observation by its cylinder count (cyl).",
       want = "lm: mpg ~ hp, weights = cyl")
)

describe <- function(res) {
  # The result IS the fitted model (challenge class D: artifact != a data frame)
  r <- res$result
  if (inherits(r, c("lm", "glm"))) {
    fam <- if (inherits(r, "glm")) summary(r)$family$family else "gaussian"
    return(sprintf("FIT %s | %s | %d coef", fam,
                   paste(trimws(deparse(formula(r))), collapse = " "),
                   length(stats::coef(r))))
  }
  a <- res$args
  if (!is.null(a)) {
    return(sprintf("args: type=%s formula=%s weights=%s offset=%s",
                   a$model_type %||% "?", a$formula %||% "?",
                   a$weights %||% "-", a$offset %||% "-"))
  }
  "no result"
}

cat("=========== MODEL BLOCK (gpt-5.1, formula-as-string) ===========\n")
ok <- 0
for (i in seq_along(cases)) {
  cs <- cases[[i]]
  blk <- new_model_block()
  client <- ellmer::chat_openai(model = MODEL, echo = "none")
  res <- tryCatch(
    discover_block_args(prompt = cs$ask, block = blk, data = mtcars, client = client),
    error = function(e) list(success = FALSE, error = conditionMessage(e))
  )
  if (isTRUE(res$success)) {
    ok <- ok + 1
    cat(sprintf("\n[%d] OK   want %-28s -> %s\n", i, cs$want, describe(res)))
  } else {
    cat(sprintf("\n[%d] FAIL want %-28s -> %s\n", i, cs$want,
                substr(res$question %||% res$message %||% res$error %||% "(none)", 1, 160)))
  }
}
cat(sprintf("\n=========== %d/%d succeeded ===========\n", ok, length(cases)))
