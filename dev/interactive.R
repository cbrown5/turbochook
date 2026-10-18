# dev/interactive.R
# ---------------------------------------------------------------------------
# Scratch script for stepping through agent() by hand.
#
# devtools::load_all() puts every internal function (sandbox_start,
# make_default_tools, show_tool_call, ...) in reach, so you don't need :::.
#
# Run the blocks below with Cmd+Enter / Ctrl+Enter, one line at a time.
# ---------------------------------------------------------------------------

devtools::load_all(".")

# ---- 1. The arguments, as local variables -------------------------------
# agent()'s body refers to its arguments by name. Bind them in the global
# env first and the body then runs line by line, unchanged.

task <- "Make a file called hello.R that prints 'hi', then run it."
chat <- ellmer::chat_anthropic(model = "claude-sonnet-5-5")


# A throwaway folder, so the agent can't touch the package source
wd <- file.path(tempdir(), "agent-sandbox")
dir.create(wd, showWarnings = FALSE)

debugonce(agent)

agent(task)
