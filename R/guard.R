# guard.R
# ---------------------------------------------------------------------------
# A fast grep for risky code, run BEFORE the agent's code is executed.
#
# The guard runs in your R session (inside the installed package). The
# agent's code runs in the sandbox, a different process, so it can't switch
# the guard off while the agent is running.
#
# This is a tripwire, not a proof. Clever code can hide what it does (e.g.
# building function names from strings). That's why the "indirect call"
# patterns (eval, parse, do.call, get, ...) are on the list too: if the agent
# hides code, the hiding itself gets flagged.
# ---------------------------------------------------------------------------

# Each pattern is a regex and a plain English reason.
danger_patterns <- c(
  # Run other programs
  "\\b(system|system2|shell|shell\\.exec)\\s*\\(" = "runs a shell command",
  "\\b(processx|callr|sys)::" = "starts another process",
  "\\bRscript\\b|\\bR CMD\\b" = "starts another R process",
  # Delete or move files
  "\\b(unlink|file\\.remove|file\\.rename|file\\.copy|dir\\.remove)\\s*\\(" = "deletes, moves or copies files",
  "\\bfs::(file|dir)_(delete|move|copy)" = "deletes, moves or copies files",
  "\\brm\\s+-r" = "deletes files (rm -r)",
  # Internet
  "\\b(download\\.file|url|socketConnection|socketAccept|make\\.socket)\\s*\\(" = "uses the internet",
  "\\b(curl|httr|httr2|RCurl|websocket)::|library\\((curl|httr|httr2|RCurl)\\)" = "uses the internet",
  "https?://" = "mentions a web address",
  # Hidden or indirect code
  "\\b(eval|evalq|parse|str2lang|str2expression|do\\.call|match\\.fun|get|get0|mget)\\s*\\(" = "builds or runs code indirectly",
  "\\bsource\\s*\\(|\\bsys\\.source\\s*\\(" = "runs code from another file",
  "\\.(Internal|Primitive|Call|External|C)\\s*\\(" = "calls R internals",
  "base64|rawToChar|intToUtf8|chartr\\s*\\(" = "decodes text (could hide code)",
  # Change the R setup or this package
  "\\b(install\\.packages|remove\\.packages|devtools::install|remotes::install|pak::)" = "installs or removes packages",
  "\\.libPaths|R_LIBS|\\.Library|find\\.package|system\\.file" = "touches the R library",
  "turbochook" = "mentions the turbochook package",
  "\\b(Sys\\.setenv|Sys\\.unsetenv|Sys\\.chmod|setwd)\\s*\\(" = "changes the environment or working folder",
  "\\.Rprofile|\\.Renviron" = "touches R startup files",
  # Escape the project folder
  "\\.\\./|~/|\\bpath\\.expand\\s*\\(|\\bnormalizePath\\s*\\(" = "points outside the project folder"
)

#' Scan code for risky patterns
#'
#' @param code A string of code (or file contents).
#' @param patterns Named character vector: regex = reason.
#' @return A character vector of reasons (empty if nothing found).
#' @examples
#' scan_code("unlink('data', recursive = TRUE)")
#' @export
scan_code <- function(code, patterns = danger_patterns) {
  hits <- vapply(names(patterns), grepl, logical(1), x = code, perl = TRUE)
  reasons <- patterns[hits]
  if (length(reasons) == 0) return(character())
  # Show the matching text too, so the user can see what was found
  found <- vapply(names(reasons), function(p) {
    regmatches(code, regexpr(p, code, perl = TRUE))
  }, character(1))
  unique(paste0(reasons, ": ", trimws(found)))
}

# What to scan for each tool call. R code is always scanned. For file
# writes we scan the path, and the content too if it is a code file
# (writing code is harmless until it is run, but run_r_code can source it).
guard_check <- function(name, arguments, wd = getwd()) {
  if (name == "run_r_code") {
    return(scan_code(inline_sourced_files(arguments$code, wd)))
  }
  if (name %in% c("write_file", "edit_file")) {
    text <- arguments$path
    if (grepl("\\.(R|r|Rmd|qmd|sh|py|bat|ps1)$|^\\.R(profile|environ)", basename(text))) {
      text <- paste(text, arguments$content, arguments$new_text, sep = "\n")
    }
    return(scan_code(text))
  }
  character()
}

# source("R/file.R") is fine if the file itself is fine. So for each
# source() of a project file (given as a plain string), swap the call for
# the file's contents, and scan that. Anything else, like source(x) or a
# file outside the project, is left in and gets flagged.
inline_sourced_files <- function(code, wd) {
  pattern <- "\\bsource\\s*\\(\\s*[\"']([^\"']+)[\"'][^)]*\\)"
  calls <- regmatches(code, gregexpr(pattern, code, perl = TRUE))[[1]]
  for (call in calls) {
    path <- sub(pattern, "\\1", call, perl = TRUE)
    full <- tryCatch(check_path(path, wd), error = function(e) NULL)
    if (is.null(full) || !file.exists(full)) next
    contents <- paste(readLines(full, warn = FALSE), collapse = "\n")
    code <- sub(call, contents, code, fixed = TRUE)
  }
  code
}

# Pause the agent and ask the user. Returns TRUE to allow, FALSE to block.
# When nobody is there to ask (e.g. running from Rscript), we block.
guard_ask <- function(tool_name, reasons) {
  show_warning(tool_name, reasons)
  if (!interactive()) {
    cli::cli_alert_danger("Not an interactive session, so the call was blocked.")
    return(FALSE)
  }
  answer <- readline("Allow this tool call? [y = yes, n = no]: ")
  tolower(trimws(answer)) %in% c("y", "yes")
}
