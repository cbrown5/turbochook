test_that("with_retry retries rate limits and then succeeds", {
  tries <- 0
  flaky <- function() {
    tries <<- tries + 1
    if (tries < 3) stop("HTTP 429 Too Many Requests")
    "ok"
  }
  expect_equal(with_retry(flaky(), base_delay = 0.01), "ok")
  expect_equal(tries, 3)
})

test_that("with_retry passes other errors straight through", {
  tries <- 0
  broken <- function() {
    tries <<- tries + 1
    stop("bad API key")
  }
  expect_error(with_retry(broken(), base_delay = 0.01), "bad API key")
  expect_equal(tries, 1)
})

test_that("with_retry gives up after max_tries", {
  expect_error(with_retry(stop("rate limit exceeded"), max_tries = 2, base_delay = 0.01), "rate limit")
})
