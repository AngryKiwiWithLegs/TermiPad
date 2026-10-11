# TermiPad UI/UX Follow-up Backlog

## Local Icon Library, Duplicate Prevention, and Manual Selection

**Status:** The phase-two local icon system is implemented in code; the stable baseline will be updated after one consolidated verification on real macOS.

The current tool icon strategy uses fixed local semantic mappings for known common CLIs; unrecognized tools fall back deterministically, based on their name, to a limited set of SF Symbol and gradient combinations. This design does not go online, does not read READMEs, does not use remote avatars, and does not let AI rewrite commands or freely generate brand graphics. It works as a safe early default, but combinations may repeat as the number of unknown tools grows.

This batch implements a persistable local icon identity and an icon picker without changing tool commands, source trust, or the launch flow. An unknown tool is assigned a local fallback combination only the first time its style is missing; combinations already assigned to existing tools do not change when tools are added.

| Item | Goal | Safety and acceptance boundary |
|---|---|---|
| Expand the local icon catalog | Categorized SF Symbols and a controlled palette now cover more CLI types | Uses only symbols and colors shipped with the app; downloads no brand avatars or remote images. |
| Avoid automatic icon duplicates | Assigned local combinations are now persisted for unknown tools; on a first collision an unused combination is assigned by deterministic rules | Assignment is based only on local tool identity; it records no command content, paths, API keys, or network metadata. |
| Manual icon picker | Users can now choose a symbol and color from the local icon catalog and can restore automatic selection | The user's choice takes priority over automatic assignment; it does not change the command, template, source, or working directory. |
| Local PNG override | Custom PNGs continue to keep the highest priority | Images are stored only in a locally controlled directory; backup, restore, and diagnostics still do not propagate local binaries or paths. |
| Accessibility names | Provide every icon with an accessibility label carrying the tool name and purpose | An icon must not be the only source of information about what a tool means. |

> This batch is a visual polish item, not part of any network discovery, install, or remote control capability. The stable baseline should be updated only after a separate code batch completes a static audit and one consolidated verification on real macOS.

## Phone Collaboration Research Pending

Connecting a phone to TermiPad is a separate remote-operation architecture topic. Any approach must uphold principles such as local pairing, revocable devices, least privilege, explicit user confirmation, never exposing the terminal directly to the public internet, and never letting remote metadata construct or rewrite commands on its own. See the later phone collaboration feasibility design for details.
