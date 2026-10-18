make_ctx <- function(wd) {
  ctx <- new.env()
  ctx$wd <- normalizePath(wd)
  ctx$max_result_chars <- 5000
  ctx$timeout <- 10
  ctx$block_internet <- TRUE
  ctx$done <- FALSE
  ctx
}

call_tool <- function(tools, name, ...) {
  tool <- Filter(function(t) t@name == name, tools)[[1]]
  tool(...)
}

test_that("file tools read, write and edit", {
  wd <- withr::local_tempdir()
  tools <- turbochook:::make_default_tools(make_ctx(wd))

  call_tool(tools, "write_file", path = "sub/a.txt", content = "hello\nworld")
  expect_true(file.exists(file.path(wd, "sub/a.txt")))
  expect_match(call_tool(tools, "read_file", path = "sub/a.txt"), "2  world")
  expect_match(call_tool(tools, "read_file", path = "."), "sub/a.txt")

  call_tool(tools, "edit_file", path = "sub/a.txt", old_text = "world", new_text = "chook")
  expect_equal(readLines(file.path(wd, "sub/a.txt")), c("hello", "chook"))
  expect_error(call_tool(tools, "edit_file", path = "sub/a.txt", old_text = "nope", new_text = "x"), "not found")
})

test_that("paths outside the project are refused", {
  wd <- withr::local_tempdir()
  tools <- turbochook:::make_default_tools(make_ctx(wd))
  expect_error(call_tool(tools, "read_file", path = "../x"), "not allowed")
  expect_error(call_tool(tools, "read_file", path = "/etc/hosts"), "outside")
  expect_error(call_tool(tools, "write_file", path = "~/x.txt", content = "x"), "outside")
})

test_that("task_complete records the summary", {
  ctx <- make_ctx(withr::local_tempdir())
  tools <- turbochook:::make_default_tools(ctx)
  call_tool(tools, "task_complete", summary = "All done")
  expect_true(ctx$done)
  expect_equal(ctx$summary, "All done")
})

test_that("run_r_script runs a project script and refuses other paths", {
  wd <- withr::local_tempdir()
  writeLines("cat('hi from script')", file.path(wd, "s.R"))
  tools <- turbochook:::make_default_tools(make_ctx(wd))
  expect_match(call_tool(tools, "run_r_script", path = "s.R"), "hi from script")
  expect_error(call_tool(tools, "run_r_script", path = "nope.R"), "not found")
  expect_error(call_tool(tools, "run_r_script", path = "../s.R"), "not allowed")
})
