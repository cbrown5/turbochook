# dev/interactive.R
# ---------------------------------------------------------------------------
# Scratch script for stepping through turbochook() by hand.
#
# devtools::load_all() puts every internal function (sandbox_start,
# make_default_tools, show_tool_call, ...) in reach, so you don't need :::.
#
# Run the blocks below with Cmd+Enter / Ctrl+Enter, one line at a time.
# ---------------------------------------------------------------------------

devtools::load_all(".")

# ---- 1. The arguments, as local variables -------------------------------
# turbochook()'s body refers to its arguments by name. Bind them in the global
# env first and the body then runs line by line, unchanged.

task <- "Make a file called hello.R that prints 'hi', then run it."
chat <- ellmer::chat_anthropic(model = "claude-sonnet-5-5")


# A throwaway folder, so the agent can't touch the package source
wd <- file.path(tempdir(), "agent-sandbox")
dir.create(wd, showWarnings = FALSE)

debugonce(turbochook)

turbochook(task)


# ---- 2. Handfish: the smaller agent -------------------------------------
# Same loop, four tools, and it asks before every call. Runs in THIS R
# session, so watch what you approve.

handfish("Make a file called hello.R that prints 'hi', then run it.", wd = wd)

# To step through it without answering prompts, approve everything:
handfish("...", wd = wd, approve = function(name, args) TRUE)
