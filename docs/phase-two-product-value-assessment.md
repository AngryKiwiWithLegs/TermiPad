# TermiPad phase-two product value assessment

**Status:** Product roadmap judgment; it does not authorize development of Telegram, a PWA, an iPhone app, or remote execution.

## Conclusion

TermiPad's product core is not "remote control of a terminal", but **turning the CLIs the user has deliberately installed, understands, and wants to interact with into a reliable, recognizable, auditable icon launcher on macOS.** So what phase two should invest in most is not adding more entry points, but further improving the recognizability, organization, recovery, and launch determinism of the local tool catalog.

The completed P2-A (read-only GitHub discovery), P2-B (controlled Homebrew install review), and P2-C (read-only environment report) are the safe, controlled extensions of the original design; they already form the complete loop of "P2 as originally defined". Phone collaboration, Telegram, the Mini App, and the PWA are new, separate exploration lines; they should not be mistaken for prerequisites of completing P2, nor slip quietly into the stable `TermiPad Mendocino`.

## Assessment criteria

This assessment uses five dimensions: whether it directly strengthens the core positioning; whether users would use it frequently; whether it keeps an understandable security model; whether it introduces ongoing operations and external dependencies; and whether it can deliver value without external accounts, servers, or release qualifications.

| Candidate capability | Fit with the core positioning | Expected frequency | Security / operations burden | Phase-two judgment |
|---|---:|---:|---:|---|
| Local icon library, picker, and collision-free assignment | Very high | Very high | Low | **Necessary, implement first** |
| Improving local tool catalog organization, search, favorites / recents | Very high | Very high | Low | **Necessary, keep improving** |
| Polishing the readability and auditability of the existing controlled discovery, install review, and environment report | High | Medium | Low to medium | **Worthwhile, iterate on real usage feedback** |
| Same-network native read-only phone catalog and local pairing | Medium | Conditionally medium | High | **Meaningful, but deferred as a separate preview** |
| PWA static icon panel | Medium | Low to medium | Medium | **Suitable as an experience prototype, not a main product capability** |
| Telegram Mini App icon panel | Medium | Conditionally medium | High | **Only when Telegram is already a fixed personal entry point** |
| Pure Telegram Bot text buttons | Low | Conditionally low | Medium | **Not recommended as the main path of an icon product** |
| Remote restricted launching / cloud relay | Conditionally high | Conditionally low | Very high | **Not on the roadmap now** |

## Necessary phase-two investments

### 1. The icon system is a core capability, not decoration

What sets TermiPad apart from an ordinary launcher is exactly "whether the user can recognize a tool at a glance, trust what it corresponds to, and still have it stay stable as the library grows". The existing fixed SF Symbols, stable hash fallback, and local-PNG-first strategy have laid the right foundation; phase two should add a richer local icon library, stable persisted assignment, deterministic conflict handling, manual selection, and controlled PNG priority.

This investment improves the grid that is used every day and does not change the command, network, or permission boundaries. Its value is **faster recognition, a lower chance of launching the wrong thing, and a stronger sense of ownership over the library**, not merely a prettier UI.

### 2. Trustworthiness and recoverability of the local workflow

The review inbox, tool health, terminal handoff, isolated backup recovery, favorites / recents, and per-tool working directories decide whether the product can be trusted in daily work over the long term. Phase two should follow real usage feedback and first handle frequent questions such as "why can't I find this tool", "why can't it launch right now", and "how do I safely restore the original configuration", rather than pursuing more automation.

The three controlled extensions of P2 should stay conservative: GitHub discovery is off by default, Homebrew only produces explicit review plans, and the environment report is read-only. Their value lies in helping users understand and verify existing workflows; they must not evolve into automatic install, automatic update, or a supply-chain control panel.

## Valuable capabilities that must be deferred

### Local phone companion

It has real value for users who "after leaving the Mac need to view their tool catalog, confirm the Mac's current state, or occasionally start a handoff of an authorized tool". But the value comes first from **same-network visibility and paired devices**, not from remote control. The right first milestone is R0: implement a signable, expiring, revocable, rejectable `LaunchIntent` policy layer locally on the Mac; this step opens no network and needs no iPhone app.

Only when R0's rejection tests for forgery, expiry, replay, revocation, unauthorized tools, and variable injection all pass, and the user confirms that a same-network phone entry is a frequent need, is it worth entering R1's local pairing and read-only catalog. It should be a separate preview and not replace the local macOS product.

### PWA static icon panel

A PWA is valuable for validating the phone layout, home-screen shortcuts, and the icon grid, and needs no Apple Developer account; but it is not a secure identity system and cannot inherently access the Mac safely. Its most fitting role is **an M1 experience prototype or a future read-only private catalog**, not the product's second core client.

## Capabilities that should not be invested in now

### Telegram Bot and Mini App as the main product entry

A Telegram Mini App does solve "showing a real icon grid inside Telegram", but what it solves is where the UI lives, not the core workflow. It requires a Bot identity, token management, a fixed HTTPS origin, server-side `initData` validation, a short-session service, web supply-chain constraints, and ongoing operations. Ordinary Bot text buttons, in turn, dilute TermiPad's icon-based distinctiveness.

So it can be kept as a private personal experiment: when Telegram is already an entry point the user uses every day, it is worth trying as a restricted icon catalog; but it should not be the default route for all TermiPad users, and still less should accounts, relays, webhooks, or public services be introduced early just so that "remote control is possible".

### Remote execution from elsewhere and cloud relays

This capability would push the product from a local launcher toward a remote device management product. Even with only fixed tools allowed, it introduces online state, device identity, revocation, replay, latency, push, account recovery, service availability, abuse protection, and security response responsibilities. Until there is enough real usage demand, its risk and maintenance cost clearly outweigh its value to the current product.

> For TermiPad, the best "remote feature" is not letting a terminal run from anywhere, but keeping the user always clear about: what can be requested, who is requesting, whether the Mac is online, and why the Mac accepts or rejects.

## Suggested tiered roadmap

| Tier | Goal | Suggested scope |
|---|---|---|
| **Phase-two core** | Keep the local launcher fast, recognizable, and recoverable as tools multiply | Icon library, conflict assignment, manual icon management, catalog organization, and polishing the frequent launch paths |
| **Phase-two security polish** | Let users understand the optional extensions without losing control | Improve the explanations, auditing, and rejection paths of P2-A/P2-B/P2-C based on real feedback |
| **Separate experiment line** | Validate whether the phone icon experience really changes the workflow | The R0 local policy layer; then only a same-network read-only catalog or an M1 static PWA preview |
| **Explicitly deferred** | Keep the product from being pulled off course by external platforms and the complexity of remote execution | Telegram integration, real remote requests, long remote windows, remote relays, and cloud accounts |

## Current recommendation

If phase two can pick only one main line, it should be the **local icon system and tool catalog management**. It is fully consistent with TermiPad's name, core experience, and completed architecture, has the lowest security cost and the highest usage frequency, and does not depend on an Apple account, Telegram, a domain, or a long-running server.

The phone companion should stay a preview project that "continues only after the local policy layer passes"; the Telegram Mini App should be demoted further to an optional interface that "continues only when the user explicitly confirms they will open the tool catalog through Telegram over the long term". This way phase two has clear, deliverable product value and is not held hostage by the imagined possibilities of remote control.
