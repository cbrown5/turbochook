# tools.R
# ---------------------------------------------------------------------------
# The six default tools, plus the optional vision tool.
#
# Each tool is made with ellmer::tool(), the same way you'd make your own.
# They share a small environment, `ctx`, that holds the project folder, the
# sandbox session and whether task_complete has been called.
#
# A tool that fails calls stop(). ellmer sends the error to the LLM, and the
# screen shows a red cross.
# ---------------------------------------------------------------------------

make_default_tools <- function(ctx) {
  read_file <- ellmer::tool(
    function(path) {
      path <- check_path(path, ctx$wd)
      if (dir.exists(path)) {
        files <- list.files(path, recursive = TRUE, all.files = FALSE)
        return(clip_chars(paste(files, collapse = "\n"), ctx$max_result_chars))
      }
      if (!file.exists(path)) stop("File not found: ", path)
      lines <- readLines(path, warn = FALSE)
      numbered <- sprintf("%4d  %s", seq_along(lines), lines)
      clip_chars(paste(numbered, collapse = "\n"), ctx$max_result_chars)
    },
    name = "read_file",
    description = "Read a text file (shown with line numbers). Give a folder to list its files.",
    arguments = list(
      path = ellmer::type_string("Path to the file or folder, relative to the working folder.")
    )
  )

  write_file <- ellmer::tool(
    function(path, content) {
      path <- check_path(path, ctx$wd)
      dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
      writeLines(content, path)
      paste("Wrote", length(strsplit(content, "\n")[[1]]), "lines to", path)
    },
    name = "write_file",
    description = "Create or overwrite a file with the given content.",
    arguments = list(
      path = ellmer::type_string("Path to the file, relative to the working folder."),
      content = ellmer::type_string("The full content of the file.")
    )
  )

  edit_file <- ellmer::tool(
    function(path, old_text, new_text) {
      path <- check_path(path, ctx$wd)
      if (!file.exists(path)) stop("File not found: ", path)
      text <- paste(readLines(path, warn = FALSE), collapse = "\n")
      n <- lengths(regmatches(text, gregexpr(old_text, text, fixed = TRUE)))
      if (n == 0) stop("old_text was not found in the file. Read the file and copy the text exactly.")
      if (n > 1) stop("old_text was found ", n, " times. Add more context so it is unique.")
      text <- sub(old_text, new_text, text, fixed = TRUE)
      writeLines(text, path)
      paste("Edited", path)
    },
    name = "edit_file",
    description = "Replace one exact piece of text in a file. old_text must appear exactly once.",
    arguments = list(
      path = ellmer::type_string("Path to the file, relative to the working folder."),
      old_text = ellmer::type_string("The exact text to replace."),
      new_text = ellmer::type_string("The text to put in its place.")
    )
  )

  run_r_code <- ellmer::tool(
    function(code) {
      # Restart the sandbox if the last call killed it
      if (!ctx$session$is_alive()) {
        ctx$session <- sandbox_start(ctx$wd, ctx$block_internet)
      }
      result <- sandbox_run(ctx$session, code, timeout = ctx$timeout)
      clip_chars(result, ctx$max_result_chars)
    },
    name = "run_r_code",
    description = paste(
      "Run R code in a persistent R session (objects are kept between calls).",
      "Printed output, warnings and errors are returned."
    ),
    arguments = list(
      code = ellmer::type_string("The R code to run.")
    )
  )

  run_r_script <- ellmer::tool(
    function(path) {
      path <- check_path(path, ctx$wd)
      if (!file.exists(path) || dir.exists(path)) stop("File not found: ", path)
      result <- sandbox_script(path, ctx$wd, ctx$block_internet, timeout = ctx$timeout)
      clip_chars(result, ctx$max_result_chars)
    },
    name = "run_r_script",
    description = paste(
      "Run an R script from the project in a fresh R session, like `Rscript script.R`.",
      "Use this (not system2 or Rscript) to run a pipeline from a clean start.",
      "Objects it makes are not kept; save results to files."
    ),
    arguments = list(
      path = ellmer::type_string("Path to the script, relative to the working folder.")
    )
  )

  task_complete <- ellmer::tool(
    function(summary) {
      ctx$summary <- summary
      ctx$done <- TRUE
      "Task marked complete."
    },
    name = "task_complete",
    description = "Call this when the task is finished. Ends the session.",
    arguments = list(
      summary = ellmer::type_string("A short summary of what you did, for the user.")
    )
  )

  list(read_file, write_file, edit_file, run_r_code, run_r_script, task_complete)
}

# Vision: the agent can ask a vision model about an image file.
# `vision_chat` is any ellmer chat with a model that can see images.
# A fresh copy is used for each question, so images don't pile up.
make_vision_tool <- function(ctx, vision_chat) {
  ellmer::tool(
    function(path, question) {
      path <- check_path(path, ctx$wd)
      if (!file.exists(path)) stop("File not found: ", path)
      chat <- vision_chat$clone(deep = TRUE)
      answer <- with_retry(chat$chat(question, ellmer::content_image_file(path, resize = "none"), echo = "none"))
      # Add the vision model's usage to the agent's totals
      tokens <- chat$get_tokens()
      ctx$extra_tokens <- ctx$extra_tokens + sum(tokens$input, tokens$output)
      ctx$extra_cost <- ctx$extra_cost + as.numeric(chat$get_cost())
      as.character(answer)
    },
    name = "look_at_image",
    description = "Ask a vision model a question about an image file (png, jpeg, ...), e.g. to check a plot.",
    arguments = list(
      path = ellmer::type_string("Path to the image, relative to the working folder."),
      question = ellmer::type_string("What you want to know about the image.")
    )
  )
}

#' Make a vision tool for an agent
#'
#' Usually you just pass `vision = TRUE` to [agent()]. Use this to see what
#' model is used by default.
#'
#' @param model Model name for the vision chat.
#' @return An ellmer chat object.
#' @export
vision_tool <- function(model = "claude-sonnet-5-5") {
  ellmer::chat_anthropic(model = model, echo = "none")
}

# Resolve a path and make sure it is inside the project folder.
# The file tools run in YOUR R session, so this check can't be bypassed
# by the agent's code.
check_path <- function(path, wd) {
  if (grepl("(^|[/\\\\])\\.\\.([/\\\\]|$)", path)) {
    stop("Paths with '..' are not allowed: ", path)
  }
  root <- normalizePath(wd, mustWork = FALSE)
  is_absolute <- grepl("^(/|~|[A-Za-z]:)", path)
  full <- if (is_absolute) path.expand(path) else file.path(root, path)
  # Resolve symlinks for whatever part of the path already exists
  full <- if (file.exists(full)) {
    normalizePath(full)
  } else {
    file.path(normalizePath(dirname(full), mustWork = FALSE), basename(full))
  }
  inside <- full == root || startsWith(full, paste0(root, "/"))
  if (!inside) stop("Path is outside the working folder: ", path)
  if (any(startsWith(full, normalizePath(.libPaths(), mustWork = FALSE)))) {
    stop("Path is inside the R library, which is off limits: ", path)
  }
  full
}

# Keep long outputs short, to save tokens
clip_chars <- function(text, max_chars) {
  if (nchar(text) > max_chars) {
    text <- paste0(substr(text, 1, max_chars), "\n...[output truncated]")
  }
  text
}
