# M4 interactive session design — a native interaction layer (not terminal emulation)

**Status:** Design review draft (2026-09-17). Review first, then implement.

**Parent documents:** `docs/product-roadmap.md` §5 stages 5-6; `docs/m3-remote-allow-window-design.md` (the daily window — the session authorization base of this design).

**Clarification of the user's decision (2026-09-17):** "not necessarily a terminal UI" means **not being tied to the terminal form** (small, hard-to-read text and uncontrolled content), not skipping interaction — **interactive operation must be built, and built safe and friendly**. M2b/M3 executed that sentence too narrowly (only status receipts, no interaction); this design fills the gap.

## 1. Target experience (an interactive session aligned with zcode)

The task session page is upgraded from a "status panel" to a **session feed you can take part in**:

```
┌─ Task session on the phone ───────────────────┐
│ ▶ swift test        running · 1 min 12 s        │
│ ┌─────────────────────────────────────────┐  │
│ │ Live output stream (large type, auto-scroll, pausable) │  │
│ │ Test Suite 'ToolTests' started…          │  │
│ │ ✔ 12 tests passed                        │  │
│ │ ⚠ 1 test failed: testBackupRoundTrip     │  │
│ └─────────────────────────────────────────┘  │
│ [Stop]                                        │
│                                              │
│ 💬 The task needs your input:                  │
│ ┌─────────────────────────────────────────┐  │
│ │ Overwritten file build.lock detected. What now? │  │
│ │ [Skip] [Overwrite] [Abort task]             │  │
│ └─────────────────────────────────────────┘  │
└──────────────────────────────────────────────┘
```

- **Streamed output**: while a task runs, its output is pushed to the screen in real time (large type, native rendering, auto-scroll that can be paused) — replacing "a 32-line snippet after it ends"
- **Interaction points**: when a task needs a decision (a script asks via standard input / an interaction point of a fixed task definition), the phone shows a **structured choice card** — tap a button, do not type
- **Input**: when text input is really needed (e.g. a parameter), it goes through a controlled input field — still a structured field, not a free shell
- **Native large-type UI throughout** — never terminal emulation

## 2. Technical architecture

### 2.1 Streaming output push (the core protocol change)

Today it is "one connection, one request, one response" (connection lifetime = one request). M4 introduces a **subscription-style long-lived connection**:

```
Phone subscribes: openStream(taskIntentID) → the connection stays up
Mac pushes: outputChunk(streamId, text) × N     ← pushed whenever T1 stdout/stderr has new data
       : stateChange(streamId, newState)      ← pushed on every state transition
       : interactionRequest(streamId, prompt, options[])  ← the task needs input
Phone responds: interactionResponse(streamId, selection)
Phone unsubscribes: closeStream(streamId) → the connection closes
```

- Reuses the existing frame protocol (4-byte length prefix + AEAD envelope), adding the two operations `PairedDeviceOperation.openTaskStream` / `closeTaskStream` + the push message structures
- Output buffer: the Mac's T1 capture buffer is extended into a **stream source** (a cursor on top of the existing 32KB ring — after the phone reconnects it resumes from the cursor, with no repeats and no gaps)
- Backpressure: while the phone is offline, output only goes into the buffer (64KB cap, the oldest dropped beyond that) and is re-sent on reconnect
- **Red line unchanged**: output is still redacted by OutputRedactor before being sent; tool launches (terminal handoff) still have no stream

### 2.2 Where interaction points come from (the key to the security boundary)

**How does a task "ask"?** Three sources, all allowlisted:

1. **A fixed task definition declares interaction points** (preferred): `FixedTaskDefinition` gains optional `interactionPoints` — for example macOSVerification asks "continue / abort" when it detects an environment problem. The interaction options are **catalog literals**, not generated arbitrarily at runtime
2. **The generic pattern of a script asking via stdin**: the task definition declares "stdin interaction allowed", and the Mac turns question lines in the task's stdout that match a fixed pattern (a regex literal configured in the task definition) into interaction points, with options likewise given by task-definition literals
3. **Actions initiated from the phone**: stop (existing) / "rerun" could be added in a later phase — both are buttons, not typing

**Never available**: free-text input going straight to a shell, undeclared options generated at runtime, free conversation between tasks.

### 2.3 Binding to the daily window (the security base, reusing M3)

- **Precondition for stream subscription = RemoteAllowWindow.isOpen** — with the window closed, openStream is rejected outright (receipt "Today's remote window is not open")
- Lock screen → LockStateMonitor → close the window → **all active streams are disconnected immediately** (the Mac closes the streams)
- The output buffer is cleared when the window closes (in-memory state, the same discipline as the window)
- **Responses** to interaction points are likewise valid only inside the window

## 3. Phone-side design (CompanionApp)

- Task session page upgrade: tapping an entry opens the **session detail** (large-type output stream view + auto-scroll/pause + interaction cards + stop button)
- Stream connection management: open the stream on entering the detail page, close it on leaving, auto-reconnect after a drop + resume from the cursor
- Large-type output rendering: monospaced from 14pt, selectable font size, throttled refresh (frames merged every 200ms)
- The nothing-written-to-disk discipline is unchanged

## 4. Mac-side design

- `TaskOutputStreamService` (new file): stream registry (taskID → subscription state + cursor), T1 output hook (the existing capture pipe feeds the dispatch), push encoding
- `MobilePairingService`: long-lived connection mode (after openStream the connection is not dropped proactively and runs a push receive loop); the existing request/response path is kept (catalog / launch / status polling unchanged)
- The T1 stdout capture pipe already exists (M2b-2) — add a "per-line callback → dispatch" hook without touching execution semantics

## 5. Acceptance checklist (G8, real devices)

| # | Verification item | Pass criterion |
|---|---|---|
| 1 | Streamed output | The phone enters the detail page → output scrolls in real time (delay ≤ 1s) |
| 2 | Resume after a drop | Lock the phone for 10s and unlock → output continues from the breakpoint, with no repeats and no gaps |
| 3 | Interaction points | A task with interaction points runs → the phone shows a choice card → the selection takes effect |
| 4 | Window binding | openStream is rejected while the window is closed; lock screen → active streams are cut at once |
| 5 | Redaction | Build output containing a token → it is already redacted in the stream |
| 6 | Stop | The stop button works in the stream view (reusing the M2c chain) |
| 7 | Red lines | No free input goes straight to a shell; all interaction options come from task-definition literals; buffers are memory only; output is redacted; the protocol has no command/path fields |

## 6. Phase split

- **M4-1**: protocol increment (stream operations + push structures) + Mac-side stream service + T1 hook
- **M4-2**: phone-side session detail page (stream rendering + reconnect and resume)
- **M4-3**: interaction points (task definition declarations + choice card UI + response chain)
