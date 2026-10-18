expect_flag <- function(reasons, pattern) {
  expect_true(any(grepl(pattern, reasons)), info = paste(reasons, collapse = "; "))
}

test_that("risky code is flagged", {
  expect_length(scan_code("x <- mean(1:10)\nplot(x)"), 0)
  expect_flag(scan_code("system('ls')"), "shell command")
  expect_flag(scan_code("unlink('data', recursive = TRUE)"), "deletes")
  expect_flag(scan_code("download.file('a', 'b')"), "internet")
  expect_flag(scan_code("con <- url('http://x.com')"), "internet")
  expect_flag(scan_code("eval(parse(text = paste0('sys', 'tem(\"ls\")')))"), "indirectly")
  expect_flag(scan_code("source('other.R')"), "another file")
  expect_flag(scan_code("writeLines('x', file.path(.libPaths()[1], 'a'))"), "R library")
})

test_that("ordinary names that contain risky words are not flagged", {
  expect_length(scan_code("budget(1); target(2); curl_count <- 1; readr::parse_number('1')"), 0)
})

test_that("guard_check scans code files but not plain text", {
  expect_length(guard_check("write_file", list(path = "notes.md", content = "see https://x.com")), 0)
  expect_gt(length(guard_check("write_file", list(path = "a.R", content = "system('ls')"))), 0)
  expect_gt(length(guard_check("write_file", list(path = ".Rprofile", content = "x <- 1"))), 0)
  expect_gt(length(guard_check("run_r_code", list(code = "file.remove('a')"))), 0)
})

test_that("source() of a project file is judged by the file's contents", {
  wd <- withr::local_tempdir()
  writeLines("add <- function(x, y) x + y", file.path(wd, "add.R"))
  writeLines("system('rm -rf /')", file.path(wd, "bad.R"))

  expect_flag(guard_check("run_r_code", list(code = "source('R/../add.R')"), wd), "another file")
  expect_length(guard_check("run_r_code", list(code = "source(\"add.R\")\nadd(1, 2)"), wd), 0)
  expect_flag(guard_check("run_r_code", list(code = "source('bad.R')"), wd), "shell command")
  expect_flag(guard_check("run_r_code", list(code = "f <- 'add.R'; source(f)"), wd), "another file")
  expect_flag(guard_check("run_r_code", list(code = "source('missing.R')"), wd), "another file")
})
