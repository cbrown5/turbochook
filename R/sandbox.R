# sandbox.R
# ---------------------------------------------------------------------------
# The agent's R code runs in a separate R process, made with callr.
#
# The session is persistent: objects made in one run_r_code call are still
# there in the next, just like typing into the console.
#
# This keeps the agent's code away from YOUR R session (your objects, your
# loaded packages, and the turbochook guard). It is NOT a security wall. The
# child process runs as you, so it can still touch your files. See README.md.
# ---------------------------------------------------------------------------

# Start a new sandbox session in the project folder.
#   block_internet = TRUE points the proxy settings at a dead address, so
#   download.file(), url(), curl and httr fail. A speed bump, not a wall.
sandbox_start <- function(wd = getwd(), block_internet = TRUE) {
  # user_profile = FALSE: don't run a .Rprofile. The sandbox gets the same
  # package library as your session.
  options <- callr::r_session_options(env = sandbox_env(block_internet), user_profile = FALSE)
  session <- callr::r_session$new(options = options, wait = TRUE)
  session$run(setwd, list(wd))
  session
}

# Environment variables for any R process the agent's code runs in.
sandbox_env <- function(block_internet = TRUE) {
  env <- callr::rcmd_safe_env()
  if (block_internet) {
    dead_proxy <- "http://127.0.0.1:9"
    env <- c(
      env,
      http_proxy = dead_proxy,
      https_proxy = dead_proxy,
      ftp_proxy = dead_proxy,
      HTTP_PROXY = dead_proxy,
      HTTPS_PROXY = dead_proxy,
      no_proxy = "",
      NO_PROXY = ""
    )
  }
  env
}

# Run a script file in a FRESH R process, like `Rscript script.R`, with the
# same settings as the sandbox. Nothing from the persistent session is
# visible to it, and nothing it makes is kept. Returns the text the LLM sees.
sandbox_script <- function(path, wd = getwd(), block_internet = TRUE, timeout = 60) {
  result <- tryCatch(
    callr::rscript(
      path,
      wd = wd,
      env = sandbox_env(block_internet),
      user_profile = FALSE,
      timeout = timeout,
      stderr = "2>&1",
      show = FALSE,
      fail_on_status = FALSE
    ),
    callr_timeout_error = function(e) NULL
  )
  # With fail_on_status = FALSE a timeout is reported, not raised
  if (is.null(result) || isTRUE(result$timeout)) {
    return(paste0("Error: script took longer than ", timeout, " seconds and was stopped."))
  }

  text <- trimws(result$stdout)
  if (result$status != 0) {
    text <- paste0(text, if (nzchar(text)) "\n", "Error: script exited with status ", result$status)
  }
  if (!nzchar(text)) {
    text <- "(script ran, no output)"
  }
  text
}

# This function is sent to the sandbox and runs THERE, not here.
# It runs the code like the console does: prints visible values, and
# collects warnings, messages and errors as text.
sandbox_eval <- function(code) {
  error <- NULL
  output <- utils::capture.output({
    withCallingHandlers(
      tryCatch(
        {
          exprs <- parse(text = code)
          for (expr in exprs) {
            value <- withVisible(eval(expr, envir = globalenv()))
            if (value$visible) print(value$value)
          }
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
  list(output = paste(output, collapse = "\n"), error = error)
}

# Run code in the sandbox and wait up to `timeout` seconds.
# Returns the text the LLM will see.
sandbox_run <- function(session, code, timeout = 60) {
  session$call(sandbox_eval, list(code = code))
  state <- session$poll_process(timeout * 1000)

  if (state == "timeout") {
    session$interrupt()
    session$poll_process(2000)
    session$read()
    return(paste0(
      "Error: code took longer than ", timeout, " seconds and was stopped."
    ))
  }

  reply <- session$read()

  # The session itself crashed (not just an R error inside it)
  if (!is.null(reply$error)) {
    return(paste("Error: the R session failed:", conditionMessage(reply$error)))
  }

  result <- reply$result
  text <- result$output
  if (!is.null(result$error)) {
    text <- paste0(text, if (nzchar(text)) "\n", "Error: ", result$error)
  }
  if (!nzchar(text)) {
    text <- "(code ran, no output)"
  }
  text
}
