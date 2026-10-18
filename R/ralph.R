# ralph.R
# ---------------------------------------------------------------------------
# The Ralph Loop: run the same prompt again and again, each time with a
# fresh agent (a clean context). The agent's memory between loops is the
# files on disk, so we ask it to keep notes in a progress file.
#
# Each loop is a normal agent() run, with its own step and tool call limits.
# The Ralph loop stops when:
#   - the agent makes a file called RALPH_DONE (it's sure the job is done), or
#   - we hit max_loops, or
#   - the total cost goes over max_cost
# ---------------------------------------------------------------------------

ralph_instructions <- "

# Working in a loop
You are one run in a loop of agents working on this task. You have no
memory of earlier runs, except the files in the working folder.
1. Read {progress_file} first, if it exists, to see what has been done.
2. Do the next most important piece of work. Keep it small, and check it works.
3. Update {progress_file} with what you did and what is left to do.
4. Only if the WHOLE task is finished and checked, write a file called
   {done_file} (any content). Never make it otherwise.
5. Call task_complete."

#' Run an agent in a Ralph Loop
#'
#' @param prompt The task. The same prompt is given to every loop.
#' @param max_loops Most agent runs.
#' @param max_cost Stop once the total cost (in dollars) goes over this.
#'   Only works for models where ellmer knows the price.
#' @param progress_file The file agents use to pass notes to the next loop.
#' @param done_file The file the agent makes when the whole task is done.
#'   It is deleted before the first loop.
#' @param ... Passed on to [agent()], e.g. `chat`, `max_steps`, `max_tool_calls`.
#' @return Invisibly, a list of the results from each loop.
#' @export
ralph <- function(prompt,
                  max_loops = 10,
                  max_cost = Inf,
                  progress_file = "PROGRESS.md",
                  done_file = "RALPH_DONE",
                  ...) {
  instructions <- gsub("{progress_file}", progress_file, ralph_instructions, fixed = TRUE)
  instructions <- gsub("{done_file}", done_file, instructions, fixed = TRUE)
  full_prompt <- paste0(prompt, instructions)

  # The done file is in the project folder (wd, if given to agent())
  wd <- list(...)$wd %||% getwd()
  done_path <- file.path(wd, done_file)
  unlink(done_path)

  results <- list()
  total_cost <- 0

  for (loop in seq_len(max_loops)) {
    cat("\n")
    cli::cat_rule(
      left = paste("Ralph loop", loop, "of", max_loops),
      right = sprintf("total cost $%.4f", total_cost),
      line = 2, col = "magenta"
    )

    result <- agent(full_prompt, ...)
    results[[loop]] <- result
    if (!is.na(result$cost)) total_cost <- total_cost + result$cost

    if (file.exists(done_path)) {
      cli::cli_alert_success("Agent says the task is done after {loop} loop{?s}.")
      break
    }
    if (total_cost > max_cost) {
      cli::cli_alert_warning("Total cost ${round(total_cost, 4)} is over max_cost. Stopping.")
      break
    }
    if (loop == max_loops) {
      cli::cli_alert_warning("Reached max_loops ({max_loops}) without the task being done.")
    }
  }

  invisible(results)
}
