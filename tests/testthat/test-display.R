test_that("markdown formatting keeps the text", {
  withr::local_options(cli.num_colors = 1)
  out <- turbochook:::format_markdown("Some **bold** and `code`.\n```r\nx <- 1\n```\nDone.")
  expect_equal(out, c("Some bold and code.", "x <- 1", "", "Done."))
})

test_that("clip_lines cuts long output", {
  out <- turbochook:::clip_lines(paste(1:20, collapse = "\n"), 5)
  expect_match(out, "15 more lines")
})
