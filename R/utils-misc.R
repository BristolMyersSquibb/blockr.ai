eval_code <- function(code, data) {
  # Optional warning for file operations that might not be intended
  if (grepl("read\\.(csv|xlsx|table)|write\\.", code)) {
    warning("Code contains file I/O operations - consider using provided data instead", 
            call. = FALSE)
  }
  
  eval(
    parse(text = code),
    envir = list2env(data, parent = globalenv())
  )
}

try_eval_code <- function(...) {
  tryCatch(
    {
      res <- eval_code(...)

      # plots might not fail at definition time but only when printing.
      # We trigger the failure early with ggplotGrob()
      if (ggplot2::is_ggplot(res)) {
        suppressMessages(ggplot2::ggplotGrob(res))
      }

      res
    },
    error = function(e) {
      structure(conditionMessage(e), class = "try-error")
    }
  )
}

style_code <- function(code) {
  paste0(styler::style_text(code), collapse = "\n")
}

last <- function(x) x[[length(x)]]

split_newline <- function(...) {
  strsplit(paste0(..., collapse = ""), "\n", fixed = TRUE)[[1L]]
}

#' Validate gt objects are properly constructed
#' @param obj Object to validate
#' @return List with 'valid' (logical) and 'message' (character)
validate_gt_object <- function(obj) {
  if (!inherits(obj, "gt_tbl")) {
    return(list(valid = FALSE, message = "Object is not a gt_tbl. Use gt::gt() to create gt objects."))
  }
  
  # Check for essential gt structure - only check the most critical ones
  required_components <- c("_data", "_boxhead", "_options")
  
  missing_components <- setdiff(required_components, names(obj))
  if (length(missing_components) > 0) {
    return(list(valid = FALSE, message = paste0("gt object missing essential components: ", paste(missing_components, collapse = ", "))))
  }
  
  # Check if data component exists and is valid
  if (is.null(obj[["_data"]]) || !is.data.frame(obj[["_data"]])) {
    return(list(valid = FALSE, message = "gt object missing or invalid _data component. Ensure gt::gt(your_data) was called properly."))
  }
  
  return(list(valid = TRUE, message = ""))
}

#' Validate ggplot objects are properly constructed
#' @param obj Object to validate  
#' @return List with 'valid' (logical) and 'message' (character)
validate_ggplot_object <- function(obj) {
  if (!ggplot2::is_ggplot(obj)) {
    return(list(valid = FALSE, message = "Object is not a ggplot. Use ggplot2::ggplot() to create plots."))
  }
  
  # Check for essential ggplot components - empty ggplot() has no data and no layers
  # An empty ggplot has data as "waiver" class or NULL/empty data.frame
  data_empty <- is.null(obj$data) || 
                inherits(obj$data, "waiver") ||
                (is.data.frame(obj$data) && nrow(obj$data) == 0)
  if (data_empty && length(obj$layers) == 0) {
    return(list(valid = FALSE, message = "ggplot object has no data or layers. Add geom_*() functions."))
  }
  
  # Try to build the plot to catch rendering issues early
  build_result <- try(ggplot2::ggplot_build(obj), silent = TRUE)
  if (inherits(build_result, "try-error")) {
    return(list(valid = FALSE, message = paste0("ggplot object cannot be rendered: ", as.character(build_result))))
  }
  
  return(list(valid = TRUE, message = ""))
}

#' Validate data.frame objects are properly constructed
#' @param obj Object to validate
#' @return List with 'valid' (logical) and 'message' (character)
validate_dataframe_object <- function(obj) {
  if (!is.data.frame(obj)) {
    return(list(valid = FALSE, message = "Object is not a data.frame. Transform operations must return data.frame objects."))
  }
  
  if (nrow(obj) == 0 && ncol(obj) == 0) {
    return(list(valid = FALSE, message = "data.frame is completely empty (0 rows, 0 columns). Ensure your transformation produces valid output."))
  }
  
  return(list(valid = TRUE, message = ""))
}

#' Validate block result based on block type
#' @param obj Result object to validate
#' @param block_proxy LLM block proxy object to determine validation type
#' @return List with 'valid' (logical) and 'message' (character)
validate_block_result <- function(obj, block_proxy) {
  # Fallback to basic type checking first
  result_ptype <- result_ptype(block_proxy)
  result_base_class <- class(result_ptype)[1]  # Get first class, not last
  
  if (!inherits(obj, result_base_class)) {
    return(list(
      valid = FALSE, 
      message = paste0(
        "Expected object inheriting from `", result_base_class, 
        "` but got `", paste(class(obj), collapse = ", "), 
        "`. Check your code returns the correct object type."
      )
    ))
  }
  
  # Enhanced validation based on specific block type
  if (inherits(block_proxy, "llm_gt_block_proxy")) {
    return(validate_gt_object(obj))
  } else if (inherits(block_proxy, "llm_plot_block_proxy")) {
    return(validate_ggplot_object(obj))  
  } else if (inherits(block_proxy, "llm_transform_block_proxy")) {
    return(validate_dataframe_object(obj))
  }
  
  # Default: passed basic type check
  return(list(valid = TRUE, message = ""))
}

log_wrap <- function(..., level = "info") {
  for (tok in strwrap(split_newline(...), width = 0.7 * getOption("width"))) {
    write_log(tok, level = level)
  }
}

log_asis <- function(..., level = "info") {
  for (tok in split_newline(...)) {
    write_log(tok, level = level)
  }
}
