test_that("system prompt includes AGENTS.md and a skills directory", {
  wd <- withr::local_tempdir()
  writeLines("Always use ggplot2.", file.path(wd, "AGENTS.md"))
  dir.create(file.path(wd, "skills", "plotting"), recursive = TRUE)
  writeLines(
    c("---", "name: plotting", "description: How to make nice plots", "---", "Use theme_bw()."),
    file.path(wd, "skills", "plotting", "SKILL.md")
  )
  writeLines("Tips for cleaning data", file.path(wd, "skills", "cleaning.md"))

  prompt <- turbochook:::build_system_prompt(wd)
  expect_match(prompt, "Always use ggplot2")
  expect_match(prompt, "plotting: How to make nice plots \\(read skills/plotting/SKILL.md\\)")
  expect_match(prompt, "cleaning: Tips for cleaning data")
  # Skill bodies are not loaded until needed
  expect_no_match(prompt, "theme_bw")
})

test_that("no AGENTS.md or skills is fine", {
  prompt <- turbochook:::build_system_prompt(withr::local_tempdir())
  expect_no_match(prompt, "Skills")
})
