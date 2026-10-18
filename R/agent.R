# agent.R
# ---------------------------------------------------------------------------
# The agent loop.
#
#   1. THINK   - send a message to the LLM, it replies with text and
#                optionally one or more tool calls
#   2. ACT     - run the tool(s) in R
#   3. OBSERVE - send the tools' results back to the LLM
#   ... repeat until the LLM calls task_complete
#
# ellmer does steps 1-3 for us when tools are registered: chat$chat() keeps
# going round until the LLM replies without a tool call. We watch each lap
# with two hooks:
#   on_tool_request - just before a tool runs: print it, check limits,
#                     run the guard
#   on_tool_result  - just after it runs: print the result, stop if the
#                     tool was task_complete
# To stop, a hook signals a "turbochook_stop" condition, which drops us out
# of chat$chat() and back into the loop below.
# ---------------------------------------------------------------------------

#' Run the agent on a task
#'
#' @param task What you want done, in plain words.
#' @param chat An ellmer chat object. Pick any provider and model, e.g.
#'   `ellmer::chat_openrouter(model = "qwen/qwen3.8-27b")`. A copy is used,
#'   so your object isn't changed.
#' @param tools A list of extra tools made with [ellmer::tool()].
#' @param vision `TRUE` to give the agent a `look_at_image` tool, or an
#'   ellmer chat object to use as the vision model.
#' @param max_steps Most LLM replies before stopping.
#' @param max_tool_calls Most tool calls before stopping.
#' @param guard Scan code for risky calls and ask before running it.
#' @param block_internet Point the sandbox's proxy settings at a dead address.
#' @param timeout Seconds before a `run_r_code` call is stopped.
#' @param max_result_chars Tool results longer than this are cut short.
#' @param max_retries Retries when the API is rate limited.
#' @param wd The project folder. The agent can only touch files in here.
#' @return Invisibly, a list with the summary, status, counts, cost and the
#'   chat (so you can carry on talking to it).
#' @export
agent <- function(task,
                  chat = ellmer::chat_anthropic(model = "claude-sonnet-5-5"),
                  tools = list(),
                  vision = FALSE,
                  max_steps = 30,
                  max_tool_calls = 60,
                  guard = TRUE,
                  block_internet = TRUE,
                  timeout = 60,
                  max_result_chars = 5000,
                  max_retries = 5,
                  wd = getwd()) {
  # ---- Set up -------------------------------------------------------------

  # Shared state for the tools
  ctx <- new.env()
  ctx$wd <- normalizePath(wd)
  ctx$block_internet <- block_internet
  ctx$timeout <- timeout
  ctx$max_result_chars <- max_result_chars
  ctx$done <- FALSE
  ctx$summary <- NULL
  ctx$extra_tokens <- 0 # used by the vision tool
  ctx$extra_cost <- 0

  ctx$session <- sandbox_start(ctx$wd, block_internet)
  on.exit(ctx$session$close(), add = TRUE)

  all_tools <- make_default_tools(ctx)
  if (isTRUE(vision)) vision <- vision_tool()
  if (inherits(vision, "Chat")) all_tools <- c(all_tools, list(make_vision_tool(ctx, vision)))
  all_tools <- c(all_tools, tools)

  chat <- chat$clone(deep = TRUE) # deep, so our hooks stay on our copy
  chat$set_system_prompt(build_system_prompt(ctx$wd))
  chat$set_tools(all_tools)

  # ---- Counters -----------------------------------------------------------

  steps <- 0 # LLM replies so far
  tool_calls <- 0 # tools we have actually run

  stats <- function() {
    tokens <- chat$get_tokens()
    list(
      steps = steps,
      tool_calls = tool_calls,
      tokens = sum(tokens$input, tokens$output, tokens$cached_input) + ctx$extra_tokens,
      cost = as.numeric(chat$get_cost()) + ctx$extra_cost
    )
  }

  # Called whenever we might be looking at a new LLM reply. If it is new,
  # print the step header and the LLM's text. Returns TRUE if over max_steps.
  replies_seen <- 0
  check_new_step <- function() {
    replies <- sum(vapply(chat$get_turns(), function(t) t@role == "assistant", logical(1)))
    if (replies > replies_seen) {
      replies_seen <<- replies
      steps <<- steps + 1
      show_step_header(steps, stats())
      show_agent_text(chat$last_turn()@text)
    }
    steps > max_steps
  }

  # ---- Hooks: ACT and OBSERVE ---------------------------------------------

  chat$on_tool_request(function(request) {
    if (check_new_step()) stop_agent("max_steps")
    # task_complete is always allowed, so the agent can sum up
    if (tool_calls >= max_tool_calls && request@name != "task_complete") {
      stop_agent("max_tool_calls")
    }

    show_tool_call(request@name, request@arguments)

    if (guard) {
      reasons <- guard_check(request@name, request@arguments, ctx$wd)
      if (length(reasons) > 0 && !guard_ask(request@name, reasons)) {
        ellmer::tool_reject(paste(
          "The user blocked this call because it looked risky:",
          paste(reasons, collapse = "; ")
        ))
      }
    }
    tool_calls <<- tool_calls + 1
  })

  chat$on_tool_result(function(result) {
    is_error <- !is.null(result@error)
    text <- if (is_error) error_text(result@error) else paste(result@value, collapse = "\n")
    is_error <- is_error || grepl("(^|\n)Error: ", text)
    show_tool_result(text, is_error)
    if (ctx$done) stop_agent("complete")
  })

  # ---- The loop: THINK ----------------------------------------------------

  cli::cli_h1("Turbo Chook")
  show_agent_text(task)

  message_to_llm <- task # the first message is the task itself
  attempt <- 0 # rate limit retries in a row

  repeat {
    replies_before <- replies_seen

    outcome <- withCallingHandlers(
      tryCatch(
        {
          chat$chat(message_to_llm, echo = "none")
          "replied"
        },
        turbochook_stop = function(cond) conditionMessage(cond),
        error = function(e) if (is_rate_limit(e)) e else stop(e)
      ),
      # ellmer warns about failed tool calls; we've already shown them
      ellmer_tool_failure = function(w) invokeRestart("muffleWarning")
    )

    # Rate limited: wait, then try again
    if (inherits(outcome, "error")) {
      attempt <- attempt + 1
      if (attempt > max_retries) stop(outcome)
      backoff_wait(attempt, max_retries)
      check_new_step()
      if (replies_seen > replies_before) {
        # We got partway, so the last tool results may be lost
        message_to_llm <- "(The API was rate limited and the last tool results may be lost. Check where you are up to, then carry on.)"
      }
      next
    }
    attempt <- 0

    # A hook stopped us: task complete, or a limit was hit
    if (outcome != "replied") {
      status <- outcome
      break
    }

    # The LLM replied with text only and no tool call. Show it and nudge.
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

# Signal a stop from inside a hook. It's a condition, not an error, so
# ellmer and the retry code don't treat it as a failure.
stop_agent <- function(status) {
  cond <- structure(
    class = c("turbochook_stop", "condition"),
    list(message = status, call = NULL)
  )
  stop(cond)
}

error_text <- function(error) {
  if (inherits(error, "condition")) conditionMessage(error) else paste(error, collapse = "\n")
}

`%||%` <- function(x, y) if (is.null(x)) y else x
