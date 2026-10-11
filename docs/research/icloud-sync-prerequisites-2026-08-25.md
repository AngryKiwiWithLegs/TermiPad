# iCloud sync prerequisites research note

**Date:** 2026-08-25
**Purpose:** A design gate for TermiPad P1 iCloud sync, not implementation notes.

Apple's SwiftData documentation states explicitly that automatic iCloud sync needs two capabilities, iCloud and Background Modes; the iCloud capability needs a valid Apple Developer account with admin permission.[1] The app also needs to enable CloudKit, choose or create a CloudKit container, and turn on Remote notifications to receive server changes.[1]

SwiftData infers the CloudKit container from the entitlements, and the models must conform to CloudKit's schema restrictions. The official documentation specifically notes: CloudKit cannot enforce unique constraints and does not support non-optional relationships; after the production schema is promoted only additive changes are possible, and model types cannot be deleted nor existing attributes changed.[1]

TermiPad's current container factory explicitly uses `cloudKitDatabase: .none` for fixed-store tests, which is right for local-first development and recovery tests. Without an Apple Developer account, team, container ID, entitlements, and a real-device CloudKit environment, it must not be changed into a "looks like it syncs" implementation, nor can P1 iCloud be claimed as done.

Before entering iCloud implementation, the following decisions must be made first:

| Decision | What TermiPad needs to settle |
|---|---|
| Account and container | Apple Developer team, bundle identifier, private CloudKit container, and the development/production environments. |
| Synced objects | Whether tool records, candidates, favorites, and categories sync; API keys, variable values, controlled local icons, working directories, and diagnostics must stay local by default. |
| Conflict strategy | How cross-device conflicts of tool commands are handled; the user's local commands must not be overwritten silently. |
| Migration | Migration of the existing local SwiftData store to a syncing store, backup, rollback, and user choice. |
| Acceptance | At least two test devices on the same Apple ID, offline changes, conflicts, deletion, recovery, and safe fallback. |

## References

[1]: https://developer.apple.com/documentation/swiftdata/syncing-model-data-across-a-persons-devices "Apple: Syncing model data across a person’s devices"
[2]: https://developer.apple.com/documentation/coredata/setting-up-core-data-with-cloudkit "Apple: Setting Up Core Data with CloudKit"
