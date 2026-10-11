# TermiPad Telegram Companion Security Design

**Status:** Feasibility and restricted pilot design complete; code implementation not started.

## 1. Conclusion

A Telegram Bot **can** become TermiPad's phone entry, but only as a restricted remote-control surface relayed through a third-party cloud, not as a terminal interface. It is more convenient than same-network local pairing: requests can be made when you are away and the phone is not on the same LAN as the Mac; but it also introduces new trust boundaries such as the Telegram cloud, a Bot token, a continuously running Mac connection, a Telegram account allowlist, and message metadata.

The recommendation is therefore to define Telegram as a **“Telegram Companion Preview”** rather than a default product capability. The first pilot allows only one or more explicitly bound private Telegram accounts to tap fixed buttons provided by the Bot in a private chat. A button represents only a tool UUID this Mac has already allowed, and the Mac remains the final policy enforcer. Bot text, user messages, command arguments, files, images, voice, links, forwarded content, and free-form input never enter the launch flow.

> Telegram is not an end-to-end TermiPad control channel. Any information sent to the Bot passes through Telegram's service; so commands, variables, paths, working directories, API keys, terminal output, and backup data must never be carried in Bot messages, button payloads, or replies.

## 2. Transport Choice: Long Polling Only, No Public Webhook

The Telegram Bot API has two mutually exclusive ways to receive updates: `getUpdates` long polling or a Webhook.[1] For the TermiPad pilot, **long polling** should be chosen: the running Mac app connects out to Telegram over HTTPS to fetch updates, exposing no public listening port, domain, or reverse proxy.

A Webhook is not suitable for the first pilot. A Webhook requires Telegram to push updates to an HTTPS URL, and the official documentation also states that it needs a valid TLS certificate, a supported port, and correct domain configuration.[2] That would force TermiPad or the user to maintain a public entry point, enlarging the surface for scanning, forged requests, operational mistakes, and service exposure. Even though the API supports validating a `secret_token` request header, it should not be treated as the preferred architecture for remote terminal control.[1]

Long polling also has a clear cost: TermiPad must keep running on the Mac (it can be a persistent menu bar app), and the Mac must have a network connection. If the app quits, or the Mac sleeps, goes offline, or logs out, the Bot should show only a fixed “Mac offline” and must not queue up terminal requests for delayed execution. Telegram officially notes that updates are kept on the server for at most 24 hours; this product must not treat that window as a delayed-execution queue.[1]

## 3. First-Release Interaction: Private Chat, Fixed Keyboard, Fixed Actions

The Bot supports only Telegram private chats and rejects groups, channels, inline mode, deep links carrying actions, files/media, text commands, and voice input. Telegram's Bot features allow an inline keyboard; pressing such a button does not send a normal chat message but produces a callback interaction.[3] That suits showing a list of tool buttons published by the Mac, but the button data must be a short-lived, single-use, unguessable opaque action token, not a tool name, command, or argument.

Every Bot update must pass the following checks; if any step fails, only a fixed rejection status is returned:

1. The session the Bot token belongs to has been explicitly enabled by the Mac user, and the token is stored only in the Mac Keychain.
2. The update comes from a private chat and `from.id` matches the Mac's local allowlist; identity is not judged by Telegram nickname, username, or chat title.
3. The update type can only be the expected callback; all text messages, edited messages, files, images, links, and unknown update types are ignored outright.
4. The callback action token must exist in the short-lived action table in the Mac's memory, bound to the allowed Telegram user, tool UUID, policy version, message ID, nonce, and expiry time.
5. A token is invalidated after one use; the Mac keeps recent callback IDs/nonces to reject replays and rate-limits repeated requests.
6. The Mac re-reads the tool by its local tool UUID and rechecks health status, remote authorization, the no-variables restriction, and target terminal availability; it never trusts any business field in the button data.
7. Terminal handoff still goes through `TerminalLauncher`; if automation permission is denied, it reports only “needs local handling on the Mac/copied safely” and returns no command or terminal output to Telegram.

Telegram also explicitly reminds developers that the backend must itself verify whether a received command is valid and whether the sender is authorized, and cannot rely on the Bot's command scope alone.[3]

## 4. Permission Model and Fixed Statuses

| Mode | Default | What Telegram can do | Mandatory protection on the Mac |
|---|---|---|---|
| Status view | Off by default; available once the user enables it | View minimized online status, authorized tool icons, and fixed statuses | Shows no commands, paths, variables, or terminal output |
| Request launch | Optional by default | Tap one authorized tool button | The Mac shows a local confirmation; no terminal handoff without confirmation |
| Short remote launch window | Off by default | Launch individually authorized tools without variables | Time limit, device/account allowlist, health check, nonce, rate limiting, immediate revocation |

Bot replies may use only fixed status categories: `Mac offline`, `waiting for Mac confirmation`, `request rejected by policy`, `tool unavailable`, `handed to the selected terminal`, `copied, needs handling on the Mac`. Commands, variables, working directories, paths, versions, stdout/stderr, exit codes, and error stacks must not be returned.

Controlled install plans, environment reports, tool editing, the Review Inbox, scanning, backup restore, settings changes, and icon upload are all permanently disabled in the Telegram pilot. They involve the supply chain, privacy, or local data changes and must stay in the Mac's local UI.

## 5. Secrets, Privacy, and Revocation

A Bot token is the authentication credential for the Bot API; Telegram's documentation states that every Bot has a unique authentication token and that all Bot API requests carry that token as part of the URL.[1] The token is therefore stored only in the Mac Keychain and is not written to `UserDefaults`, SwiftData, JSON backups, diagnostic bundles, logs, screenshots, UI copy, or the Git repository. On the Mac the user should be able to turn off the Bot with one click, clear the token, revoke a single Telegram user, revoke all users, and invalidate all short-lived action tokens immediately.

TermiPad's local diagnostics record only fixed count categories: Bot enabled/disabled, connection established/interrupted, authorization rejected, callback accepted/rejected, expired/replay rejections, and launch handoff result categories. They do not record the Telegram user ID, chat ID, Bot token, tool name, command, path, or message body.

## 6. Comparison with Same-Network Local Pairing

| Dimension | Same-network local pairing | Telegram Companion Preview |
|---|---|---|
| Usable remotely | No | Yes, as long as the Mac app is running and online |
| Public inbound port | Not needed | Not needed (long polling) |
| Third-party cloud dependency | None | Yes; Telegram handles message transport and the account system |
| Phone app | A native app must be developed | None to develop; Telegram is used directly |
| Device authentication | Local device key and pairing | Telegram user allowlist + Mac-local action token; local policy validation is still required |
| Confidential information boundary | Can be protected with local TLS | Only minimized, non-sensitive status is allowed; no commands or output are transmitted |
| Mac always-on requirement | Local listening/controlled mode | The app must be running and long polling; quitting or sleeping means offline |
| Best suited for | Privacy first, same location | Personally triggering a few authorized tools remotely |

## 7. Verifiable Pilot Stages

| Stage | Scope | Acceptance that must pass |
|---|---|---|
| **T0: offline policy prototype** | Action token, allowlist, expiry, nonce, replay rejection, per-tool authorization state machine | Unit tests cover rejection of forged callbacks, unknown users, group chats, text input, expiry, replay, tools with variables, and install plans |
| **T1: personal Bot long-polling preview** | Controlled switch in the Mac menu bar, Keychain token, private-chat callbacks only, fixed status replies | The token never leaves the Keychain/backups/diagnostics; quitting/sleeping does not delay execution; turning it off revokes all tokens |
| **T2: per-request Mac confirmation** | A Telegram request is handed to the terminal only after local confirmation on the Mac | Fails safely when the user does not confirm, the tool is unhealthy, automation is denied, or the terminal is unavailable |
| **T3: short remote launch window** | Explicitly selected tools without variables, a limited time period, independent authorization per tool | After expiry, revocation, account change, replay, or network reconnection, requests are rejected or re-authorization is required |
| **T4: multi-user/groups/cloud service** | Not on the current roadmap | Privacy, operations, abuse, auditing, and external distribution responsibilities must be re-audited |

## 8. Current Recommendation

If the goal is for you personally to tap known tools occasionally while away, the Telegram approach can serve as a **restricted personal preview**, and it validates product value faster than building an iPhone app. But implementing “run whatever is tapped” directly is not recommended. **T0** should be completed first, confirming that the action token and local policy layer can reject all text, argument, variable, install, and replay attacks, before deciding whether to start T1.

If you prioritize privacy, an offline LAN, and minimal third-party dependencies, the earlier same-network local pairing R0/R1 should continue first. The two approaches can share the “local launch intent policy layer”, but they cannot share an authentication method or treat the Telegram Bot as a trusted command source.

## References

[1]: https://core.telegram.org/bots/api "Telegram Bot API"
[2]: https://core.telegram.org/bots/faq "Telegram Bots FAQ"
[3]: https://core.telegram.org/bots/features "Telegram Bot Features"
