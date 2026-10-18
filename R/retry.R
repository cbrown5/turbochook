# retry.R
# ---------------------------------------------------------------------------
# Retry an API call when we hit a rate limit, waiting longer each time
# (exponential backoff): 2s, 4s, 8s, 16s, ... plus a little random jitter.
# Any other error is passed straight through.
# ---------------------------------------------------------------------------

rate_limit_pattern <- "429|Too Many Requests|rate.?limit|throttl|overloaded|529"

is_rate_limit <- function(error) {
  grepl(rate_limit_pattern, conditionMessage(error), ignore.case = TRUE)
}

backoff_wait <- function(attempt, max_tries, base_delay = 2) {
  wait <- base_delay * 2^(attempt - 1) + stats::runif(1, 0, 1)
  cli::cli_alert_warning(
    "Rate limited (attempt {attempt}/{max_tries}). Waiting {round(wait, 1)}s..."
  )
  Sys.sleep(wait)
}

#' Run an expression, retrying on rate limit errors
#'
#' @param expr The expression to run, e.g. `chat$chat("hi")`.
#' @param max_tries Most attempts before giving up.
#' @param base_delay Seconds to wait after the first failure. Doubles each time.
#' @return The value of `expr`.
#' @export
with_retry <- function(expr, max_tries = 5, base_delay = 2) {
  expr <- substitute(expr)
  env <- parent.frame()
  for (attempt in seq_len(max_tries)) {
    result <- tryCatch(
      list(value = eval(expr, env)),
      error = function(e) {
        if (!is_rate_limit(e) || attempt == max_tries) stop(e)
        e
      }
    )
    if (!inherits(result, "error")) return(result$value)
    backoff_wait(attempt, max_tries, base_delay)
  }
}
