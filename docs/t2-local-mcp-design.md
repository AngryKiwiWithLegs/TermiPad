# T2: local restricted MCP collaboration design

**Status:** Implemented, and passed consolidated real macOS verification on 2026-08-26 (archive `20260826-212137`). User-facing configuration, usage, and troubleshooting are in `docs/t2-local-mcp-user-guide.md`.

## Product promise

T2 lets an MCP client on the same Mac, explicitly enabled by the user, query TermiPad's fixed tasks, propose a one-off local task, query minimal status, or cancel a task that has not started. It is not a general terminal service and does not let an agent approve or run tasks directly.

```text
MCP client
  └─ starts TermiPad --termipad-mcp-stdio
       └─ JSON-RPC stdio + schema validation
            └─ named CFMessagePort (local inter-process communication only)
                 └─ the already-running TermiPad main app
                      └─ T0/T1 project scope, review, execution, and cancellation policy
```

The stdio child process does not open the SwiftData store. The main app is the only process that reads/modifies local tools, scopes, review windows, and task state, so it never competes with the UI for the same store.

## Enabling and the identity boundary

Local MCP is off by default. The user must deliberately turn on "Allow Local MCP Task Proposals" in the "Local Task Workbench". The switch only permits stdio clients of the same logged-in user on this Mac to request restricted operations; the port name, the MCP `clientInfo`, and the text of tool calls are not identity credentials and cannot replace local review, project scopes, or authorization windows.

## Exposed tools

| Tool | Input | Minimal return | Explicitly cannot do |
|---|---|---|---|
| `list_task_scopes` | None | Opaque scope ID, display name, availability state | Does not return local paths. |
| `list_fixed_tasks` | None | Fixed task kind, risk level, purpose | Does not return commands, arguments, executables, or working directories. |
| `propose_task` | `scope_id`, `task_kind` | ID of the task awaiting review, state, expiry time | Does not approve, does not run, and carries no commands or variables. |
| `get_task_status` | `task_id` | Minimal task/execution state and an optional exit code | Does not return stdout, stderr, files, or project content. |
| `cancel_task` | `task_id` | Minimal state after cancellation | Does not terminate a running process; a running task must be stopped in the local workbench. |

Every JSON schema sets `additionalProperties: false`. The protocol layer rejects extra parameters, and the bridge layer validates the task kind and scope again. A task must still pass the T0 local review window and is run by T1's fixed definitions.

## Currently forbidden

T2 does not implement HTTP, Streamable HTTP, WebSocket, network listening, phone, PWA, Telegram, arbitrary shell, PTY, AppleScript, file browsing, resource reads, prompt/sampling, passing in commands/paths/variables, or keeping and returning full terminal output.

## Acceptance focus

The consolidated real macOS verification must cover SwiftPM, the Xcode build, unit tests, and UI smoke tests together. The static guards must prove: no SwiftData access in the stdio layer; the local bridge uses `CFMessagePort`; no network, XPC, processes, terminal handoff, PTY, or output pipes; tool schemas are strict and stdout carries only JSON-RPC.
