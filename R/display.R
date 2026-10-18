# display.R
# ---------------------------------------------------------------------------
# Everything that prints to the screen. Uses cli (ellmer already needs it).
# ---------------------------------------------------------------------------

# Header rule for each step, e.g. ── Step 3 ──────── 1,234 tokens | $0.012 ──
show_step_header <- function(step, stats) {
  cost <- if (is.na(stats$cost)) "cost n/a" else sprintf("$%.4f", stats$cost)
  right <- sprintf(
    "%s tokens | %s | %d tool calls",
    format(stats$tokens, big.mark = ","),
    cost,
    stats$tool_calls
  )
  cat("\n")
  cli::cat_rule(left = paste("Step", step), right = right, col = "cyan")
}

# Light markdown for the agent's text: **bold**, `code`, ```code blocks```.
# Prose is wrapped to the console width; code blocks are left as they are.
format_markdown <- function(text) {
  parts <- strsplit(text, "```", fixed = TRUE)[[1]]
  out <- character()
  for (i in seq_along(parts)) {
    part <- parts[[i]]
    if (i %% 2 == 0) {
      # Inside a code block: drop the language tag, colour the code
      code <- sub("^[A-Za-z]*\n", "", part)
      out <- c(out, cli::col_cyan(strsplit(trimws(code, "right"), "\n")[[1]]))
    } else {
      for (line in strsplit(part, "\n")[[1]]) {
        line <- gsub("\\*\\*(.+?)\\*\\*", cli::style_bold("\\1"), line)
        line <- gsub("`([^`]+)`", cli::col_cyan("\\1"), line)
        line <- gsub("^#+\\s*(.*)$", cli::style_bold("\\1"), line)
        width <- min(cli::console_width(), 100) - 2
        wrapped <- cli::ansi_strwrap(line, width = width)
        out <- c(out, if (length(wrapped)) wrapped else "")
      }
    }
  }
  out
}

show_agent_text <- function(text) {
  text <- trimws(text)
  if (!nzchar(text)) return(invisible())
  cat(format_markdown(text), sep = "\n")
}

# Show a tool call. R code gets syntax highlighting.
show_tool_call <- function(name, arguments) {
  cli::cat_line(cli::col_yellow(cli::symbol$arrow_right, " ", name))
  for (arg in names(arguments)) {
    value <- as.character(arguments[[arg]])
    if (arg == "code") {
      lines <- strsplit(value, "\n")[[1]]
      highlighted <- tryCatch(cli::code_highlight(lines), error = function(e) lines)
      cat(highlighted, sep = "\n")
    } else {
      cli::cat_line(cli::col_grey("  ", arg, ": "), clip_lines(value, 6))
    }
  }
}

# Show a tool result with a tick or a cross. Long results are cut short on
# screen (the LLM still sees the full result, up to max_result_chars).
show_tool_result <- function(text, is_error) {
  mark <- if (is_error) cli::col_red(cli::symbol$cross) else cli::col_green(cli::symbol$tick)
  cli::cat_line(mark, " ", cli::col_grey(clip_lines(text, 12)))
}

clip_lines <- function(text, n) {
  lines <- strsplit(as.character(text), "\n")[[1]]
  if (length(lines) > n) {
    lines <- c(lines[1:n], paste0("... [", length(lines) - n, " more lines]"))
  }
  paste(lines, collapse = "\n")
}

# Final summary in a box.
show_summary <- function(summary, stats, status) {
  width <- min(cli::console_width(), 80) - 6
  cost <- if (is.na(stats$cost)) "n/a" else sprintf("$%.4f", stats$cost)
  lines <- c(
    unlist(lapply(strsplit(summary, "\n")[[1]], function(line) {
      wrapped <- cli::ansi_strwrap(line, width = width)
      if (length(wrapped)) wrapped else ""
    })),
    "",
    cli::col_grey(sprintf(
      "Steps: %d | Tool calls: %d | Tokens: %s | Cost: %s",
      stats$steps, stats$tool_calls, format(stats$tokens, big.mark = ","), cost
    ))
  )
  colour <- if (status == "complete") "green" else "yellow"
  title <- if (status == "complete") "Task complete" else paste("Stopped:", status)
  cat("\n")
  print(cli::boxx(lines, header = title, border_col = colour, padding = 1))
}
