# Turbo Chook

A simple, transparent LLM coding agent written in R. Inspired by the Pi agent and the Ralph Loop.

CJ Brown, 2026-10-18

```r
turbochook::agent("Load data.csv, plot cover against distance and save it as plot.png")
```

## How it works

The agent runs a simple loop:

1. **THINK**: send a message to the LLM. It replies with text and, optionally, one or more tool calls.
2. **ACT**: run the tool(s) in R.
3. **OBSERVE**: send the tools' results back to the LLM.

... and repeat until the LLM calls `task_complete`.

API calls go through the `ellmer` package, so any provider and model ellmer supports will work.

## Features

- **Five default tools**: `read_file`, `write_file`, `edit_file`, `run_r_code` and `task_complete`. Add your own with `ellmer::tool()`.
- **Light system prompt.** It adds the project's `AGENTS.md` if there is one.
- **Skills, loaded only when needed.** Skills in a `skills/` folder are listed by name and description; the agent reads the full skill when the task needs it.
- **Optional vision tool.** The agent can ask a vision model about an image, e.g. to check a plot it made.
- **Sandbox instead of approval.** The agent's R code runs in a separate `callr::r_session()`, with a timeout and a soft internet block.
- **Danger guard.** Risky code (shell commands, deleting files, internet access, hidden `eval()` code, changes to the R library) is flagged before it runs, and you're asked y/n.
- **Clear terminal output** with `cli`:
  - a header rule for each step, with tokens, cost and tool calls so far
  - the agent's text wrapped, with bold and code in colour
  - R code syntax-highlighted
  - ✓/✗ results, cut short when long
  - a boxed final summary
- **Cost control**: step and tool call limits, and a retry with exponential backoff when the API is rate limited.
- **Ralph Loop**: `ralph()` runs fresh agents on the same prompt, again and again, until the job is done.

---

# Using Turbo Chook

## Install

```r
devtools::install("path/to/turbochook")
```

You need an API key for your provider, e.g. `ANTHROPIC_API_KEY` in `~/.Renviron`.

## Run the agent

```r
turbochook::agent("Load data.csv, plot cover against distance and save it as plot.png")
```

The agent works in the current folder (or `wd = "some/folder"`). It returns (invisibly) a list with the `summary`, `status`, `steps`, `tool_calls`, `tokens`, `cost` and the `chat`, so you can keep talking to it.

### Pick your provider and model

Pass any ellmer chat object. A copy is used, so your object isn't changed.

```r
agent("...", chat = ellmer::chat_anthropic(model = "claude-haiku-5-5"))
agent("...", chat = ellmer::chat_openrouter(model = "qwen/qwen3.8-27b"))
agent("...", chat = ellmer::chat_ollama(model = "llama3.3"))
```

### Limits (to manage costs)

```r
agent("...", max_steps = 30, max_tool_calls = 60, timeout = 60, max_result_chars = 5000)
```

- `max_steps`: most LLM replies.
- `max_tool_calls`: most tool calls (`task_complete` is always allowed, so the agent can sum up).
- `timeout`: seconds before a `run_r_code` call is stopped.
- `max_result_chars`: long tool results are cut short before going to the LLM.

### Add your own tools

Make them with `ellmer::tool()` and pass them in a list:

```r
count_rows <- ellmer::tool(
  function(path) nrow(read.csv(path)),
  name = "count_rows",
  description = "Count the rows in a csv file.",
  arguments = list(path = ellmer::type_string("Path to the csv file."))
)
agent("How many rows are in data.csv?", tools = list(count_rows))
```

Your tools run in your R session, not the sandbox, and the guard doesn't check them.

### Vision

```r
agent("Make a plot of the data, then check it looks right", vision = TRUE)
agent("...", vision = ellmer::chat_openai(model = "gpt-5"))  # any vision model
```

This adds a `look_at_image(path, question)` tool. It sends the image to a separate vision chat (Claude Sonnet 5.5 by default). Its tokens and cost are added to the totals.

### AGENTS.md and skills

- If the folder has an `AGENTS.md`, it is added to the system prompt.
- Skills go in `skills/<name>/SKILL.md` or `skills/<name>.md`. Only each skill's name, description (from a `description:` line in the YAML header, or the first line) and path go in the system prompt. The agent reads the full file with `read_file` when it needs it.

### What you see

Each step gets a header rule with the step number, tokens, cost so far and tool calls. The agent's text is wrapped, with **bold** and `code` in colour. Tool calls are shown with R code highlighted. Results get a ✓ or ✗ and are cut to 12 lines on screen. The final summary goes in a box.

Cost shows as `n/a` when ellmer doesn't know the price of the model (at the time of writing that includes the Claude 5.5 models in ellmer 0.4.2).

## Ralph Loop

```r
turbochook::ralph(
  "Write R functions for each analysis in plan.md, with tests.",
  max_loops = 10,
  max_cost = 2,                       # dollars, if ellmer knows the price
  chat = ellmer::chat_anthropic(model = "claude-haiku-5-5"),
  max_steps = 20                      # passed on to agent()
)
```

Each loop is a fresh `agent()` run (a clean context) with the same prompt. The agents pass notes to each other in `PROGRESS.md`. The loop stops when an agent writes a `RALPH_DONE` file (only allowed once the whole task is checked), or at `max_loops` / `max_cost`. The done signal is a file, not a word in the summary, because models write things like "not RALPH_DONE yet".

## Rate limits

Every API call is retried when the error looks like a rate limit (`429`, `Too Many Requests`, `rate limit`, `throttle`, plus Anthropic's `overloaded`/`529`). The waits are 2s, 4s, 8s, 16s, ... plus some random jitter, for up to `max_retries` (default 5) tries. If a rate limit hits partway through a step, the agent is told the last tool results may be lost and asked to check where it's up to. You can use `with_retry()` in your own code too.

---

# The sandbox: how safe is it?

Short answer: **callr gives isolation, not security.**

`callr::r_session()` starts a second R process. The agent's `run_r_code` calls run there, in a session that persists (objects stay between calls, like the console). That's good for:

- keeping your R session clean (the agent can't overwrite your objects or crash your session),
- timeouts (a runaway loop is stopped after `timeout` seconds),
- keeping the guard out of reach (see below).

But the child process runs **as you**, with all your permissions. So yes, to your questions:

| Can the agent's code... | With callr alone |
|---|---|
| delete files (`unlink()`, `file.remove()`)? | Yes. (`rm()` only removes R objects, which is harmless.) |
| run shell commands (`system()`, `system2()`, `Rscript`)? | Yes |
| hide code in `eval(parse(text = ...))`, `do.call()`, `get()`? | Yes |
| `source()` a script it just wrote? | Yes |
| use the internet (`url()`, `download.file()`, httr)? | Yes |

So Turbo Chook adds three layers on top.

### 1. The guard (a fast grep, then ask you)

Before `run_r_code`, `write_file` or `edit_file` runs, the code is scanned with a list of regexes (`R/guard.R`, try `turbochook::scan_code("...")`). It looks for:

- shell commands and other processes: `system`, `system2`, `shell`, `processx::`, `callr::`, `Rscript`
- deleting, moving or copying files: `unlink`, `file.remove`, `file.rename`, `fs::file_delete`, `rm -r`
- the internet: `url(`, `download.file`, sockets, `curl::`, `httr`, web addresses
- **indirect code**: `eval`, `parse`, `str2lang`, `do.call`, `match.fun`, `get`, `.Internal`, `.Call`, and decoding tricks like `base64`, `rawToChar`, `intToUtf8`. If the agent tries to hide a call, the hiding gets flagged.
- `source()` of anything other than a plain-string path to a project file. For `source("R/add.R")` the guard scans the contents of `R/add.R` instead of flagging it.
- changes to R itself: `install.packages`, `.libPaths`, `R_LIBS`, `system.file`, anything mentioning `turbochook`, `Sys.setenv`, `setwd`, `.Rprofile`, `.Renviron`
- paths that leave the project: `../`, `~/`, `normalizePath`

Files written with `write_file`/`edit_file` are scanned by path, and by content if they're code files (`.R`, `.Rmd`, `.qmd`, `.sh`, `.py`, ...), since a script can be sourced later.

If anything matches, the agent pauses, you see what was found and why, and you answer y/n. If you say no, the agent is told the call was blocked and why. **In a non-interactive session (e.g. `Rscript`, or a Ralph loop left running), risky calls are blocked automatically.** Turn the guard off with `guard = FALSE`.

**Why the agent can't edit the guard.** The guard runs in *your* R process, from the installed package already loaded in memory. The agent's code runs in a different process. Also:

- the file tools refuse any path outside the project folder, and any path inside `.libPaths()`. Those checks also run in your process.
- code that mentions the R library, `.libPaths`, `system.file` or `turbochook` is flagged.
- even if a file in the installed package was changed, the copy already loaded in your session isn't affected until you reload it.

### 2. Internet speed bump

The sandbox starts with `http_proxy`/`https_proxy` pointed at a dead address (`127.0.0.1:9`). `download.file()`, `url()`, curl, httr and httr2 all honour these, so downloads fail. Code that ignores proxies (raw sockets, or `system("curl --noproxy ...")`) gets past it, but those calls are flagged by the guard. Allow internet with `block_internet = FALSE`.

### 3. Path checks on file tools

`read_file`, `write_file` and `edit_file` only work inside the project folder. `..` is refused and symlinks are resolved.

### The honest limits

The guard is a tripwire, not a proof. A regex can't fully understand R: a determined model could still find a pattern we didn't list. It catches the common and the obvious, and makes hiding things noisy. For real isolation, run the agent where it can't hurt anything:

- **Docker**: run R in a container with only the project folder mounted (e.g. the `rocker/r-ver` image), with `--network none` if you don't need the internet.
- **A separate user account or VM** with no access to your files.
- **macOS `sandbox-exec`** or **Linux `bubblewrap`/`firejail`** to restrict file and network access for the whole R process.
- Keep the project under **git**, so any change the agent makes can be undone.

---

# How the code is laid out

| File | What it does |
|---|---|
| `R/agent.R` | `agent()`: setup, the hooks and the loop |
| `R/tools.R` | the five default tools, the vision tool, path checks |
| `R/sandbox.R` | starts the callr session and runs code in it |
| `R/guard.R` | the danger scan and the y/n prompt |
| `R/prompt.R` | system prompt, AGENTS.md, skills directory |
| `R/display.R` | everything printed to the screen |
| `R/retry.R` | rate limit retries with backoff |
| `R/ralph.R` | the Ralph Loop |

**How the loop works.** ellmer already runs THINK → ACT → OBSERVE once tools are registered: `chat$chat()` keeps going round until the LLM replies without a tool call. Rather than rebuild that, `agent()` hooks in with `chat$on_tool_request()` (print the call, check limits, run the guard) and `chat$on_tool_result()` (print the result, stop if it was `task_complete`). To stop, a hook signals a `turbochook_stop` condition, which drops out of `chat$chat()`. If the LLM replies with text and no tool call, the outer `repeat` loop shows the text and nudges it to carry on, until it calls `task_complete` or hits a limit.

Run the tests with `devtools::test()`. They don't call any API.
