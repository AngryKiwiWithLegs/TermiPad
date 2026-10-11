# TermiPad phone app: assessment as a formal product capability and achievable scope

**Status:** Product roadmap decision draft; connecting a real Bot token, an HTTPS session service, or remote execution on the Mac is not yet authorized.

## 1. The real scenario to solve

What the TermiPad phone app should solve is not "having a terminal on the phone", but letting the user still see a **controlled tool panel** on their own phone after leaving the Mac: check whether authorized tools are available, confirm whether the Mac can receive requests, and tap a configured icon to ask the Mac to run the existing local terminal handoff flow.

This is a formal capability consistent with TermiPad's core, not an experiment to be rejected because the number of users is unknown. The criteria should be: whether it is technically feasible, whether it can be maintained reliably at acceptable cost, and whether it can stay secure enough without exposing a terminal. The conclusion: **it can be built and has product value; but it must be implemented as a "restricted remote entry", not a "remote shell".**

> The phone app's promise should be: **request your own authorized fixed tools from any appropriate place; the Mac remains the sole execution authority.**

## 2. What the user can actually do

| Phone action | Achievable? | The Mac's final conditions |
|---|---|---|
| Browse the private icon tool catalog | Yes | Only short names, controlled icons, and fixed states are published; no commands, paths, variables, or output. |
| See whether the Mac can respond | Yes | Only fixed states such as `online`, `unreachable`, and `needs local confirmation` are shown. |
| Tap a fixed tool | Yes | Produces only a short-lived, unreadable launch intent that carries no command text. |
| Have the Mac hand off to Terminal / iTerm / Warp | Yes, restricted | The tool exists, is allowed item by item, passes the health check, the account/device is valid, the nonce is not replayed, and the time limit has not passed. |
| Request local confirmation or use a short remote window | Yes | Confirm each time by default; a short window must be opened by the user on the Mac beforehand and expires automatically. |
| Enter arbitrary shell, arguments, paths, variables, or URLs | No | These inputs never become request protocol fields. |
| Browse files, read stdout/stderr, view the screen or processes | No | The phone app gets only fixed result categories. |
| Remotely install, upgrade, uninstall, or change tool trust | No | Supply-chain changes always stay under local review on the Mac. |

So the answer to "can the phone tap an icon": **yes.** In the full version, what is tapped is not a piece of command but a `LaunchIntent`: account or device identity, a short-lived action token, a tool reference, a one-off nonce, an expiry time, and a signature. The Mac then looks up its own tool record locally, rechecks authorization, health, revocation, and the terminal target, and only then decides to hand off or reject.

## 3. Three technical paths

| Path | Can it deliver "tap an icon while away"? | Cost and dependencies | Proper positioning |
|---|---|---|---|
| **Same-LAN native iPhone Companion** | Only when on the same network as the Mac | Native iOS development, pairing, Bonjour, local TLS, real-device permissions; release needs Apple's external conditions | The first companion version with the fewest external dependencies. |
| **PWA private panel** | Yes; depends on a secure session service and the Mac's outbound connection | A fixed HTTPS domain, device pairing/sign-in, a session service; no App Store needed | The lightweight route to a standalone phone entry. |
| **Telegram Mini App** | Yes; shows icons inside Telegram and passes restricted intents to the Mac | A Bot, a fixed HTTPS origin, server-side validation of `initData`, Mac long polling, and ongoing operations | The most direct entry for users already used to Telegram. |

### Same-network native companion

Technically feasible. Apple's Network framework supports local connections using TLS; a local TLS identity consists of a certificate and a private key, which can be stored in the Keychain and verified by the client.[1] Local network access and Bonjour are constrained by user authorization and `Info.plist` declarations, so a real iPhone and a real Mac are the necessary acceptance environment.[2]

Its advantage is having no third-party chat platform and no public session service; its drawbacks are that the user cannot connect on cellular or when away, and that real-device signing, testing, and distribution of a native iPhone app are limited by Apple account conditions. It is a safe first technical path, but not enough by itself to meet the full need of "I am out right now".

### PWA private panel

Technically feasible, and a home-screen shortcut can give an app-like experience. It needs no App Store, but still requires a fixed HTTPS origin, device identity or pairing, short sessions, and a service that can coordinate restricted intents with the Mac. A PWA is not a security model; the security model is still the action verification and authorization window on the Mac.

It suits users who want a standalone TermiPad-branded entry and do not want to depend on Telegram. The cost is concentrated in the domain, HTTPS, the session service, and identity/revocation management.

### Telegram Mini App

Also technically feasible. A Telegram Mini App can launch a full JavaScript icon UI inside Telegram, with support for themes, safe areas, full screen, and home-screen shortcuts.[3] But a Mini App must be loaded from a trusted HTTPS address; the `initData` provided by the client cannot be trusted directly, and the server must verify it with the Bot token and check its freshness.[3]

The Mac need not, and should not, open a public port. Telegram's `getUpdates` lets the Mac initiate long polling to Telegram; officially it is mutually exclusive with a webhook.[4] TermiPad should choose long polling, restrict update types, ignore all free text, files, and group chat content, and accept only fixed actions produced by a verified session. That way Telegram is an entry for passing restricted requests, not a network entry into the Mac.

## 4. Security conditions are an implementation specification, not grounds for rejection

The security cost of this feature exists, but it is no reason to give it up. The security specification should be written into the product rather than left to the user's judgment: the Mac never opens a public listening port; the Bot/Mini App/PWA never touch commands, arguments, paths, working directories, secrets, or terminal output; every tool is authorized individually; install review can never be started remotely; by default every request requires local confirmation on the Mac; a short remote window must be opened deliberately by the user; all requests have account/device binding, signatures, nonces, expiry, replay rejection, rate limiting, and revocation; and when the Mac is locked, asleep, the app bridge is not running, or permissions are unavailable, requests are rejected safely.

The web app, Telegram, and the phone are all untrusted input boundaries. Even if one of these layers is breached, an attacker can only try to submit opaque actions; the Mac must still reject unknown accounts, unknown tools, expired actions, replays, tools with variables, unauthorized tools, and unhealthy tools.

## 5. Formal roadmap

| Phase | Deliverable | Networked? | Why it is necessary |
|---|---|---:|---|
| **R0: restricted launch policy layer** | `LaunchIntent`, per-tool authorization, account/device allowlist, signatures, nonce, expiry, replay/revocation tests | No | Turns "tap an icon on the phone" into auditable rules rather than something patched together later. |
| **R1: Mac companion status and read-only catalog** | Minimal catalog, fixed states, the user turns it on / pauses / revokes on the Mac | Can start local | First validate whether users can understand and manage the boundary. |
| **R2: same-network native pairing** | iPhone Companion, Bonjour, local TLS, one-off pairing, local confirmation each time | LAN only | Delivers real icon requests with the fewest external dependencies. |
| **R3: entry while away** | Choose a PWA or a Telegram Mini App; short sessions and outbound polling from the Mac | Yes | Covers requesting fixed tools when the user is not on the same network. |
| **R4: short remote launch window** | Open only to variable-free, individually authorized tools; automatic expiry and revocation | Yes | Reduces the friction of confirming on the Mac every time, where there is a clear need. |

**R0–R3 should be treated as the phone app's formal follow-up roadmap.** R4 is considered only after R3 matures. Remote arbitrary terminals, cloud relays, remote file browsing, and terminal output return are not on the roadmap, because they are not capabilities the current scenario needs.

## 6. Current decision

The product need for the phone app holds: it solves the continuity problem of still being able to use one's existing tool library when away from the Mac. It can deliver what the user described as "tap an icon on the phone, then the Mac performs a controlled handoff". Technology does not stand in the way; the main costs are the native or web entry, device identity, the session service, and security testing — all engineering costs that can be planned.

The next actual development should start from R0 rather than wiring a Telegram Bot to the Mac right away. This does not delay the goal; on the contrary, it ensures that whichever is chosen later — native iPhone, PWA, or Telegram Mini App — they all share the same verifiable, revocable local security core.

## References

[1]: https://developer.apple.com/documentation/network/creating-an-identity-for-local-network-tls "Apple: Creating an Identity for Local Network TLS"
[2]: https://developer.apple.com/documentation/technotes/tn3179-understanding-local-network-privacy "Apple: TN3179 Understanding Local Network Privacy"
[3]: https://core.telegram.org/bots/webapps "Telegram: Mini Apps"
[4]: https://core.telegram.org/bots/api#getupdates "Telegram Bot API: getUpdates"
