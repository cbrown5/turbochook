# prompt.R
# ---------------------------------------------------------------------------
# The system prompt. Kept short on purpose. It has three parts:
#   1. A few lines on how to behave
#   2. AGENTS.md, if the project has one
#   3. A directory of skills (names + descriptions only, not the full text)
# The tool definitions are sent by ellmer, so they aren't repeated here.
# ---------------------------------------------------------------------------

base_prompt <- "You are Turbo Chook, a coding agent working in an R project.
Working folder: {wd}

Use the tools to do the task. Look before you change things: read files
before editing them, and check the results of your code.
run_r_code runs in a persistent R session, so objects stay between calls.
To run a project script from a clean start, use run_r_script. To run it in
the persistent session, use source('path/to/script.R'). Never use system(),
system2() or Rscript to run R code; those calls get blocked.
Save plots and outputs to files; there is no screen.
Keep your replies short. When the task is done, call task_complete with a
short summary for the user."

build_system_prompt <- function(wd = getwd()) {
  prompt <- gsub("{wd}", wd, base_prompt, fixed = TRUE)

  agents_file <- file.path(wd, "AGENTS.md")
  if (file.exists(agents_file)) {
    agents <- paste(readLines(agents_file, warn = FALSE), collapse = "\n")
    prompt <- paste0(prompt, "\n\n# Project instructions (AGENTS.md)\n\n", agents)
  }

  skills <- find_skills(file.path(wd, "skills"), wd)
  if (nrow(skills) > 0) {
    lines <- sprintf("- %s: %s (read %s)", skills$name, skills$description, skills$path)
    prompt <- paste0(
      prompt,
      "\n\n# Skills\n\n",
      "These skills have extra instructions. Only read a skill's file with ",
      "read_file when the task needs it.\n",
      paste(lines, collapse = "\n")
    )
  }

  prompt
}

# Look for skills/<name>/SKILL.md or skills/<name>.md.
# The description comes from a `description:` line in the YAML header,
# or failing that the first non-empty line of the file.
find_skills <- function(dir, wd = getwd()) {
  empty <- data.frame(name = character(), description = character(), path = character())
  if (!dir.exists(dir)) return(empty)

  files <- c(
    list.files(dir, pattern = "^SKILL\\.md$", recursive = TRUE, full.names = TRUE),
    list.files(dir, pattern = "\\.md$", full.names = TRUE)
  )
  files <- unique(files)
  if (length(files) == 0) return(empty)

  rows <- lapply(files, function(file) {
    lines <- readLines(file, warn = FALSE)
    name <- if (basename(file) == "SKILL.md") basename(dirname(file)) else sub("\\.md$", "", basename(file))
    name_line <- grep("^name:", lines, value = TRUE)[1]
    if (!is.na(name_line)) name <- trimws(sub("^name:", "", name_line))

    description <- grep("^description:", lines, value = TRUE)[1]
    if (is.na(description)) {
      text <- lines[nzchar(trimws(lines)) & !grepl("^---", lines)]
      description <- if (length(text)) text[1] else ""
    }
    description <- trimws(sub("^description:", "", description))

    data.frame(name = name, description = description, path = relative_path(file, wd))
  })
  do.call(rbind, rows)
}

relative_path <- function(path, wd = getwd()) {
  path <- normalizePath(path, mustWork = FALSE)
  wd <- normalizePath(wd, mustWork = FALSE)
  prefix <- paste0(wd, "/")
  ifelse(startsWith(path, prefix), substring(path, nchar(prefix) + 1), path)
}
