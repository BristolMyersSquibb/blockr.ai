# Exhaustive eval: drive every composer template against the pharmaverseadam dm
# and record what works, what doesn't, and whether failures answer gracefully.
readRenviron("/workspace/.Renviron"); .libPaths("/workspace/blockr.dev/.devcontainer/.library")
suppressMessages({
  pkgload::load_all("blockr.core",quiet=TRUE); pkgload::load_all("blockr.dm",quiet=TRUE)
  pkgload::load_all("blockr.extra",quiet=TRUE); pkgload::load_all("blockr.sandbox",quiet=TRUE)
  pkgload::load_all("blockr.ai",quiet=TRUE); library(dm)
})
options(blockr.skill_library = system.file("skills", package="blockr.sandbox"))
adam <- eval(blockr.dm:::pharmaverseadam_expr())
`%||%` <- function(a,b) if (is.null(a)||!length(a)||!nzchar(as.character(a)[1])) b else a

tdir <- "blockr.sandbox/inst/extdata/composer-templates"
files <- sort(list.files(tdir, pattern="\\.R$"))
labelOf <- function(f) sub("^#\\s*Label:\\s*","", grep("^#\\s*Label:", readLines(file.path(tdir,f), warn=FALSE), value=TRUE)[1])

fetched <- function(cl){o<-character();for(t in cl$get_turns())for(ct in t@contents)if(inherits(ct,"ellmer::ContentToolRequest")&&ct@name=="read_skill_file")o<-c(o,ct@arguments$path %||% "");paste(o,collapse=";")}
lastmsg <- function(res){ res$question %||% res$error %||% (if(!is.null(res$result)) tryCatch(data_effect(NULL,res$result),error=function(e)"") else "") }

rows <- list()
for (i in seq_along(files)) {
  f <- files[i]; id <- sub("\\.R$","",f); lab <- labelOf(f)
  ask <- sprintf("Use the composer skill to build the '%s' table (template %s) for this connected data.", lab, id)
  cl <- ellmer::chat_openai(model="gpt-5.1", echo="none")
  res <- tryCatch(discover_block_args(prompt=ask, block=new_function_block(fn=function(data) data), data=adam, client=cl),
                  error=function(e) list(success=FALSE, error=conditionMessage(e)))
  eff <- if(!is.null(res$result)) tryCatch(data_effect(NULL,res$result),error=function(e)"") else ""
  pop <- grepl("^populated", eff)
  stage <- if (isTRUE(res$success) && pop) "OK-POPULATED" else if (isTRUE(res$success)) "RAN-NOT-POP" else if (!is.null(res$question)) "ASKED" else "FAILED"
  got <- sub("templates/","",fetched(cl)); gotright <- grepl(id, got, fixed=TRUE)
  detail <- substr(gsub("\\s+"," ", lastmsg(res)), 1, 150)
  rows[[i]] <- data.frame(id=id, stage=stage, fetched_right=gotright, detail=detail, stringsAsFactors=FALSE)
  cat(sprintf("[%2d/%d] %-26s %-13s fetch=%s | %s\n", i, length(files), id, stage, gotright, detail))
}
out <- do.call(rbind, rows)
saveRDS(out, "/tmp/skills-eval-all.rds")
cat("\n===== SUMMARY =====\n"); print(table(out$stage))
cat("fetched correct template:", sum(out$fetched_right), "/", nrow(out), "\n")
