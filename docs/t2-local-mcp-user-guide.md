# TermiPad T2 local restricted MCP user guide

**Applies to:** TermiPad Mendocino T2; consolidated real macOS verification archive `20260826-212137`; document status: verified local configuration instructions.

> **Purpose and boundary.** T2 lets an MCP client on the same Mac query the running TermiPad for fixed tasks and project scopes, propose one fixed task for local review, read minimal status, or cancel a task that has not started. It is neither a terminal replacement nor a remote control service: there is no network address, HTTP, WebSocket, arbitrary shell, file browsing, passing in of paths/arguments/environment variables, PTY, or full terminal output.

## 1. Before you start: check whether this is the right way to use it

T2 is for a local MCP client already running on the **same Mac under the same logged-in user**. The client starts a restricted `stdio` child process of TermiPad; the child process only handles JSON-RPC and strict input validation, while the actual local data and policy operations are still handled by the open TermiPad main app through a local inter-process bridge.

| Requirement | Notes | Behavior when not met |
|---|---|---|
| A normally launched TermiPad main app | The main app installs the local bridge and holds the local task data. | MCP returns `local_bridge_unavailable`. |
| The user has turned local MCP on on the Mac | Turn on "Allow Local MCP Task Proposals" in the "Local Task Workbench". Off by default. | MCP returns `local_mcp_disabled`. |
| At least one project scope is selected | Every proposal must point to an existing, non-revoked, available local project scope. | The proposal returns `project_scope_unknown` or `project_scope_unavailable`. |
| A local MCP client that supports `stdio` | The client must be able to start a child process by absolute path and pass a fixed argument. | Cannot connect; do not switch to HTTP or a public port. |

This guide neither needs nor should involve creating a Manus custom MCP connector, entering a token, configuring a URL, or adding environment variables. MCP here is a local child-process protocol, not a cloud connector or a mobile device service.

## 2. Launch and prepare TermiPad first

Open TermiPad in **normal app mode** first, not with the `--termipad-mcp-stdio` argument. If you are building a debug version from the repository, you can use the fixed, separate build directory below; this step only builds and opens the local app, starts no network service, and grants MCP no execution permission.

```bash
cd ~/TermiPad
xcodegen generate
xcodebuild \
  -project TermiPad.xcodeproj \
  -scheme TermiPad \
  -destination 'platform=macOS' \
  -derivedDataPath "$PWD/.mcp-derived-data" \
  build
open "$PWD/.mcp-derived-data/Build/Products/Debug/TermiPad.app"
```

Then complete the following local steps in TermiPad's **Local Task Workbench**. The project folder path stays only on this Mac; an MCP client gets only the opaque scope ID, display name, and availability state, never the path.

1. Choose a project folder under "Project Scopes"; if a scope already exists, confirm it shows as available and not revoked.
2. Turn on the "Allow Local MCP Task Proposals" switch. The switch only allows restricted operations and does not treat the client, the port name, or `clientInfo` as identity credentials.
3. Keep the TermiPad main window or app process running. After the app is closed, the MCP child process has no local bridge to reach and cannot open or compete for the SwiftData database by itself.

If you later use a signed, distributed app, change `command` in the configuration below to that app's actual absolute executable path (usually `TermiPad.app/Contents/MacOS/TermiPad`). Do not configure the repository directory, a shell wrapper script, a `PATH` search, or dynamic arguments.

## 3. Register the service in the local MCP client

The configuration file location and top-level fields differ between MCP clients; use the client's official documentation to find the file. Whatever the host calls the server entry, TermiPad's key values are fixed: the **absolute executable path** plus the single argument `--termipad-mcp-stdio`.

Below is a **template** in the structure common to MCP client configurations. Replace `/Users/your-account-name` with the real absolute path on this Mac; do not add `env`, `url`, `headers`, a token, shell strings, or extra arguments.

```json
{
  "mcpServers": {
    "termipad-local": {
      "command": "/Users/your-account-name/TermiPad/.mcp-derived-data/Build/Products/Debug/TermiPad.app/Contents/MacOS/TermiPad",
      "args": ["--termipad-mcp-stdio"]
    }
  }
}
```

After the configuration is saved, the MCP client starts the child process. Under the MCP `stdio` rules the client writes UTF-8 JSON-RPC line by line to the child's standard input, and the server writes only valid MCP messages line by line to standard output; so any wrapper that prints extra debug text to stdout breaks the protocol.[1] TermiPad neither requires nor accepts a network URL or a secret.

> **Do not use `--termipad-mcp-stdio` in a shortcut that opens the app normally.** The argument puts the executable into headless stdio service mode; it needs to be started as a child process by an MCP client. The main app must stay running separately to provide the restricted local bridge.

## 4. Minimal verification order after connecting

The standard MCP lifecycle requires the client to send `initialize` first, then `notifications/initialized` after receiving the response, and only then enter regular tool calls.[2] Most mature MCP clients do this automatically; if the client shows an initialization error before the tool list appears, first check whether it requests and supports the `2025-03-26` or `2025-11-25` protocol version this service accepts exactly.

Verify in the following order, to avoid creating a task right at the start.

| Order | Action in the MCP client | Expected minimal result | What does not happen |
|---|---|---|---|
| 1 | Reload or connect `termipad-local`. | The client discovers the tool capability. | No network connection is opened and no project files are read. |
| 2 | Call `list_task_scopes`. | An opaque `scope_id`, display name, and `available` / `unavailable` / `revoked` state. | No project path is returned. |
| 3 | Call `list_fixed_tasks`. | Fixed task kinds, risk levels, and purposes. | No commands, arguments, executables, or working directories are returned. |
| 4 | Call `propose_task` only when really needed. | A new `task_id` in the awaiting-local-review state, possibly with an expiry time. | The task is neither approved nor run. |
| 5 | Go back to the TermiPad workbench on the Mac to review. | The user can see the proposal, open a local review window, and approve or cancel per local policy. | The MCP client cannot stand in for this step. |
| 6 | Call `get_task_status` only when progress needs confirming. | Minimal state, execution state, an optional exit code or rejection reason. | No stdout, stderr, file content, or project content is returned. |

TermiPad rejects ordinary tool operations until it receives `notifications/initialized`; it also limits each MCP service process to at most 30 ordinary requests per 60 seconds. The rate limit is a protection mechanism and should not be circumvented with retry loops, concurrent child processes, or multiple wrappers.

## 5. The five available tools

All tools use strict JSON Schema with `additionalProperties` set to `false`. In other words, unlisted fields are rejected before reaching the local bridge even if they look harmless. UUIDs must use the standard string form.

| Tool | Required input | What is returned | Key restriction |
|---|---|---|---|
| `list_task_scopes` | None | `scope_id`, `display_name`, `status`. | No paths or file information are returned. |
| `list_fixed_tasks` | None | `task_kind`, `risk`, `purpose`. | No commands, arguments, executables, or directories are returned. |
| `propose_task` | `scope_id`, `task_kind`. | A `task_id` awaiting review, risk, state, execution state, an optional expiry time. | Only fixed tasks can be proposed; `command`, `cwd`, `env`, or a URL cannot be smuggled in, and it cannot approve or run. |
| `get_task_status` | `task_id`. | Minimal task and execution state, an optional exit code, rejection reason, expiry time. | No terminal output or file content is returned. |
| `cancel_task` | `task_id`. | Minimal task state after cancellation. | Cannot terminate a running task; it must be stopped in the local workbench on the Mac. |

The correct input shape of `propose_task` has only the two fields in the example below:

```json
{
  "scope_id": "11111111-2222-3333-4444-555555555555",
  "task_kind": "swiftPackageTests"
}
```

The IDs in the example above are format samples only and cannot be reused. The real values must first be returned by `list_task_scopes` and `list_fixed_tasks`. Do not add fields such as `command`, `path`, `arguments`, `environment`, `url`, or natural-language instructions.

## 6. Review, execution, cancellation, and revocation

A task created by MCP can only be in the awaiting-review state. Real approval and starting are done only by the user in the TermiPad workbench on the Mac: first open a 15-minute local review window for the scope, then approve per local policy, and finally the user chooses whether to start the fixed task. Even when T1 starts a task, it uses only the fixed executable, fixed arguments, the selected project scope, and empty stdin/stdout/stderr; the full terminal output is neither stored nor returned.

| Your goal | The right way | What not to try |
|---|---|---|
| Pause new MCP operations | Turn off "Allow Local MCP Task Proposals" in the Local Task Workbench. | Do not try to use the client `clientInfo`, the port name, or a configured token as a revocation mechanism. |
| Stop the MCP child process | Disconnect or remove the server configuration in the MCP client. The client should close the child's stdin and wait for it to exit; terminate the process step by step if necessary.[2] | Do not let a background shell wrapper keep the service resident. |
| Revoke task permission for a project | In TermiPad's Local Task Workbench choose "Revoke Scope" for that project scope. | Do not pass substitute paths or new directories in MCP requests. |
| Cancel a proposal that has not run | Use `cancel_task(task_id)` or the cancel button in the local workbench. | Do not delete or tamper with the local database files. |
| Stop a running T1 task | Go back to the task card on the same Mac and click "Stop". | Do not call `cancel_task` repeatedly; it returns `task_running_local_stop_required`. |

Turning off the MCP switch makes later bridge requests get rejected; closing the main app makes the bridge unavailable. Neither is the same as force-terminating a process already running locally in T1, so a running task must still be handled with the workbench's "Stop" button.

## 7. Common errors and safe troubleshooting

| Symptom or error code | Likely cause | Safe way to handle it |
|---|---|---|
| `local_bridge_unavailable` | TermiPad is not running normally, the main app is in recovery mode, or the client is not in the same Mac / login context. | Open TermiPad normally, confirm the main data container is available, then reconnect. Do not switch to HTTP, a localhost port, or a shared network directory. |
| `local_mcp_disabled` | The local workbench switch is still off. | Turn it on manually only when you yourself need local collaboration; turn it off after use. |
| `invalid_arguments` | Extra fields, an invalid UUID, or a `task_kind` not in the fixed catalog. | Remove every unlisted field; get the IDs and enum values again from the listing tools. |
| `project_scope_unknown` | The `scope_id` does not exist. | Call `list_task_scopes` again; do not guess IDs or submit local paths. |
| `project_scope_unavailable` | The scope was revoked or its directory is temporarily unavailable. | Check the scope state in the Mac workbench; to restore it, the user chooses the project folder again. |
| `task_unknown` | The `task_id` does not exist or is no longer available. | Use only the ID returned by this proposal; do not scan local files looking for task information. |
| `task_running_local_stop_required` | The task is already running on this Mac. | Go back to the TermiPad workbench to stop it; MCP has no remote process termination capability. |
| `rate_limited` | A single service process exceeded 30 ordinary requests in one minute. | Wait, then make the necessary single call, and fix the client's polling strategy. |
| `Unsupported protocol version`, or operations rejected before initialization | The client did not request or does not support the `2025-03-26` / `2025-11-25` versions TermiPad accepts exactly, or did not send the initialization notification per the lifecycle. | Update to, or switch to, a local stdio MCP client that supports the accepted versions; do not loosen TermiPad's protocol validation by hand or add a compatibility network proxy. |

If the client UI asks for a server URL, API key, OAuth, browser authorization, or a remote endpoint, the connection type it chose is not the `stdio` child-process mode of this guide. Do not expose TermiPad as an HTTP service to accommodate that UI; choose a local client that supports command-style `stdio` MCP configuration.

## 8. Verified and unverified scope

T2 passed consolidated verification on the user's real Apple Silicon Mac with Xcode 26.6, Swift 6.3.3, and XcodeGen 2.46.0. The verification covers protocol and strict schema unit tests, Swift source security guards, the native macOS build, and UI smoke tests; the result directory is `20260826-212137`. This proves the local T2 scope in the current repository has passed regression verification in that environment; it does not mean any specific third-party MCP host has actually been connected or certified.

| Verified | Not yet implemented or not yet verified |
|---|---|
| Same-machine `stdio` JSON-RPC, the fixed protocol versions, the initialization order, and the five restricted tools. | The brand-specific configuration files or UI flows of any particular third-party MCP client. |
| The in-app off-by-default switch, the CFMessagePort local bridge, T0 local review, and T1 minimal execution results. | The iPhone companion, PWA, Telegram, remote network sessions, HTTP MCP, or public ports. |
| Forbidding network, XPC, arbitrary process launching, shell, PTY, terminal handoff, file browsing, and full output. | Developer ID, notarization, Gatekeeper cold start, iCloud/CloudKit, and external distribution. |

Before actually connecting an MCP client next, first confirm that the client supports a local stdio configuration of "command + args", and complete a read-only walkthrough of `tools/list`, `list_task_scopes`, and `list_fixed_tasks` without calling `propose_task`. Only after these steps behave as expected should proposing one low-risk fixed task, reviewable by the user on the Mac, be considered.

## 9. OpenCode: a compatible way to connect a local client

**Conclusion: OpenCode can serve as T2's MCP client.** OpenCode officially supports local MCP servers; it requires `type: "local"` inside the `mcp` object, with the executable and fixed arguments written as one `command` array.[4] OpenCode 1.14.33 has been confirmed in practice to initialize with `2025-11-25`; TermiPad accepts exactly that version and the original `2025-03-26`, and echoes the accepted client version in a successful handshake, in line with MCP's version negotiation rules.[6] This strictly matches TermiPad's single entry point of "absolute executable path + `--termipad-mcp-stdio`" and needs no URL, remote server, OAuth, headers, token, or environment variables.

OpenCode also has its own `bash`, file read/write, and network tools. **TermiPad's restricted MCP boundary does not automatically restrict these built-in OpenCode tools.** OpenCode allows most tools by default, so the permission configuration in this section explicitly denies OpenCode's shell and file modification abilities and makes the remaining operations require confirmation by default.[5] Do not use OpenCode's `--auto` mode; it automatically approves operations that are not explicitly denied.[5]

### 9.1 Minimal configuration file

Put this personal local configuration in `~/.config/opencode/opencode.jsonc` rather than committing it to any project's Git repository. OpenCode merges global and project configuration; when editing, only add or merge the `mcp` and `permission` fields below, and do not overwrite your existing provider or personal settings.[4]

Keep `enabled` at `false` initially. Change it to `true` temporarily only when TermiPad is running normally, a scope is ready, and you yourself are about to do the read-only walkthrough; change it back to `false` afterwards.

```jsonc
{
  "$schema": "https://opencode.ai/config.json",
  "mcp": {
    "termipad-local": {
      "type": "local",
      "command": [
        "/Users/your-account-name/TermiPad/.mcp-derived-data/Build/Products/Debug/TermiPad.app/Contents/MacOS/TermiPad",
        "--termipad-mcp-stdio"
      ],
      "enabled": false,
      "timeout": 6000
    }
  },
  "permission": {
    "*": "ask",
    "bash": "deny",
    "edit": "deny",
    "webfetch": "deny",
    "websearch": "deny",
    "task": "deny"
  }
}
```

Replace `/Users/your-account-name` in the example with the real account directory on the Mac, and confirm that the path points to the `TermiPad.app/Contents/MacOS/TermiPad` you built in section 2. **After every pull of new commits that touch MCP, you must re-run the targeted build command of section 2 to overwrite the binary in `.mcp-derived-data`; the verification artifacts of `./scripts/verify-macos.sh` do not replace that fixed path.** `command` must stay an array: do not change it to `zsh -c`, `bash -c`, string concatenation, or a wrapper script; and do not add `cwd`, `environment`, `url`, `headers`, OAuth fields, or any secret values. `timeout: 6000` only leaves OpenCode's tool discovery a little more time than the upper limit of TermiPad's local bridge requests and does not widen TermiPad's capabilities.

### 9.2 Read-only-first walkthrough

First open TermiPad normally, confirm in the "Local Task Workbench" that an available project scope exists, and turn on "Allow Local MCP Task Proposals". Then temporarily change `enabled` above to `true`, restart OpenCode, and run:

```bash
opencode mcp list
```

This command shows the configured MCP servers and their connection status.[4] If `termipad-local` is available, enter the following **read-only prompt** in an ordinary OpenCode conversation:

```text
Use only the termipad-local MCP tools and call list_task_scopes and list_fixed_tasks, in that order.
Do not call propose_task, get_task_status, or cancel_task; do not use bash, editing, files, network, sub-agents, or other tools.
Only summarize the returned display names, states, fixed task purposes, and risk levels; do not guess paths, commands, or arguments.
```

The expected result contains only opaque scope IDs, scope display names and states, and fixed task kinds, purposes, and risk levels. It should not show project paths, command bodies, arguments, environment variables, terminal output, or file content. After confirming that this read-only round behaves as expected, change `enabled` back to `false` and turn off "Allow Local MCP Task Proposals" in the TermiPad workbench.

### 9.3 Do not configure or use it like this

| Unsafe or incompatible practice | Reason | The right alternative |
|---|---|---|
| Writing the service as `type: "remote"` or entering a URL. | T2 has no HTTP / Streamable HTTP service and does not authenticate remote clients. | Use `type: "local"` with the local absolute path. |
| Entering a token, OAuth, headers, or `environment` for TermiPad. | T2 neither needs nor reads these values; extra secrets widen the exposure surface unnecessarily. | Write no secrets or environment variables in the configuration. |
| Starting the service with `zsh -c`, `bash -c`, `npx`, or a wrapper script. | Introduces extra shell parsing, PATH dependence, or the risk of polluting stdout. | The `command` array contains only the absolute path of the TermiPad executable and the single fixed argument. |
| Using `--auto` in OpenCode, or keeping the default permissive permissions. | OpenCode's other built-in tools may run shell, editing, or network actions independently; TermiPad MCP does not restrict this. | Use the `permission` configuration of this section and stay in confirmation mode. |
| Requesting `propose_task` in the very first walkthrough. | It is easy to skip observing the connection, scopes, and minimal returns. | First list scopes and fixed tasks read-only; confirm a low-risk proposal separately later. |

OpenCode's `opencode serve`, `opencode web`, `--hostname`, `--mdns`, and remote attach are separate OpenCode features and are not steps needed to enable TermiPad T2. They should not appear in this walkthrough, nor be treated as a way to expose TermiPad to the LAN or the public internet.

## References

[1]: https://modelcontextprotocol.io/specification/2025-03-26/basic/transports "Model Context Protocol: Transports (stdio)"
[2]: https://modelcontextprotocol.io/specification/2025-03-26/basic/lifecycle "Model Context Protocol: Lifecycle"
[3]: https://developer.apple.com/documentation/corefoundation/cfmessageport "Apple: CFMessagePort"
[4]: https://opencode.ai/docs/mcp-servers/ "OpenCode: MCP servers"
[5]: https://opencode.ai/docs/permissions/ "OpenCode: Permissions"
[6]: https://modelcontextprotocol.io/specification/2025-11-25/basic/lifecycle "Model Context Protocol: Lifecycle and version negotiation"
