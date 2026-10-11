# T2: protocol basis for local restricted MCP collaboration

**Status:** Research complete; the T2 same-machine `stdio` server is implemented and passed consolidated real macOS verification on 2026-08-26 (archive `20260826-212137`). No Manus custom MCP connector is configured yet; that choice fits T2's local, secret-free, network-free boundary.

## Current session and product boundary

The current Manus session has no usable custom MCP connector; the check found zero user-defined connectors. T2 does not create, enable, or modify connectors, nor does it let the current session access the user's Mac directly. TermiPad's first MCP version is designed only as a `stdio` server the user configures deliberately on the **same Mac**.

## Conclusions from the official protocol

| Protocol fact | What it means for the T2 design |
|---|---|
| MCP initialization must precede normal operation: the client sends `initialize`, then `notifications/initialized` on success. | The server rejects tool calls until initialization is complete; only the `tools` capability is negotiated. |
| `stdio` shutdown is the client closing the child's input and waiting for the process to exit; every request should have a timeout. | T2 uses line-based JSON-RPC stdio and exits when the client disconnects; it keeps no background or network session. |
| Tools must declare a JSON Schema; the server must validate input, enforce access control, rate-limit, and sanitize output. | All tools use `additionalProperties: false`; only UUIDs / fixed enums are accepted; results return only states and fixed descriptions. |
| MCP strongly recommends that sensitive calls stay rejectable by a human. | `propose_task` can only create the T0 review state and never approves or runs automatically; `cancel_task` only cancels local tasks. |
| The official Swift SDK is currently Tier 3. | The first version prefers a small, testable protocol subset and keeps unverified SDK behavior out of TermiPad's main execution chain. |

## Conclusions on the local bridge

As a child process of the MCP client, the `stdio` MCP server cannot reliably compete directly with the running SwiftUI app for the same SwiftData store. T2's bridge prefers a named `CFMessagePort` held by the app process: the stdio process only handles JSON-RPC and strict schemas, then asks the running app for restricted operations through the local port. Apple defines `CFMessagePort` as a communication channel that can transfer arbitrary data between threads or processes on the same machine; it is not HTTP, WebSocket, or a public listener.[5]

The local port name is not an authentication credential. TermiPad still keeps MCP off by default and turns it on explicitly inside the app; the `clientInfo` an MCP client submits is used only as compatibility information and never as proof of identity or authorization. The first version is only for local use by the same logged-in user; cross-user use, sandbox scenarios, remote connections, and privileged helpers are all outside T2.

| Process | Responsibility | Forbidden |
|---|---|---|
| MCP stdio executable | JSON-RPC lifecycle, schema validation, minimized protocol results | Opens no database, runs no tasks, uses no network, prints no non-protocol stdout. |
| In-app `CFMessagePort` | The single restricted bridge to the local models and T0/T1 policy | Not exposed to the network, accepts no commands/paths/variables, returns no full output. |
| TermiPad main app | User-visible local permission, task review, and policy management | Does not treat MCP client information as an authentication credential. |

## What T2 explicitly does not implement

- No `execute(command, cwd, env)`, terminal, PTY, file browsing, resource reads, prompt, sampling, or full output tools.
- No HTTP, Streamable HTTP, WebSocket, listening port, external network, token, or phone bridge.
- No stdio logs written to stdout; stdout may only carry JSON-RPC protocol messages.

## References

[1]: https://modelcontextprotocol.io/specification/2025-03-26/basic/lifecycle "Model Context Protocol: Lifecycle"
[2]: https://modelcontextprotocol.io/specification/2026-07-28/server/tools "Model Context Protocol: Tools"
[3]: https://modelcontextprotocol.io/docs/2026-07-28/develop/build-server "Model Context Protocol: Build an MCP server"
[4]: https://modelcontextprotocol.io/docs/2026-07-28/sdk "Model Context Protocol: SDKs"
[5]: https://developer.apple.com/documentation/corefoundation/cfmessageport "Apple: CFMessagePort"
