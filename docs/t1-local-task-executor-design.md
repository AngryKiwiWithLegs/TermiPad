# T1: local restricted task executor and workbench

**Status:** In the implementation batch; this phase only starts fixed tasks approved by T0 directly on the user's Mac. It connects to no network, MCP, phone, PWA, Telegram, remote input, or PTY.

## Goal

T1 turns a `TaskIntent` approved by T0 into a local process constrained to the project scope. What it solves is "running an already reviewed fixed test task on the Mac in a controlled way", not letting the user, an agent, or a future phone send arbitrary shell.

## The single execution path

```text
Fixed task catalog → T0 reviews and approves the TaskIntent → T1 pre-check
       → fixed executable + fixed arguments + project currentDirectoryURL
       → empty stdin/stdout/stderr → minimal status and exit code
```

The executor rejects every intent that is not `.approved`, already started intents, expired intents, revoked or unavailable project scopes, unknown task types, and missing pre-check files. It does not assemble `cd`, command text, or arguments through a shell; nor does it search `PATH` to decide the executable.

## Fixed task definitions

| Task | Fixed executable and arguments | Project pre-check | Time limit |
|---|---|---|---:|
| Swift Package tests | `/usr/bin/xcrun` + `swift test` | `Package.swift` | 120 seconds |
| Consolidated macOS verification | `scripts/verify-macos.sh` inside the project | `Package.swift`, `project.yml`, the script is executable | 300 seconds |
| XcodeGen project generation | `xcodegen` at a controlled absolute path + `generate` | `project.yml` | 60 seconds |

Catalog entries change only with app updates; T1 accepts no commands, arguments, paths, or URLs from AI, MCP, web pages, chat, project READMEs, or phone requests.

## Process and privacy boundary

The process's `currentDirectoryURL` is bound to the project root, and the environment keeps only a controlled `HOME`, locale settings, and a fixed `PATH`. Standard input, standard output, and standard error all point to the null device. T1 therefore offers no interactive prompts, PTY, terminal transcript, full log, or output return.

`TaskIntent` stores only the execution state, start/end time, and exit code; it stores no output content. The results the user can see in the workbench are only: not started, running, succeeded, failed, timed out, stopped, start rejected, or start failed.

## Stop and time limit

The workbench can send a stop request to the current direct task process; every fixed task also has a maximum time limit, after which the direct task process is likewise stopped. T1 currently does not promise to manage arbitrary child process trees, nor does it replace a full terminal or job system. Any future process group governance, sandbox permission model, or minimal diagnostic summary must be designed, tested, and reviewed in a separate phase.

## Limits that cannot be bypassed

| Unsupported capability | Reason |
|---|---|
| Free-form commands, arguments, environment variables, URLs, or paths | They would turn the task workbench into an arbitrary shell. |
| Interactive terminal, PTY, keyboard input, or terminal output | They would grow into a remote terminal capability and increase exposure of sensitive data. |
| Network, MCP, phone, or Telegram requests | These entries must be connected separately after the local execution boundary is stable. |
| Automatically saving a temporary task as an icon tool | Making a capability permanent must be confirmed separately by the user on the Mac. |
