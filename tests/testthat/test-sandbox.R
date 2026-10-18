test_that("sandbox keeps state and reports output, warnings and errors", {
  wd <- withr::local_tempdir()
  session <- turbochook:::sandbox_start(wd)
  on.exit(session$close())

  expect_match(turbochook:::sandbox_run(session, "x <- 41\nx + 1"), "42")
  expect_match(turbochook:::sandbox_run(session, "x"), "41")
  expect_match(turbochook:::sandbox_run(session, "warning('careful')"), "Warning: careful")
  expect_match(turbochook:::sandbox_run(session, "stop('boom')"), "Error: boom")
  expect_match(turbochook:::sandbox_run(session, "y <- 1"), "no output")
  expect_equal(
    normalizePath(turbochook:::sandbox_run(session, "cat(getwd())")),
    normalizePath(wd)
  )
})

test_that("sandbox code runs in another process", {
  session <- turbochook:::sandbox_start(withr::local_tempdir())
  on.exit(session$close())
  pid <- turbochook:::sandbox_run(session, "cat(Sys.getpid())")
  expect_false(pid == as.character(Sys.getpid()))
})

test_that("sandbox times out long code", {
  session <- turbochook:::sandbox_start(withr::local_tempdir())
  on.exit(session$close())
  expect_match(turbochook:::sandbox_run(session, "Sys.sleep(10)", timeout = 1), "longer than")
  expect_match(turbochook:::sandbox_run(session, "1 + 1"), "2")
})

test_that("internet is blocked by default", {
  session <- turbochook:::sandbox_start(withr::local_tempdir())
  on.exit(session$close())
  out <- turbochook:::sandbox_run(
    session,
    "download.file('https://cran.r-project.org', tempfile(), quiet = TRUE, method = 'libcurl')",
    timeout = 20
  )
  expect_match(out, "Error")
})

test_that("scripts run in a fresh process in the project folder", {
  wd <- withr::local_tempdir()
  writeLines(c("x <- 41", "cat(x + 1, getwd(), sep = '\\n')"), file.path(wd, "ok.R"))
  writeLines(c("cat('before\\n')", "stop('boom')"), file.path(wd, "bad.R"))
  writeLines("Sys.sleep(10)", file.path(wd, "slow.R"))

  out <- turbochook:::sandbox_script(file.path(wd, "ok.R"), wd)
  expect_match(out, "42")
  expect_match(out, basename(wd), fixed = TRUE)

  out <- turbochook:::sandbox_script(file.path(wd, "bad.R"), wd)
  expect_match(out, "before")
  expect_match(out, "boom")
  expect_match(out, "exited with status")

  expect_match(turbochook:::sandbox_script(file.path(wd, "slow.R"), wd, timeout = 1), "longer than")
})
