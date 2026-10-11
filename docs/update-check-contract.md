# TermiPad Private Update Check Contract

**Status:** An optional auxiliary capability for the private beta. It is off by default and does not constitute a release, signing, notarization, or auto-update solution.

## User Boundary

The user must turn on manual checks themselves in **Settings → Update Checks** and enter an HTTPS update source. TermiPad does not go online automatically at launch and makes no request when no update source is configured. Each check happens only after the user clicks “Check for Updates”.

> The update check reads only version metadata; it does not download, install, execute, or verify any app artifact.

| Item | Rule |
|---|---|
| Allowed update sources | An HTTPS URL with a non-empty host name. |
| Request method | A single `URLSession.data(for:)` read with a 10-second timeout, ignoring the local cache. |
| Disallowed approaches | HTTP, automatic downloads, installer invocation, executing downloaded content, changing the app signature or quarantine attributes. |
| Release notes | The optional `releaseNotesURL` must also be HTTPS; it opens in the system default browser only after the user clicks it. |
| Version format | Non-negative integers in `major[.minor[.patch]]`; other formats are rejected. |
| Privacy | Diagnostics record only the fixed category of update check success or failure, not the update source URL. |

## JSON Manifest Format

The update source returns a single JSON object. The current app prompts the user only when the manifest version is **strictly higher** than the local version; a lower or equal version is not shown as an update.

```json
{
  "version": "1.2.0",
  "releaseNotesURL": "https://example.com/termipad/releases/1.2.0"
}
```

There is currently no official update source to configure. The address should be filled in only when, in the future, an audited HTTPS private source that the user can identify exists. Even if the update check finds a higher version, the user must still review the release notes themselves and obtain the software through an explicit, separate distribution process.

## Relationship to Official Distribution

Developer ID signing, Hardened Runtime, notarization, ticket stapling, and Gatekeeper cold-start verification remain independent gates. This feature does not bypass, replace, or lower any distribution requirement.
