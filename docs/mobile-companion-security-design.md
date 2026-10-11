# TermiPad phone collaboration security design

**Status:** Feasibility and product boundary design complete; code implementation has not started.

## 1. Conclusion

Controlling TermiPad on the Mac from a phone is technically feasible, but it should not be defined as a "remote terminal on the phone". The right product model is: **a paired phone sends the Mac a restricted launch intent; the Mac only lets that intent reference tools or static install plans that already exist and are authorized locally, and then follows the existing terminal handoff logic.**

The phone must never send shell, arguments, variable values, working directories, tool paths, README content, network metadata, or arbitrary JSON instructions. The Mac opens no general shell, PTY, file browsing, arbitrary port forwarding, service installation, or background command execution. This limits phone collaboration to a remote control for a trusted tool library rather than a new remote code execution entry.

Apple has marked Multipeer Connectivity as deprecated and recommends migrating to the Network framework, which provides TLS, listening, browsing, and bidirectional connections.[1] [2] New phone collaboration should therefore use **Network framework + Bonjour + local TLS + Keychain/CryptoKit key material**, not Multipeer Connectivity or a self-built plaintext HTTP service.

## 2. Three architecture options

| Option | User experience | Security and operations cost | Conclusion |
|---|---|---|---|
| **A. Local pairing on the same LAN** | The phone and Mac are on the same Wi-Fi/Ethernet network; the phone taps an authorized icon and the Mac receives a restricted launch intent | No public port is opened; needs the local network permission, a Bonjour service declaration, TLS, pairing, and revocation | **Recommended first release** |
| **B. Relying on the user's existing secure network access** | The user first reaches the environment through a secure network they manage themselves, then connects to the local bridge service | The network boundary is still carried by the user's existing security infrastructure; TermiPad neither configures nor sells that network | Documentation for advanced users only; no built-in configuration |
| **C. Cloud relay / remote control across the public internet** | The Mac can be controlled on cellular or from elsewhere | Needs accounts, a persistent relay, device online state, abuse protection, push, auditing, service availability, and stricter external security review | **Not on the current roadmap** |

> The first version does only option A: same LAN, explicit pairing, approval each time by default. The Mac does not listen on public interfaces, does no NAT traversal, offers no cloud relay, and does not use iCloud to sync pairing keys.

## 3. First-release product boundary: Local Companion Preview

### 3.1 What it can do

The phone companion app shows only the **minimal catalog** the Mac publishes on its own initiative: the tool display name, local icon identity, a short local description, whether it can be launched remotely, and the result status of the last "handed to the terminal". It does not show the full command, template variables, absolute paths, the working directory, API keys, backup content, or full terminal output.

After the phone taps a tool it sends only a `LaunchIntent` containing the paired device ID, tool UUID, permission configuration version, one-off nonce, expiry time, and signature. The Mac looks up the entity by tool UUID in the local SwiftData store and re-runs the existing health check, remote authorization rules, and terminal target rules. If any check fails, the Mac rejects the request and returns only a fixed status category to the phone, such as "tool no longer available", "local confirmation on the Mac required", or "terminal handoff not completed".

### 3.2 What it does not do

The first release forbids remotely editing commands, entering arguments, running arbitrary terminals, browsing files, creating tools, changing source trust, accepting candidates, starting scans, running controlled install plans, reading the terminal screen, returning terminal stdout/stderr, and running in the background indefinitely. Nor can it bypass macOS restrictions when the Mac is locked, asleep, the app is not running in controlled remote mode, or the Automation permission is unavailable.

## 4. Pairing, authentication, and revocation

First pairing must be completed at the Mac. The Mac shows a one-off QR code or short pairing code and, in the app, the name and fingerprint of the phone waiting to pair; the device relationship is established only after the user explicitly confirms on the Mac. The pairing code should be valid only briefly, usable once, and contain no commands or local paths.

After pairing, both sides generate or exchange separate device keys. Private keys and pairing keys are stored only in each platform's Keychain; the Keychain can hold small secrets, certificates, and communication trust assets.[3] CryptoKit supports key agreement, digital signatures, and symmetric encryption, and is preferred over handling low-level cryptographic memory yourself.[4] Every launch intent needs a signature, a monotonic nonce, a short expiry, and the pairing ID; the Mac must also do replay rejection, rate limiting, and revocation checks.

The Mac's Settings page should show paired devices, last activity time, and permission state, and offer three actions: "Pause phone collaboration", "Revoke this device", and "Revoke all devices". Revocation must invalidate existing sessions immediately. Paired device names, keys, nonce state, and authorization configuration must not enter JSON backups, diagnostic packages, or the iCloud sync scope.

## 5. Local transport and system permissions

The local bridge uses the Network framework's `NWListener`, `NWBrowser`, and TLS connections, not plaintext HTTP. Apple explicitly provides a path for creating a digital identity for local network TLS; a TLS identity consists of a certificate and a private key and can encrypt traffic between client and server.[2] The first version should fix one TermiPad-specific Bonjour service type, use a minimum TLS version policy, and apply certificate or public-key pinning to paired clients rather than accepting arbitrary LAN clients.

Local network access is governed by the Local Network privacy control on iOS/iPadOS and macOS. The first time an app accesses the local network, the system asks the user to allow it; if Bonjour is used, the specific service types must also be declared in `Info.plist`.[1] Both the phone and the Mac must explain, in clear Chinese/English permission text, "discovers only the paired TermiPad Mac on the same LAN, does not scan other devices, and does not expose a terminal". The iOS Simulator does not support this privacy behavior, so acceptance must use a real iPhone and a real Mac.[1]

## 6. Remote launch authorization model

The default mode is that **every request needs confirmation on the Mac**. This is the safest, but it cannot meet the need to operate after the user has left the computer entirely. So the user can deliberately open a short "remote launch window" on the Mac, which applies only to explicitly selected tools.

| Permission mode | Default | What the phone can do | The Mac's protection |
|---|---|---|---|
| View only | Default | Browse the minimal tool catalog and status | No terminal handoff is initiated |
| Request launch | Optional by default | Send the Mac a launch request for an existing tool | The Mac must show local confirmation |
| Short remote launch window | Off by default | Launch tools that are individually authorized and need no variable input | Validity period, tool allowlist, health check, rate limiting, revocation, and terminal handoff fallback |

Install review plans are never allowed to be handed off from the phone, by default and always. They involve software supply-chain changes and must stay on the Mac's local review and explicit confirmation path. If opening this up is ever considered, it must be a separate security review and cannot be mixed with tool launching.

## 7. Status return and privacy

The phone can get only fixed result categories: `requested`, `waiting for Mac confirmation`, `handed to Terminal/iTerm/Warp`, `copied`, `Mac offline`, `tool unavailable`, `rejected by permission policy`. No commands, variables, absolute paths, process output, exit codes, file names, or network metadata are returned.

Local diagnostics record only fixed counter categories, such as pairing created, pairing revoked, launch request accepted/rejected, replay rejected, and session expired; tool names, repository names, commands, paths, device tokens, and version output are not recorded.

## 8. Suggested phased implementation

| Phase | Scope | Acceptance criteria |
|---|---|---|
| **R0: threat model and prototype** | `LaunchIntent` data model, signature/nonce verification, local state machine on the Mac; no network opened | Unit tests cover rejection of forged signatures, expiry, replay, revocation, unauthorized tools, and variable injection |
| **R1: same-network pairing and read-only catalog** | Native iPhone app, Bonjour discovery, local TLS, one-off pairing, minimal catalog | Verification on a real iPhone + Mac of allowing/denying the local network permission, pairing, revocation, offline, and restart |
| **R2: remote requests confirmed each time** | The phone sends a restricted launch intent; the Mac must approve locally | The phone cannot submit raw commands; unapproved, locked, unhealthy tool, and terminal refusal cases all fail safely |
| **R3: short remote launch window** | Explicitly opened on the Mac, per-tool authorization, automatic expiry | Only variable-free tools are allowed; expiry, revocation, replay, network switch, and wake from sleep all reject or require re-pairing |
| **R4: remote access from elsewhere** | Relays, accounts, and service responsibility are evaluated only after a new project approval | Not part of the current commitment; needs separate privacy, security, operations, and Apple distribution reviews |

## 9. Current decision recommendation

The recommendation is to enter only **R0** next, then let the user decide whether to continue with R1. R0 does not need to open the terminal to the phone or the LAN: it only abstracts the existing "hand off to the chosen terminal after the user clicks a tool" flow into an auditable, rejectable, signable local launch intent. Only when R0's security tests pass is it worth starting the iPhone app and local network permission work.

The current project can keep the stable positioning of `TermiPad Mendocino`; phone collaboration should use a separate preview codename and must not slip quietly into the existing stable version.

## References

[1]: https://developer.apple.com/documentation/technotes/tn3179-understanding-local-network-privacy "Apple: TN3179 Understanding local network privacy"
[2]: https://developer.apple.com/documentation/network/creating-an-identity-for-local-network-tls "Apple: Creating an Identity for Local Network TLS"
[3]: https://developer.apple.com/documentation/security/keychain-services "Apple: Keychain services"
[4]: https://developer.apple.com/documentation/cryptokit "Apple: CryptoKit"
[5]: https://developer.apple.com/documentation/multipeerconnectivity "Apple: Multipeer Connectivity (deprecated)"
