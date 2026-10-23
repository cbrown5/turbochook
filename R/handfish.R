# handfish.R
# ---------------------------------------------------------------------------
# Handfish: a smaller agent than turbochook(), for teaching.
#
# Same loop, fewer moving parts:
#
#   1. THINK   - send a message to the LLM, it replies with text and
#                optionally a tool call
#   2. ASK     - show you the call and wait for you to approve it
#   3. ACT     - run the tool in R
#   4. OBSERVE - send the result back to the LLM
#   ... repeat until the LLM calls task_complete
#
# What it drops compared with turbochook(): the callr sandbox, the vision
# tool, skills, rate limit retries, run_r_script and edit_file. Code runs in
# YOUR R session. The safety comes from step 2 instead: nothing happens
# unless you say yes.
#
# Approval lives inside the tools, not in a hook. A hook can watch a tool
# call but cannot stop it; a tool can. When you decline, the tool calls
# stop(), and ellmer passes that back to the LLM as the result, so the agent
# learns it was refused and can try something else.
# ---------------------------------------------------------------------------

#' Run a small agent that asks before it does anything
#'
#' A simpler sibling of [turbochook()], written for teaching. It has four
#' tools (`read_file`, `write_file`, `run_r_code`, `task_complete`) and asks
#' you to approve every tool call before it runs.
#'
#' Unlike [turbochook()], the agent's code runs in your own R session, with
#' no sandbox. Approval is the safety: read each call before you accept it.
#'
#' @param task What you want done, in plain words.
#' @param chat An ellmer chat object. A copy is used, so your object isn't
#'   changed.
#' @param max_steps Most LLM replies before stopping.
#' @param wd The project folder. The file tools can only touch files in here.
#' @param approve A function called with the tool name and its arguments,
#'   returning `TRUE` to run the call. The default asks you in the console.
#'   Pass your own for tests, or `function(name, args) TRUE` to approve
#'   everything.
#' @return Invisibly, a list with the summary, status, counts, cost and the
#'   chat (so you can carry on talking to it).
#' @examples
#' \dontrun{
#' handfish("Make a file called hello.R that prints 'hi', then run it.")
#' }
#' @export
handfish <- function(task,
                     chat = ellmer::chat_anthropic(model = "claude-sonnet-5-5"),
                     max_steps = 20,
                     wd = getwd(),
                     approve = ask_approval) {
  # ---- Set up -------------------------------------------------------------

  # Shared state for the tools
  ctx <- new.env()
  ctx$wd <- normalizePath(wd)
  ctx$approve <- approve
  ctx$done <- FALSE
  ctx$summary <- NULL

  chat <- chat$clone(deep = TRUE) # deep, so our hooks stay on our copy
  chat$set_system_prompt(handfish_prompt(ctx$wd))
  chat$set_tools(make_handfish_tools(ctx))

  steps <- 0 # LLM replies so far
  tool_calls <- 0 # tools we have actually run

  stats <- function() {
    tokens <- chat$get_tokens()
    list(
      steps = steps,
      tool_calls = tool_calls,
      tokens = sum(tokens$input, tokens$output, tokens$cached_input),
      cost = as.numeric(chat$get_cost())
    )
  }

  # Called whenever we might be looking at a new LLM reply. If it is new,
  # print the step header and the LLM's text. We can't just count laps of
  # the loop below, because one lap can hold several replies: ellmer keeps
  # going round while the LLM calls tools.
  replies_seen <- 0
  check_new_step <- function() {
    replies <- sum(vapply(chat$get_turns(), function(t) t@role == "assistant", logical(1)))
    if (replies > replies_seen) {
      replies_seen <<- replies
      steps <<- steps + 1
      show_step_header(steps, stats())
      show_agent_text(chat$last_turn()@text)
    }
    steps >= max_steps
  }

  # ---- Hooks: just for showing what is going on ---------------------------
  # The approval itself happens inside the tools, see make_handfish_tools().

  chat$on_tool_request(function(request) {
    if (check_new_step()) stop_agent("max_steps")
    show_tool_call(request@name, request@arguments)
    tool_calls <<- tool_calls + 1
  })

  chat$on_tool_result(function(result) {
    is_error <- !is.null(result@error)
    text <- if (is_error) error_text(result@error) else paste(result@value, collapse = "\n")
    show_tool_result(text, is_error)
    if (ctx$done) stop_agent("complete")
  })

  # ---- The loop -----------------------------------------------------------

  cli::cli_h1("Handfish")
  show_agent_text(task)

  message_to_llm <- task # the first message is the task itself

  repeat {
    # THINK (and, via the tools, ASK / ACT / OBSERVE until the LLM has
    # nothing more to call)
    outcome <- withCallingHandlers(
      tryCatch(
        {
          chat$chat(message_to_llm, echo = "none")
          "replied"
        },
        turbochook_stop = function(cond) conditionMessage(cond)
      ),
      # ellmer warns about failed tool calls; we've already shown them
      ellmer_tool_failure = function(w) invokeRestart("muffleWarning")
    )

    # A hook stopped us: the agent called task_complete, or we ran out of steps
    if (outcome != "replied") {
      status <- outcome
      break
    }

    # The LLM replied with text and no tool call. Show it and nudge.
    if (check_new_step()) {
      status <- "max_steps"
      break
    }
    message_to_llm <- "Carry on with the task. If it is finished, call task_complete."
  }

  # ---- Wrap up ------------------------------------------------------------

  summary <- ctx$summary %||% paste0(
    "The agent stopped before calling task_complete (", status, ")."
  )
  final <- stats()
  show_summary(summary, final, status)

  invisible(c(
    list(summary = summary, status = status),
    final,
    list(chat = chat)
  ))
}

# ---------------------------------------------------------------------------
# Approval
# ---------------------------------------------------------------------------

# Ask in the console. Returns TRUE to run the call.
# Anything that isn't "y" is a no, so a stray keypress is safe.
ask_approval <- function(name, arguments) {
  if (!interactive()) {
    stop(
      "handfish() needs an interactive session to approve tool calls. ",
      "Pass your own `approve` function to run it unattended.",
      call. = FALSE
    )
  }
  cli::cat_line(cli::col_yellow("  Run this ", name, " call? [y/N] "))
  answer <- tolower(trimws(readline()))
  identical(answer, "y") || identical(answer, "yes")
}

# Wrap a tool function so it asks first. If you say no, it stops() and the
# refusal goes back to the LLM as the tool's result.
#
# The wrapper keeps `fun`'s own arguments rather than taking `...`, because
# ellmer::tool() checks the function's formals against the argument list we
# declare for the LLM.
with_approval <- function(ctx, name, fun) {
  wrapper <- function() {
    args <- as.list(environment())
    if (!isTRUE(ctx$approve(name, args))) {
      stop("The user declined this call. Ask them what to do instead.")
    }
    do.call(fun, args)
  }
  formals(wrapper) <- formals(fun)
  wrapper
}

# ---------------------------------------------------------------------------
# The four tools
# ---------------------------------------------------------------------------

make_handfish_tools <- function(ctx) {
  read_file <- ellmer::tool(
    with_approval(ctx, "read_file", function(path) {
      path <- check_path(path, ctx$wd)
      if (dir.exists(path)) {
        return(paste(list.files(path, recursive = TRUE), collapse = "\n"))
      }
      if (!file.exists(path)) stop("File not found: ", path)
      paste(readLines(path, warn = FALSE), collapse = "\n")
    }),
    name = "read_file",
    description = "Read a text file. Give a folder to list its files.",
    arguments = list(
      path = ellmer::type_string("Path to the file or folder, relative to the working folder.")
    )
  )

  write_file <- ellmer::tool(
    with_approval(ctx, "write_file", function(path, content) {
      path <- check_path(path, ctx$wd)
      dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
      writeLines(content, path)
      paste("Wrote", path)
    }),
    name = "write_file",
    description = "Create or overwrite a file with the given content.",
    arguments = list(
      path = ellmer::type_string("Path to the file, relative to the working folder."),
      content = ellmer::type_string("The full content of the file.")
    )
  )

  run_r_code <- ellmer::tool(
    with_approval(ctx, "run_r_code", function(code) {
      handfish_eval(code, ctx$wd)
    }),
    name = "run_r_code",
    description = paste(
      "Run R code in the user's R session.",
      "Printed output, warnings and errors are returned."
    ),
    arguments = list(
      code = ellmer::type_string("The R code to run.")
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

  list(read_file, write_file, run_r_code, task_complete)
}

# Run the code here, in this R session, in its own environment so it doesn't
# clobber your globals. Like the console: prints visible values, and collects
# warnings, messages and errors as text.
handfish_eval <- function(code, wd = getwd()) {
  env <- new.env(parent = globalenv())
  old <- setwd(wd)
  on.exit(setwd(old), add = TRUE)

  error <- NULL
  output <- utils::capture.output({
    withCallingHandlers(
      tryCatch(
        for (expr in parse(text = code)) {
          value <- withVisible(eval(expr, envir = env))
          if (value$visible) print(value$value)
        },
        error = function(e) error <<- conditionMessage(e)
      ),
      warning = function(w) {
        cat("Warning:", conditionMessage(w), "\n")
        invokeRestart("muffleWarning")
      },
      message = function(m) {
        cat(conditionMessage(m))
        invokeRestart("muffleMessage")
      }
    )
  })

  text <- paste(output, collapse = "\n")
  if (!is.null(error)) text <- paste0(text, if (nzchar(text)) "\n", "Error: ", error)
  if (!nzchar(text)) text <- "(code ran, no output)"
  text
}

# ---------------------------------------------------------------------------
# The system prompt
# ---------------------------------------------------------------------------

handfish_prompt <- function(wd = getwd()) {
  prompt <- paste0(
    "You are Handfish, a small coding agent working in an R project.\n",
    "Working folder: ", wd, "\n\n",
    "Use the tools to do the task. Read files before you change them, and
check the results of your code.
Every tool call is shown to the user, who approves it before it runs. If a
call is declined, do not simply try it again: ask the user what they want
instead.
run_r_code runs in the user's R session. Save plots and outputs to files;
there is no screen.
Keep your replies short. When the task is done, call task_complete with a
short summary for the user."
  )

  agents_file <- file.path(wd, "AGENTS.md")
  if (file.exists(agents_file)) {
    agents <- paste(readLines(agents_file, warn = FALSE), collapse = "\n")
    prompt <- paste0(prompt, "\n\n# Project instructions (AGENTS.md)\n\n", agents)
  }

  prompt
}
