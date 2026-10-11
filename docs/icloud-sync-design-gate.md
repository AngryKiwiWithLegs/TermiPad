# TermiPad iCloud sync design gate

**Status:** Not implemented; explicitly disabled by default.
**Applies when:** An Apple Developer account with admin permission is available and a CloudKit container has been created.
**Purpose:** Prevent "turning on the iCloud capability" from being mistaken for a sync feature that is safe to ship.

## 1. Current boundary

TermiPad's default SwiftData `ModelConfiguration` explicitly sets `cloudKitDatabase: .none`. Even if the project gains an iCloud entitlement in the future, data will not sync by accident through automatic container discovery. Any iCloud implementation must add a separate, audited sync configuration and must not change the semantics of the default local-first container.

> In the current version, JSON backup is still the only supported way to migrate between devices; the user exports and imports it deliberately and can preview, merge, and restore.

## 2. Apple prerequisites

Apple's automatic SwiftData sync requires the iCloud and Background Modes capabilities, a CloudKit container, and Remote notifications; the iCloud capability needs a valid Apple Developer account with admin permission.[1]

| Prerequisite | Current status | Completion bar before implementation |
|---|---|---|
| Apple Developer team | Not available | Obtain team permission to manage capabilities. |
| Bundle ID and signing configuration | Ad hoc for development | Set up a team-managed app identifier and development signing. |
| CloudKit container | Not created | Create a private container and record the container identifier and the development/production environments. |
| iCloud / Background Modes | Not enabled | Enable CloudKit and Remote notifications, and audit the entitlements. |
| CloudKit schema | Not initialized | Initialize and review it in the development environment, and complete the migration strategy before promoting to production. |

## 3. Sync scope: local-first by default

| Data | Initial sync strategy | Reason |
|---|---|---|
| Tool names, categories, descriptions, favorites | Could be synced | Low-sensitivity tool metadata that is portable across devices. |
| Launch commands the user edited manually | Needs explicit conflict handling | Commands have execution impact; a remote version must not silently overwrite the local one. |
| Review inbox | Not synced by default, or behind its own switch | Discovery results depend heavily on the local install environment and may be invalid on another device. |
| Working directory | Not synced | Paths are machine-specific and currently do not enter JSON backups either. |
| Custom local icons | Not synced | They are only controlled local files; binaries or paths should not spread through CloudKit. |
| Saved variable values | Not synced by default | May contain sensitive tokens, private paths, or environment information. |
| AI API key | Never synced | Stored only in the macOS Keychain. |
| Diagnostic records | Not synced | Local support information for the current device only. |

## 4. Conflict and migration requirements

How CloudKit handles concurrent changes, together with SwiftData's model restrictions, means commands or user preferences cannot rely on "last writer silently wins". Before implementation, at least the following strategies must be designed:

1. Keep manually modified commands, working directories, variable values, icons, and API keys local-first, and do not add them to the sync schema.
2. When syncable metadata conflicts, show a clear choice or keep timestamped versions; the local launch command must never change silently.
3. Before turning sync on, require the user to export a JSON backup first; provide a reversible path to turn sync off and keep using the local store.
4. Rehearse schema initialization, offline edits on two devices, reconnecting, deletion, reinstall, and backup restore in the CloudKit development environment first; after the production schema is promoted, only additive changes are allowed.[1]

## 5. Conditions under which it must not be called done

If any of the following is missing, TermiPad must not be described as "supporting iCloud sync" in the UI, the README, or release notes: no developer account, no CloudKit container, no verification on two real devices, no conflict strategy, or no rehearsal of migration from and rollback to the existing local SwiftData store.

## References

[1]: https://developer.apple.com/documentation/swiftdata/syncing-model-data-across-a-persons-devices "Apple: Syncing model data across a person’s devices"
