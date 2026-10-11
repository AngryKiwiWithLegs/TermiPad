# TermiPad roadmap completion audit

**Audit scope:** The features, reliability, recovery, and local efficiency capabilities of the private macOS Swift/SwiftUI app. This document does not confuse "the code runs" with "ready for external distribution".

## Current conclusion

TermiPad's original P0 goals and the P1 capabilities that do not depend on a developer account have reached the finishing stage of implementation. The core workflow remains: **scan interactive CLIs the user installed deliberately → confirm in the review inbox → launch or copy with a local command and variable form → manage and recover on this Mac**. Network enrichment, update checks, and the diagnostic package are all add-ons the user opts into and do not change this local-first boundary.

| Roadmap module | Current status | Implemented, or explicit gate |
|---|---|---|
| P0: trustworthy collection | Done | First-run boundary notice, review inbox, manual add, hide/delete/restore, scan filtering, and installation source. |
| P0: trustworthy launching | Done | Variable form, template escaping, Terminal/iTerm/Warp/copy only, copy fallback when Automation is denied, safe wrapping of the local working directory the user explicitly chose with edit-to-fix when the directory is gone, and the local health check when the absolute executable path is no longer valid. The working directory never enters backups or diagnostic packages. |
| P0: trustworthy information | Done | Conservative GitHub matching, visible source/score, AI Keychain and commands that cannot be rewritten, local icon strategy. |
| P0: recovery and verification | Done | JSON backup/preview/merge, old schema compatibility, reopening a fixed SwiftData store, consolidated macOS verification. |
| P1: frequent actions | Done | Favorites, recents, menu bar entry, and in-app keyboard shortcuts. |
| P1: diagnostics | Done | Local ring event log, privacy-preserving JSON diagnostic package, export and clearing initiated by the user. |
| P1: update notices | Done | Off by default, manual HTTPS JSON read by the user, notifies only and never downloads/installs/executes. |
| P1: iCloud sync | External gate, design complete | Defaults to `cloudKitDatabase: .none`, and the account, CloudKit container, conflict, migration, and two-device acceptance conditions are recorded; see `docs/icloud-sync-design-gate.md`. No fake implementation without account/container configuration. |
| P2-A: Project Discovery Preview | Done and passed real macOS verification | Off by default; only a manual user refresh of the fixed public GitHub CLI query; ETag cache, rate-limit backoff, non-fork / non-archived filtering, explainable ranking, and the local cache are all implemented. It does not install software, generate commands, collect projects automatically, or upload local tool data. |
| P2-B: controlled install review | Implemented and verified on real macOS | Only the built-in statically reviewed Homebrew core formula catalog (13 formulae, Sources/ControlledInstallPlan.swift:71-85); exact repository mapping; shows the expected CLI, review revision, date, and fixed command; it can be handed to the chosen terminal or copied only after the user explicitly checks the box and confirms manually. It does not install in-app, read README commands, support taps/casks, or collect automatically. |
| P2-C: read-only environment report | Implemented and verified on real macOS | Only when the user clicks Check does it run `--version` for 6 components at fixed absolute paths (Homebrew / Cargo / npm / pnpm / Bun / Python); it does not enumerate PATH, run a shell, use the network, or install/upgrade/uninstall/arbitrate conflicts. Sources/EnvironmentReport.swift:80-153. |
| Formal external distribution | External gate | Needs an Apple Developer account, Developer ID, Hardened Runtime, notarization, stapling, and an isolated Gatekeeper cold start. |

## Verification requirement for the private beta

After each batch of enhancements is merged, the only verification that needs to run on a real Mac is still:

```bash
cd ~/TermiPad && git pull --ff-only origin master && ./scripts/verify-macos.sh
```

The flow verifies the SwiftPM unit tests, XcodeGen, the native macOS build, UI Runner signature verification, the UI smoke tests, and the result bundle export. It neither performs nor simulates formal signing, notarization, or downloading and installing updates.

## Principles for handling unfinished items

iCloud sync and formal external distribution are blocked by external qualifications; local code cannot replace them. P2-A's discovery preview has been implemented per its separate security design and passed consolidated real macOS verification. P2-B's install assistance and P2-C's dependency governance are not simply "remaining features": they can start only after download source trust, install authorization, a rollback strategy, the scope of package manager support, and the privacy notice are each confirmed separately.
