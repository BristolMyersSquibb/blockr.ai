# AI Control Showcase — All AI-Ready Blocks
#
# Demonstrates every blockr.dplyr block that supports AI control.
# Each block is independently connected to a dataset block so you can
# test them one-by-one via the "AI Assist" chat overlay.
#
# Usage:
#   1. Start the app
#   2. Expand "AI Assist" on any block
#   3. Type a natural language instruction
#
# Example prompts per block:
#   select:         "keep only mpg, cyl, and hp"
#   filter:         "only 6 cylinder cars"
#   filter_expr:    "mpg > 25 and wt < 3"
#   arrange:        "sort by mpg descending"
#   rename:         "rename mpg to miles_per_gallon"
#   slice:          "top 5 rows by horsepower"
#   mutate:         "add a column hp_per_cyl = hp / cyl"
#   summarize:      "average mpg and count, grouped by cyl"
#   summarize_expr: "mean(hp) as avg_hp grouped by gear"
#   pivot_longer:   "pivot mpg and hp into long format"
#   unite:          use the unite block on people data
#   separate:       use the separate block on people data

pkgload::load_all("../blockr.core")
pkgload::load_all("../blockr.dock")
pkgload::load_all("../blockr.dag")
pkgload::load_all("../blockr.dplyr")
pkgload::load_all("../blockr.ai")

# --- helpers -----------------------------------------------------------------

people <- data.frame(
  first = c("John", "Jane", "Bob"),
  last = c("Doe", "Smith", "Jones"),
  age = c(30, 25, 45),
  stringsAsFactors = FALSE
)

people_united <- data.frame(
  full_name = c("John Doe", "Jane Smith", "Bob Jones"),
  age = c(30, 25, 45),
  stringsAsFactors = FALSE
)

wide <- data.frame(
  id = 1:3,
  col_a = c(10, 20, 30),
  col_b = c(15, 25, 35)
)

long <- data.frame(
  id = c(1, 1, 2, 2, 3, 3),
  variable = rep(c("a", "b"), 3),
  value = c(10, 15, 20, 25, 30, 35)
)

# --- board -------------------------------------------------------------------

serve(
  new_dock_board(
    blocks = c(
      # ---- data sources ----
      mtcars_data   = new_dataset_block("mtcars"),

      people_data   = new_static_block(people),
      united_data   = new_static_block(people_united),
      wide_data     = new_static_block(wide),
      long_data     = new_static_block(long),

      # ---- column operations ----
      select        = new_select_block(columns = c("mpg", "cyl", "hp")),
      rename        = new_rename_block(renames = list(miles_per_gallon = "mpg")),

      # ---- row operations ----
      filter        = new_filter_block(),
      filter_expr   = new_filter_expr_block("mpg > 20"),
      arrange       = new_arrange_block(columns = "mpg"),
      slice         = new_slice_block(type = "head", n = 10),

      # ---- mutations ----
      mutate        = new_mutate_expr_block(
                        exprs = list(hp_per_cyl = "hp / cyl")
                      ),

      # ---- aggregations ----
      summarize     = new_summarize_block(
                        summaries = list(
                          avg_mpg = list(func = "mean", col = "mpg"),
                          count   = list(func = "dplyr::n", col = "")
                        ),
                        by = "cyl"
                      ),
      summarize_expr = new_summarize_expr_block(
                         exprs = list(avg_hp = "mean(hp)", n = "dplyr::n()"),
                         by = "cyl"
                       ),

      # ---- reshape ----
      pivot_longer  = new_pivot_longer_block(
                        cols = c("col_a", "col_b"),
                        names_to = "variable",
                        values_to = "value"
                      ),
      pivot_wider   = new_pivot_wider_block(
                        names_from = "variable",
                        values_from = "value"
                      ),

      # ---- string operations ----
      unite         = new_unite_block(
                        col = "full_name",
                        cols = c("first", "last"),
                        sep = " "
                      ),
      separate      = new_separate_block(
                        col = "full_name",
                        into = c("first", "last"),
                        sep = " "
                      )
    ),
    links = c(
      # mtcars pipeline
      new_link("mtcars_data", "select",         "data"),
      new_link("mtcars_data", "rename",          "data"),
      new_link("mtcars_data", "filter",          "data"),
      new_link("mtcars_data", "filter_expr",     "data"),
      new_link("mtcars_data", "arrange",         "data"),
      new_link("mtcars_data", "slice",           "data"),
      new_link("mtcars_data", "mutate",          "data"),
      new_link("mtcars_data", "summarize",       "data"),
      new_link("mtcars_data", "summarize_expr",  "data"),

      # reshape
      new_link("wide_data",   "pivot_longer",    "data"),
      new_link("long_data",   "pivot_wider",     "data"),

      # string ops
      new_link("people_data", "unite",           "data"),
      new_link("united_data", "separate",        "data")
    ),
    extensions = list(dag = new_dag_extension())
  ),
  plugins = custom_plugins(ai_ctrl_block())
)
