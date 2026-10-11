# TermiPad instant testing from the phone and agent collaboration: architecture comparison and development opinion

**Status:** Follow-up development opinion; implementing an MCP service, a PTY, remote input, network bridging, a real Bot token, or arbitrary terminal execution is not yet authorized.

## 1. The decision problem

The real scenario this comparison addresses: **the user is out with only a phone; the agent gives a new test or fix command in the conversation; the user cannot copy that command into the terminal of the Mac at home or in the office.** What the user needs is for the Mac to run it on their behalf and for the agent to keep collaborating based on the result — not to watch or operate a shrunken black terminal by hand on the phone.

This is related to "tapping a saved icon on the phone" but not the same. The former needs to run temporary, conversation-driven work; the latter only needs to request an approved fixed workflow. The architecture should therefore cover both kinds of tasks rather than forcing every operation through one channel.

> **Product goal:** the user can ask the agent for a test task on the phone; TermiPad runs it locally on the Mac in a clear, restricted, revocable way; the result returns to the authorized session in the minimal necessary form.

## 2. Candidates

| No. | Candidate | Can it run new commands? | Can it cover phone icons? | Core problem |
|---|---|---:|---:|---|
| A | Phone icons directly trigger a fixed `LaunchIntent` | No | Yes | Cannot run a new command just generated in the conversation. |
| B | The agent runs arbitrary shell through a direct terminal MCP | Yes | No, a UI is needed separately | Permission, output, and prompt injection risks approach those of a full remote terminal. |
| C | TermiPad MCP only invokes approved tool IDs | Partly | Yes | Reliable and safe, but cannot cover temporary commands. |
| D | TermiPad **restricted temporary task session** | Yes | Yes, the same entry can be reused | Needs new engineering such as project scope, permission leases, timeouts, and result sanitization. |
| E | A full remote PTY terminal on the phone | Yes | Icons are possible but unnecessary | Turns the product into a remote shell, with the highest attack surface and maintenance cost. |

### A. Fixed icon `LaunchIntent`

The phone sends only a short-lived, opaque tool request. The Mac rechecks identity, per-tool authorization, nonce, expiry, revocation, tool health, and terminal target, then runs the locally saved command.

It should be kept; it suits high-frequency, stable, variable-free flows such as "run TermiPad verification", "deploy a preview", or "sync the project", but it cannot solve the temporary command pain point of this decision.

### B. Direct terminal MCP

The agent calls `execute(command, cwd, env, timeout)`, reads the full output, changes files, and runs again. It suits complex development, debugging, and exploration while sitting at the Mac best; but once used remotely from the phone, the agent, conversation data, tool output, and remote bridge together form a high-privilege execution chain.

Local MCP's `stdio` transport has the client start the server as a child process; it suits local development integration and does not inherently solve the remote connection from phone to Mac.[1] If changed to HTTP, the MCP specification requires validating `Origin` and recommends that local servers bind only to `localhost` and implement authentication, to guard against risks such as DNS rebinding.[1] A direct terminal MCP could become an advanced local development mode in the future, but it should not be the default execution surface of the phone app.

### C. TermiPad restricted MCP

TermiPad exposes restricted tools such as `list_approved_tools`, `describe_tool`, `request_launch`, and `get_request_status`. The agent hands TermiPad only an approved `toolID`; TermiPad itself holds the command content and runs it by the existing Terminal/iTerm/Warp handoff rules.

It offers clear auditing, per-item authorization, source and health state, an icon catalog the user can see, and revocability, making it a reliable capability library shared by the phone and agents; but it cannot replace temporary tests.

### D. TermiPad restricted temporary task session

This is the recommended new capability. It is not an ordinary new shell and not a remote PTY, but a **one-off task runner**. The agent submits a reviewable task proposal; TermiPad creates a time-limited session on the Mac, constrained to the project scope, and runs that one test command.

Every task must include: the target project root, the full command, a purpose category, estimated permissions, network needs, maximum run time, and the result return level. The user can open a short "remote test window" on the Mac in advance, or require local confirmation by risk level. When the task ends, times out, is revoked, the Mac is locked, the app quits, or the session becomes invalid, TermiPad stops the session and safely rejects later requests.

It solves the practical problem of "a new command cannot be copied", while putting one-off commands into a reviewable, expiring, traceable model from the start. A task does not automatically become an icon tool; only when the user later confirms it is stable and wants to reuse it is it promoted to a fixed tool by an explicit action on the Mac.

### E. Full remote PTY

A full PTY lets the phone send arbitrary keystrokes, view continuous stdout/stderr, handle interactive prompts, and browse terminal state. It has the highest coverage, but it is not needed to solve this scenario and is in substance a remote shell product: it has to deal with session hijacking, screen/output leakage, interactive password prompts, command history, persistent connections, file paths, paste risks, and long-term authorization.

So a full remote PTY is not recommended for TermiPad's product scope. A user who truly needs a full remote desktop should use separate Screen Sharing, SSH, or enterprise-managed remote development tools rather than have TermiPad reimplement them.

## 3. Comparison criteria and conclusions

The scores are architectural judgments and do not represent external market data. Scenario coverage is weighted 30%, security and control 25%, engineering feasibility 15%, ongoing operations burden 10%, and consistency with the TermiPad product 20%. 5 is best.

| Option | Scenario coverage 30% | Security and control 25% | Engineering feasibility 15% | Operations burden 10% | Product consistency 20% | Weighted judgment | Conclusion |
|---|---:|---:|---:|---:|---:|---:|---|
| A Fixed icons | 2 | 5 | 5 | 4 | 5 | 4.00 | Must be kept, but not enough to solve temporary tests. |
| B Direct terminal MCP | 5 | 2 | 4 | 3 | 2 | 3.35 | Suits advanced local development, not the default phone path. |
| C Restricted TermiPad MCP | 3 | 5 | 4 | 4 | 5 | 4.10 | The right agent interface for fixed workflows. |
| **D Temporary task session** | **5** | **4** | **3** | **3** | **5** | **4.15** | **Recommended: the formal new capability that solves the core pain point.** |
| E Full remote PTY | 5 | 1 | 2 | 1 | 1 | 2.40 | Not in the product scope. |

## 4. Recommended architecture: two planes, one local policy core

The recommendation is not to pick a single one of A, C, or D, but to build one TermiPad local policy core and offer two execution planes on top of it.

```text
Agent conversation on the phone / PWA / Telegram Mini App
                    │
         ┌──────────┴──────────┐
         │                     │
Fixed tool request         Temporary test task proposal
`toolID`                 project, full command, time limit, purpose
         │                     │
         └──────────┬──────────┘
                    ▼
        TermiPad local policy core (Mac)
  identity binding · allow window · approval · project scope · risk tiers
  nonce · expiry · rate limiting · stop · revocation · audit
                    │
         ┌──────────┴──────────┐
         ▼                     ▼
Existing terminal handoff   One-off restricted task session
Terminal/iTerm/Warp    non-interactive, timeout, minimal result
```

The phone entry is only the **transport and presentation layer**, not the execution authority. A PWA and a Telegram Mini App can both serve as icon panels later; they must not hold commands, paths, secrets, or the Mac's inbound network address. The Mac should keep to outbound connections and never open a public listening port. A Telegram Mini App must use HTTPS, and the server must validate the client's `initData`; a Telegram Bot's long polling and webhook are mutually exclusive, so outbound long polling can be chosen instead of a webhook.[2] [3]

## 5. An explicit specification of the "clean terminal"

The first version cannot promise that "any command is perfectly sandboxed by macOS". App Sandbox can restrict file, network, and other access at the kernel level, but an app must declare its permissions explicitly; and arbitrary development toolchains often need the project directory, derived data, compilers, caches, the network, or signing resources.[4] So "clean" should be a progressive product guarantee:

| Layer | Must-have in the first version | Possible later enhancement | Cannot be promised |
|---|---|---|---|
| Lifecycle | A unique ID per session, time limit, cancellation, and terminating the child process group after timeout | Crash recovery and a task queue | A permanent background shell. |
| Project boundary | The user chooses the project root on the Mac; the task uses that directory as its working directory | Security-scoped bookmarks, per-project policy | Arbitrary access to the whole disk. |
| Environment | Use minimal environment variables; do not return environment values | Allowlisted PATH, temporary HOME, dedicated cache directory | Inheriting every login session and secret. |
| Network | By default show the network needs explicitly on the task card | Disable networking by default for low-risk tests, or authorize per project | Letting a task access arbitrary networks implicitly. |
| Input and output | No interactive PTY; input is only fixed commands approved by policy; results are returned at the minimal level | Rule-based log redaction and structured test results | Automatically sending the full terminal record to the phone / chat service. |
| Promotion | A temporary task must not automatically become a fixed tool | "Save as tool" after the user confirms on the Mac | An agent silently creating long-lived high-privilege tools. |

## 6. Follow-up development opinion

### Schedule now: T0, the local task policy core

After completing and confirming the real macOS verification of the current local icon system, the next batch of code should implement `TaskIntent` and the task state machine, rather than connecting Telegram, a PWA, MCP, or the iPhone right away.

T0 needs to cover: the task proposal model, risk categories, project scope references, full command review, the short allow window, signature/nonce/expiry, stop and revocation, process tree management, the minimal result enum, and unit tests ensuring "fixed tools" and "temporary tasks" are never confused. This phase has no network and starts no hidden or permanent shell.

### Schedule next: T1, the local temporary test task UI

Let the user view the task card on the Mac: command, project, network needs, time limit, risk, start, cancel, stop, save as a fixed tool. At first only support one-off tests the user starts from TermiPad, to validate the lifecycle and UI; submissions from agents or the phone are still not accepted.

### Conditional: T2, local stdio TermiPad MCP

Once T0/T1 are mature, provide a `stdio` MCP server so local MCP clients can propose temporary tasks or invoke fixed tools. In `stdio` mode the client starts a local child process, which suits validating agent collaboration first without creating a network service.[1] Every call still passes through the T0 policy core; no arbitrary `execute(command)` tool may be exposed.

### Conditional: T3, read-only catalog and fixed tool entry on the phone

Use the same-network native companion to first connect the phone's icon catalog, the Mac's online state, and fixed tool requests. Apple's local network and Bonjour capabilities are constrained by authorization and `Info.plist` declarations and should be verified on a real iPhone/Mac.[5]

### Long-term, requiring separate authorization: T4, remote task submission from the phone

Only after T0–T3 are validated by real use, choose a PWA or a Telegram Mini App. This phase lets the phone **submit task proposals** to an authorized session, but does not give the phone a PTY; the Mac fetches requests over an outbound connection, and T0 remains responsible for approval, execution, and returning the minimal result.

## 7. Out of scope for now

On this roadmap the following capabilities explicitly do not enter TermiPad: a Mac terminal listening on the public internet, a full remote PTY, arbitrary keyboard input, remote file browsing, automatic upload of full stdout/stderr, an arbitrary-command MCP, remote install/upgrade/uninstall, agents silently widening permissions, and agents automatically turning temporary commands into long-lived tools.

This is not dodging the user's pain point. T0–T4 already deliver starting a temporary test remotely from the phone, running it safely on the Mac, returning the result, and continuing to collaborate with the agent; what is excluded are capabilities that solving this problem does not need but that would turn the product into a remote shell.

## 8. Final opinion

**Adopt the two-plane plan of "TermiPad restricted temporary task session + fixed icon tool library".** It is the only plan that covers both real scenarios — "a new command cannot be copied on the phone" and "tapping a fixed icon on the phone" — without exposing the Mac as a permanent remote terminal.

A direct terminal MCP may exist in the future as a clearly isolated, local-only, per-use-approved advanced development mode, but it is not the foundation of the phone roadmap. The Telegram Mini App, PWA, and native iPhone Companion are later entry choices and cannot be developed ahead of the T0 task policy core.

## References

[1]: https://modelcontextprotocol.io/specification/2025-03-26/basic/transports "Model Context Protocol: Transports"
[2]: https://core.telegram.org/bots/webapps "Telegram: Mini Apps"
[3]: https://core.telegram.org/bots/api#getupdates "Telegram Bot API: getUpdates"
[4]: https://developer.apple.com/documentation/xcode/configuring-the-macos-app-sandbox "Apple: Configuring the macOS App Sandbox"
[5]: https://developer.apple.com/documentation/technotes/tn3179-understanding-local-network-privacy "Apple: TN3179 Understanding Local Network Privacy"
