# M2 remote secure session design — built-in tunnel (M2a batch)

**Status:** Design review draft (2026-09-08). Review first, then implement; this document claims no capability as implemented.

**Parent documents:** `docs/product-roadmap.md` §5 stage 5 (M2 — remote secure session, including the 2026-09-08 transport technology decision); `docs/m0-m1-mobile-entry-design.md` (pairing/encryption/revocation layer, reused unchanged by M2).

**Scope split:** This batch = **M2a (remote launching of fixed tools)**. M2b (the phone submits temporary task proposals, connected to the TaskIntent/T0/T1 policy core) is a separate batch; M3 (remote allow window) is designed separately after M2a is verified on real devices. See §8 for how the three relate.

## 1. North-star scenario

The user is out (on cellular) and taps a fixed tool in the TermiPad companion on the phone → the command runs on the **Mac at home** through the existing terminal handoff → the phone receives the minimal result (accepted/rejected). Throughout: zero public exposure, commands/paths/variables/output are never sent, and every permission is revocable.

**Honest statement (expectation management):** after M2a is complete, a remote `requestLaunch` **still needs local confirmation on the Mac** (the everyTime default is unchanged; perSession's 5-minute in-process memory window has most likely expired after the user left). "Unattended, no confirmation" is the deliverable of **M3**. M2a's value is removing "cannot connect" and laying the pipe for M3; finally resolving the deadlock depends on M3 — that is the planned order, not a defect of this batch.

## 2. Premises and verified facts (checked 2026-09-08)

| Fact | Evidence |
|---|---|
| Tailscale 1.102.2 (Homebrew) is installed on the user's Mac | `/opt/homebrew/bin/tailscale` |
| The Mac and iPhone are already on the same tailnet | `tailscale status`: `macbook-pro 100.114.69.20`, `iphone-14-plus 100.95.196.38` |
| This version's `tailscale serve --tcp` supports **raw TCP forwarding** (not only HTTPS) | `tailscale serve --help` |
| No leftover serve configuration on this Mac | `tailscale serve status` = No serve config |

**Integration model choice (the core decision of this design):** follow the pattern proven by OpenClaw — **rely on the Tailscale the user installed themselves, with TermiPad only orchestrating**; no embedded tailscaled and no home-made WireGuard.

| Candidate | Conclusion | Reason |
|---|---|---|
| A. User-installed Tailscale + TermiPad manages serve forwarding | **Adopted** | Cryptography / NAT traversal / key rotation are all left to a professional component; TermiPad gains zero new network code surface; the user's tailnet is ready; the same pattern has run on this Mac for a long time with OpenClaw |
| B. Embedded tailscaled (as a library) | Rejected | Engineering effort and permission surface grow sharply; version tracking and maintenance burden; out of proportion to the benefit for a free-account app |
| C. Home-made VPN/WireGuard | Rejected | Project red line: no home-made cryptography |
| D. Tailscale Funnel (public entry) | **Permanently disabled** | Public exposure violates the product red lines; see the guards in §6 |

## 3. Connection architecture

```
[cellular] iPhone companion app
   │  ① Try a direct LAN connection first (the M1 path, fastest on the same network) — on failure/timeout
   ▼  ② fall back to the tailnet: hostPort(the Mac's tailnet IP, 57147)
[VPN channel provided by the Tailscale iOS app — WireGuard encryption, mutual authentication by the user's account]
   ▼
[Mac at home] tailscaled receives tailnet:57147 → serve forwards → 127.0.0.1:57147
   ▼
[TermiPad] loopback listener (bound only to 127.0.0.1:57147) → existing M1 handshake/encryption/request chain
```

**Why a loopback listener + serve forwarding instead of binding NWListener directly to the tailnet interface:**
- A loopback listener = the **smallest network exposure surface**. On the Mac the port is invisible to the LAN, the public internet, and other virtual interfaces; only tailscaled (a component the user installed themselves, running as root) can forward into it. This is the strongest form of the red line "the Mac opens no public ports".
- Network.framework's ability to bind to utun interfaces is unreliable (`requiredInterfaceType` has no utun case) and fragile across Tailscale versions; serve is the forwarding path Tailscale officially supports.
- The same pattern already runs stably on this Mac with OpenClaw (gateway bound to loopback + a `tailscale serve` worker, confirmed from processes on 2026-09-08).

**Why not reuse M1's port 57146:** the M1 listener is bound to `.wifi` and comes with the Bonjour advertisement and the iOS 26 instance-name workaround; the tunnel listener has completely different semantics (loopback, no advertisement). A separate port 57147 keeps the two paths from interfering, lets them be toggled independently, and isolates failure domains. **57147 is a fixed port** (written into the protocol constants, next to 57146).

## 4. Protocol and data (minimal increment)

### 4.1 Non-breaking protocol increment

The whole M1 resume handshake chain (`PhoneResumeHello` → `MacResumeHello` → encrypted `MobilePairingRequest`) **runs unchanged over the tunnel** — the encryption layer (X25519+HKDF+AES-GCM), fingerprint binding, operation allowlist, eligibility pre-check, and local confirmation are all unchanged.

**The only protocol change:** `MacResumeHello` gains an optional field

```swift
struct MacResumeHello: Codable {
    let protocolVersion: Int
    let macPublicKey: Data
    let macNonce: Data
    /// M2a: remote endpoint "100.114.69.20:57147". Non-nil only when the user turns on "Remote Access".
    /// nil = this batch's feature is off / Tailscale was not detected — the phone's remote path is unavailable (stated explicitly, not silent).
    var tailnetEndpoint: String?
}
```

- **Sending it in plaintext is acceptable** (same frame as the existing MacResumeHello): the confidentiality of the tailnet IP is inherently protected by tailnet membership — non-members cannot route to the 100.64/10 range at all; leaking it does not weaken any security layer (a connection still needs both tailnet membership + app-layer pairing). A same-network attacker who learns the IP still has nowhere to go.
- **Forward and backward compatible**: old Macs do not send it (decodes to nil); old phones ignore the new field (JSONDecoder ignores unknown keys by default). **No protocol version bump is needed**.
- Persisted on the phone: `CompanionPairingCredentials` gains an optional `tailnetEndpoint` field, **Keychain-only** (the same discipline as §3.4 of the M0-M1 design). **It must be decoded with a custom `decodeIfPresent`** — old credential JSON lacks this key, and synthesized decoding would throw; this is where the red line "new fields must be Optional + old data compatible" lands, and the implementation batch comes with unit tests.

### 4.2 Address learning flow (same-network pairing bootstraps remote access)

1. The user turns on the "Remote Access" switch on the Mac → TermiPad detects Tailscale → reads the tailnet IP (`tailscale ip -4`, fixed path and fixed arguments) → configures serve forwarding → starts the loopback listener
2. After that, every successful same-network resume carries `MacResumeHello.tailnetEndpoint` in the frame
3. The phone writes the endpoint into its credentials (Keychain) and uses it directly when away from then on
4. Away from home the user **needs no pairing steps at all** — the bootstrap was completed long before on the same network

**Self-healing of a stale endpoint:** if a remote connection from the phone is refused / times out, the next same-network resume refreshes the endpoint (the Mac's tailnet IP changes only when the user switches tailnets manually; it is normally stable).

## 5. Mac-side design (added inside Sources; guard constraints in §6)

| Component | Responsibility | Boundary |
|---|---|---|
| `TailnetTunnelService` (new file, @MainActor ObservableObject) | Switch state machine off / detecting / ready / failed; calls the CLI; manages the loopback listener lifecycle | The only file allowed to call the tailscale CLI |
| CLI calls | `tailscale ip -4` (read), `tailscale serve --bg --tcp=57147 tcp://127.0.0.1:57147` (on), `tailscale serve --https=443 --tcp=57147 off` (off) | **Fixed absolute-path allowlist**: `/opt/homebrew/bin/tailscale`, `/usr/local/bin/tailscale` (the same discipline as EnvironmentReport: fixed path + fixed arguments + no user input concatenated, never through a shell) |
| Loopback listener | `NWListener` + `requiredLocalEndpoint = 127.0.0.1:57147` (if the framework cannot bind loopback, degrade to binding all interfaces + document the difference; app-layer encryption is unaffected) | Reuses the whole M1 `beginHandshake` chain — the `MobilePairingService` handshake code is extracted into a shared entry point, **not copy-pasted** |
| State and UI | Under Settings → Mobile Companion, a new "Remote Access (requires Tailscale)" section: switch + status line (Tailscale not detected / ready `100.x.x.x:57147` / off) | **Off by default** (the same default level as the M1 same-network pairing switch); turning it off immediately runs `serve off` + stops the listener + `MobileLaunchSession.invalidateAll()` |
| Diagnostics | `DiagnosticEventKind` gains the fixed enums `remoteTunnelOpened` / `remoteTunnelClosed` (timestamp only, no IP / tool name — privacy discipline) | The tailnet IP is not recorded in diagnostics |

**Note on refactoring the handshake entry point:** M1's `beginHandshake` currently enters from `newConnectionHandler` and carries comments with Bonjour semantics; when extracting it, keep the behavior byte-for-byte unchanged (the two listeners differ only in where connections come from), and the extraction batch runs the full consolidated verification + the same-network G4 regression.

## 6. Security analysis and continuity of the red lines

| Layer | Protection | Change in M2a |
|---|---|---|
| Network layer | WireGuard (mutual authentication of tailnet members) + zero public exposure (outbound tunnel) | New layer; Funnel permanently disabled |
| Transport layer | App-layer X25519+HKDF+AES-GCM, fingerprint comparison by eye | Unchanged, reused as is |
| Authorization layer | Eligibility pre-check + local confirmation (everyTime default) + revocation effective immediately | Unchanged; the confirmation prompt appears as usual for remote requests (the device name hint is unchanged) |
| Data layer | The phone receives only the 4-field catalog + result enums; the tailnet endpoint goes into the Keychain and not into backups | 1 new credential field (decodeIfPresent compatible) |

**Lost-phone analysis (the surface added by the tailnet scenario):** an attacker who picks up the phone needs both (a) the Tailscale iOS app's tailnet membership (Tailscale itself has Keychain protection / optional biometrics and belongs to the user's account domain) and (b) the pairing credentials in the companion app's Keychain. Missing either one, they cannot get in. **And** the user can at any time, on the Mac: turn off the remote access switch (serve is withdrawn at once), revoke the device pairing, or revoke tool permissions — three ways to withdraw immediately.

**New guards (entering verify-macos.sh in the implementation batch):**
1. `tailscale` CLI calls may only appear in `TailnetTunnelService.swift` (static grep allowlist pattern, like the NWListener guard)
2. The `funnel` subcommand is forbidden across the whole repository (any occurrence fails verification — public exposure red line)
3. The port constant `tunnelListenerPort = 57147` is declared next to 57146
4. Decoding of `CompanionPairingCredentials` must use `decodeIfPresent` (locked by tests)

## 7. G5 acceptance checklist (remote, real devices; M2a is declared complete only when all pass)

| # | Verification item | Pass criterion |
|---|---|---|
| 1 | Bootstrap | After a same-network pairing resume, the phone's credentials contain tailnetEndpoint; nil when the remote access switch is off |
| 2 | Remote resume | Phone on cellular (Wi-Fi off), Mac at home: resume succeeds and the tool catalog is reachable |
| 3 | Remote launch + confirmation | Tap a tool remotely → the Mac prompts for confirmation → confirm and run → green ✅ on the phone; the denial path is verified as well |
| 4 | Dual-channel fallback | Back on the same network the LAN path recovers automatically (no re-pairing); with the remote access switch off, the phone clearly says "remote channel not enabled" instead of spinning forever |
| 5 | Immediate withdrawal | The Mac revokes the device → a remote resume is rejected immediately (same semantics as G4 #6); turn off the remote access switch → the phone's connection fails with explicit copy |
| 6 | Red-line review | The Mac has no public inbound (no mapping on the router's WAN side); `tailscale serve status` shows only tcp forwarding inside the tailnet; the phone never sees commands/paths/variables/output |

## 8. Link to M2b / M3 (preview, not in this batch)

- **M2b (temporary task proposals)**: add operation allowlist cases (`proposeTask`, etc.) on the M2a pipe and connect T0 TaskIntent policy verification to phone requests — the protocol framework already reserves room to extend the `PairedDeviceOperation` enum; M2a does not pre-implement it.
- **M3 (remote allow window)**: once the pipe is ready, `MobileLaunchSession` (M1.1's 5-minute allowlist) is generalized into a `RemoteAllowWindow` the user authorizes explicitly (tool set + user-set duration + immediate invalidation on lock/sleep + rate limiting + auditing). This design does not predefine its fields — the contract is frozen once M2a has been experienced remotely.
