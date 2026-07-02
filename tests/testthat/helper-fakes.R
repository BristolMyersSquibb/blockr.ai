# Shared fakes for harness tests (test-harness-ellmer.R, test-run-log.R).
# testthat sources helper-*.R before every test file.

# A minimal block-like object: discover only needs attr(.,"ctor") for var names
# and class() for (best-effort, NULL-tolerant) registry lookups.
fake_block <- function(ctor = function(value = "x", ...) NULL) {
  structure(list(), class = c("fake_block", "block"), ctor = ctor)
}

# A validate function independent of any real block/testServer: "good" succeeds
# and returns a data.frame; anything else throws.
good_validate <- function(args) {
  if (identical(args$value, "good")) {
    return(data.frame(a = 1:3, b = letters[1:3]))
  }
  stop("value must be 'good', got: ", args$value %||% "NULL")
}

# Fake ellmer chat client: replays a sequence of validate_config calls, then
# returns final text. Implements only the methods the harness uses.
make_fake_chat <- function(configs = character(), final_text = "Done.") {
  tools <- NULL
  list(
    set_system_prompt = function(p) invisible(NULL),
    set_tools = function(t) {
      tools <<- t
      invisible(NULL)
    },
    get_tools = function() tools,
    chat = function(msg, ...) {
      vt <- Find(function(td) isTRUE(td@name == "validate_config"), tools)
      for (cfg in configs) {
        if (!is.null(vt)) {
          # Mimic the model: validate_config now takes the block's params as
          # native arguments, so decode the JSON config and call with them.
          args <- tryCatch(jsonlite::fromJSON(cfg, simplifyVector = FALSE),
                           error = function(e) NULL)
          if (is.list(args) && length(args)) do.call(vt, args) else vt(config = cfg)
        }
      }
      final_text
    }
  )
}

with_fake_chat <- function(chat, expr) {
  withr::with_options(
    list(blockr.chat_function = list("gpt-4o-mini" = function() chat)),
    expr
  )
}
