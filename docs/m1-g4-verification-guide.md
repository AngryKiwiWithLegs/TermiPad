# M1 G4 two-device verification guide (free Apple ID signing)

**Applies when:** After the Mac-side implementation on the `feature/m1-local-network-pairing` branch is merged and before G4 is declared passed.

**Premise:** `docs/m0-m1-mobile-entry-design.md` §3.1/§6 (updated 2026-09-06) — a free Apple ID (personal team) supports real-device **development verification**; long-term install / TestFlight / external distribution still need a paid membership.

## 1. One-time preparation (can be done ahead of time, in parallel with development)

| Step | Action | Notes |
|---|---|---|
| 1 | Xcode → Settings → Accounts → sign in with your Apple ID | A free personal team is created automatically; no payment needed |
| 2 | iPhone: Settings → Privacy & Security → Developer Mode → turn on | Required for sideloading on iOS 16+; the phone must restart |
| 3 | Connect the iPhone to the Mac with a cable, Xcode → Devices and Windows → trust and enable | The device is registered in the personal team |
| 4 | Make sure the Mac and iPhone are on the **same Wi-Fi** and the router does not have AP isolation on | AP isolation blocks Bonjour and is the most common cause of discovery failure |

**Free account limits (be aware):** ≤3 apps installed at the same time per device; App ID / device registration **expires after 7 days**; 10 new App IDs per week. Once the phone app expires its icon turns white and it will not open — Run it once more in Xcode to renew. **This does not affect TermiPad on the Mac** (local ad hoc signing, no 7-day limit).

## 2. Acceptance checklist (G4 completion conditions; record evidence for each item)

| # | Verification item | Pass criterion | Evidence |
|---|---|---|---|
| 1 | Bonjour discovery | The iPhone app can see `TermiPad` (`_termipad-m1._tcp`) in the list | Screenshot |
| 2 | Fingerprint comparison by eye | The Mac fingerprint shown on the iPhone matches the one on the Mac's Settings page | Screenshot ×2 |
| 3 | Pairing succeeds | After entering the pairing code, the device's record appears in the Mac's `PairedDeviceStore` | Mac screenshot |
| 4 | Session encryption | After pairing the phone can list the tool catalog of tools with `showInMobileEntry=true` (4 fields only) | Screenshot |
| 5 | Launch request + local confirmation | Tap a tool on the phone → the Mac prompts for confirmation per `mobileLocalConfirmPolicy` → after confirming, the terminal opens via `TerminalLauncher` | Screenshot |
| 6 | Double revocation | The Mac revokes the device / revokes the tool's mobile permission → it stops working on the phone immediately | Screenshot |
| 7 | 7-day re-signing | After reinstalling on expiry, the pairing flow works again (record truthfully whether the pairing credentials were kept) | Record |

**Red-line review (failing any item means G4 does not pass):** the phone must never see commands / paths / variables / environment variables / terminal output at any time; the Mac has no public inbound port (listening is only the Bonjour LAN advertisement); operations outside the allowlist are always rejected.

## 4. Acceptance record

**2026-09-06 first round (iPhone 14 Plus, iOS 26.6.1 ↔ MacBook Pro, 192.168.2.81/en0):**

| # | Verification item | Result | Notes |
|---|---|---|---|
| 1 | Bonjour discovery | ✅ Passed | `_termipad-m1._tcp`; the iOS local network permission declaration is generated from project.yml info.properties (a hand-written plist was once overwritten by XcodeGen, see commit 278b9a7) |
| 2 | Fingerprint comparison by eye | ✅ Passed | Confirmed by eye after MacHello.fingerprint on the phone screen matched the Mac screen |
| 3 | Pairing succeeds | ✅ Passed | Keychain entries `mobile-pairing.device-index=["BE0172EB-…"]` + `mobile-pairing.identity` both confirmed present |
| 4 | Session encryption (tool catalog) | ✅ Passed (2026-09-07) | Encrypted resume handshake + listTools; phone log `Received tool catalog count=3` (commit a161200) |
| 5 | Launch request + local confirmation | ✅ Passed (2026-09-08) | Both paths tested: tap a tool card on the phone → the Mac shows the 60s confirmation → after confirming, the terminal runs it and the phone shows a green ✅; on the denial path the phone shows an orange ✖ (the rejection reason is echoed). Mac log (three rounds of `Received request op=requestLaunch toolID=…` at 08:34:49/08:35:06/08:35:12). Root cause of the first round's "no reaction on the Mac": the phone switched phase too early, so the send block was skipped silently (fixed in commit 07f2495); list requests always worked because they do not switch phase |
| 6 | Double revocation tested | ✅ Passed (2026-09-07) | The Mac revokes the device → the phone's resume is rejected immediately (no response to the resume handshake), and the UI clearly prompts to pair again and clears the credentials automatically (commit a394e93) |
| 7 | 7-day re-signing | ⏳ Not tested | Time-dependent; the profile is actually valid until 2026-09-13. The signing mode was changed to Automatic (commit 07f2495); Manual mode requiring an explicit profile had blocked the build; whether credentials survive re-signing is still to be recorded |

**2026-09-08 M1.1 real-device retest (perSession/lowRisk session allowlist, commit 1781496):**

| # | Verification item | Result | Notes |
|---|---|---|---|
| 5a | lowRisk direct launch without confirmation | ✅ Passed | After the user set the tool's policy to `lowRiskSessionOnly`, four consecutive launches from the phone: the first prompted for confirmation and wrote the allowlist; three Mac log entries `Session allowlist hit, launching directly without confirmation policy=lowRiskSessionOnly` at 12:42:31/12:42:39/12:43:32 (within 88 seconds, inside the 5-minute window). The metacharacter second line of defense did not intercept (the template is clean) |
| 5b | First-confirmation path regression | ✅ Passed | The first request at 12:42:04 went through the 60s confirmation prompt normally (the everyTime path is unaffected by M1.1) |

9 M1.1 unit tests (window expiry / refresh / per-tool isolation / metacharacter defense / immediate invalidation on revocation) + the full consolidated verification `20260908-090453` passed.


**Conclusion: G4 in progress (5/7 + the M1.1 extras all passed).** Free signing (team 7LTPLQKWWD, rotated by Apple on the 2026-09-06 re-login) + Developer Mode + same-network mDNS are all confirmed to work. Only the time-dependent item #7 remains (re-signing when the profile expires on 2026-09-13).
