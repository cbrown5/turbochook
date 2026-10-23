# Handfish's tools, and the approval step in front of them.
# No API is called: the tools are pulled out and run directly.

handfish_ctx <- function(wd, approve = function(name, args) TRUE) {
  ctx <- new.env()
  ctx$wd <- normalizePath(wd)
  ctx$approve <- approve
  ctx$done <- FALSE
  ctx
}

call_tool <- function(tools, name, ...) {
  tool <- Filter(function(t) t@name == name, tools)[[1]]
  tool(...)
}

test_that("handfish has four tools", {
  wd <- withr::local_tempdir()
  tools <- turbochook:::make_handfish_tools(handfish_ctx(wd))
  expect_equal(
    vapply(tools, function(t) t@name, character(1)),
    c("read_file", "write_file", "run_r_code", "task_complete")
  )
})

test_that("approved file tools read and write", {
  wd <- withr::local_tempdir()
  tools <- turbochook:::make_handfish_tools(handfish_ctx(wd))

  call_tool(tools, "write_file", path = "sub/a.txt", content = "hello\nworld")
  expect_true(file.exists(file.path(wd, "sub/a.txt")))
  expect_equal(call_tool(tools, "read_file", path = "sub/a.txt"), "hello\nworld")
  expect_match(call_tool(tools, "read_file", path = "."), "sub/a.txt")
  expect_error(call_tool(tools, "read_file", path = "nope.txt"), "not found")
})

test_that("declining a call stops the tool and makes no change", {
  wd <- withr::local_tempdir()
  tools <- turbochook:::make_handfish_tools(handfish_ctx(wd, approve = function(name, args) FALSE))

  expect_error(
    call_tool(tools, "write_file", path = "a.txt", content = "hi"),
    "declined"
  )
  expect_false(file.exists(file.path(wd, "a.txt")))
})

test_that("approve sees the tool name and its arguments", {
  wd <- withr::local_tempdir()
  seen <- NULL
  approve <- function(name, args) {
    seen <<- list(name = name, args = args)
    TRUE
  }
  tools <- turbochook:::make_handfish_tools(handfish_ctx(wd, approve))

  call_tool(tools, "write_file", path = "a.txt", content = "hi")
  expect_equal(seen$name, "write_file")
  expect_equal(seen$args$path, "a.txt")
  expect_equal(seen$args$content, "hi")
})

test_that("task_complete needs no approval and sets the summary", {
  wd <- withr::local_tempdir()
  ctx <- handfish_ctx(wd, approve = function(name, args) stop("should not be asked"))
  tools <- turbochook:::make_handfish_tools(ctx)

  call_tool(tools, "task_complete", summary = "all done")
  expect_true(ctx$done)
  expect_equal(ctx$summary, "all done")
})

test_that("paths outside the project are refused", {
  wd <- withr::local_tempdir()
  tools <- turbochook:::make_handfish_tools(handfish_ctx(wd))
  expect_error(call_tool(tools, "read_file", path = "../secret.txt"), "not allowed")
})

test_that("run_r_code returns output, warnings and errors", {
  wd <- withr::local_tempdir()
  tools <- turbochook:::make_handfish_tools(handfish_ctx(wd))

  expect_match(call_tool(tools, "run_r_code", code = "print(1 + 1)"), "2")
  expect_match(call_tool(tools, "run_r_code", code = "warning('careful')"), "Warning: careful")
  expect_match(call_tool(tools, "run_r_code", code = "stop('boom')"), "Error: boom")
  expect_equal(call_tool(tools, "run_r_code", code = "x <- 1"), "(code ran, no output)")
})

test_that("run_r_code runs in the working folder and not in the global env", {
  wd <- withr::local_tempdir()
  tools <- turbochook:::make_handfish_tools(handfish_ctx(wd))

  call_tool(tools, "run_r_code", code = "writeLines('hi', 'made-here.txt')")
  expect_true(file.exists(file.path(wd, "made-here.txt")))

  call_tool(tools, "run_r_code", code = ".handfish_test_var <- 99")
  expect_false(exists(".handfish_test_var", envir = globalenv()))
})

test_that("the system prompt names the folder and picks up AGENTS.md", {
  wd <- withr::local_tempdir()
  prompt <- turbochook:::handfish_prompt(wd)
  expect_match(prompt, "Handfish", fixed = TRUE)
  expect_false(grepl("AGENTS.md", prompt, fixed = TRUE))

  writeLines("Always use base R.", file.path(wd, "AGENTS.md"))
  expect_match(turbochook:::handfish_prompt(wd), "Always use base R.", fixed = TRUE)
})

test_that("ask_approval refuses to run unattended", {
  expect_error(turbochook:::ask_approval("read_file", list(path = "a.txt")), "interactive")
})
