# Benchmark cases for the harness comparison (Design A vs B vs legacy).
#
# These centre on the headline class: blockr.extra's code_block / function_block,
# whose configuration is freeform R in a single `fn` field. That is the case the
# constrained-JSON loop is weakest at and the one the rewrite must nail. Each
# case grades the *result data*, so it is harness- and model-agnostic.
#
# A case is a list:
#   id        - short identifier
#   make_block- function() returning a fresh block
#   data      - input data
#   prompt    - natural-language instruction
#   grade     - function(result_df) -> logical (TRUE = correct)
#   tags      - character vector (difficulty / kind)

emails_df <- function() {
  data.frame(
    user = c("a", "b", "c", "d", "e"),
    email = c("a@gmail.com", "b@yahoo.com", "c@gmail.com",
              "d@hotmail.com", "e@gmail.com"),
    spend = c(10, 20, 30, 40, 50),
    stringsAsFactors = FALSE
  )
}

eval_cases <- function() {
  list(
    list(
      id = "code_head3",
      make_block = function() blockr.extra::new_code_block(),
      data = iris,
      prompt = "return only the first 3 rows",
      grade = function(df) is.data.frame(df) && nrow(df) == 3L,
      tags = c("code_block", "easy", "structural")
    ),
    list(
      id = "code_filter_cyl4",
      make_block = function() blockr.extra::new_code_block(),
      data = mtcars,
      prompt = "keep only the cars with 4 cylinders",
      grade = function(df) {
        is.data.frame(df) && "cyl" %in% names(df) &&
          all(df$cyl == 4) && nrow(df) == 11L
      },
      tags = c("code_block", "medium", "filter")
    ),
    list(
      id = "code_add_ratio",
      make_block = function() blockr.extra::new_code_block(),
      data = iris,
      prompt = "add a column called ratio equal to Sepal.Length divided by Sepal.Width",
      grade = function(df) {
        is.data.frame(df) && "ratio" %in% names(df) && nrow(df) == 150L &&
          isTRUE(all.equal(df$ratio[1], iris$Sepal.Length[1] / iris$Sepal.Width[1]))
      },
      tags = c("code_block", "medium", "mutate")
    ),
    list(
      id = "fn_top5_mpg",
      make_block = function() blockr.extra::new_function_block(),
      data = mtcars,
      prompt = "show the 5 cars with the highest mpg",
      grade = function(df) {
        is.data.frame(df) && nrow(df) == 5L && "mpg" %in% names(df) &&
          min(df$mpg) >= sort(mtcars$mpg, decreasing = TRUE)[5]
      },
      tags = c("function_block", "medium", "sort")
    ),
    list(
      id = "code_group_mean",
      make_block = function() blockr.extra::new_code_block(),
      data = iris,
      prompt = "average Sepal.Length by Species",
      grade = function(df) {
        is.data.frame(df) && nrow(df) == 3L &&
          any(vapply(df, is.numeric, logical(1)))
      },
      tags = c("code_block", "hard", "aggregate")
    ),
    list(
      id = "code_gmail_substring",
      make_block = function() blockr.extra::new_code_block(),
      data = emails_df(),
      prompt = "keep only rows whose email address is a gmail.com address",
      grade = function(df) {
        is.data.frame(df) && nrow(df) == 3L &&
          all(grepl("gmail\\.com$", df$email))
      },
      tags = c("code_block", "hard", "substring")
    )
  )
}
