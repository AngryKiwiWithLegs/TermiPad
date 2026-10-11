# TermiPad: place-name version codename scheme

**Effective date:** 2026-08-25
**Applies to:** TermiPad's internal stable baselines, preview development lines, and future private beta candidates.

## 1. Naming principles

TermiPad stays the product name, private repository name, Swift module name, and current bundle identifier. Each generation of a **fully verified stable version** additionally gets a place-name codename, in the "product name + place name" style of classic macOS versions, instead of inventing a separate product name for every development branch.

> The format of a stable version name is: **TermiPad [place name]**.
>
> For example, the current baseline is **TermiPad Mendocino**.

The series uses **towns and bays of California's Pacific coast** as its theme. It fits the local, clear, explorable-but-not-overreaching experience the "terminal tool library" stands for, while avoiding macOS codenames Apple has already used publicly, such as Ventura, Sonoma, Monterey, Mojave, Catalina, Big Sur, Sequoia, or Yosemite.

The place-name codename does not replace the semantic version number. It is a human-readable generational identity; the semantic version, Git commit, and verification evidence remain the engineering source of truth.

## 2. Current stable version

The P0 + P1 baseline that has passed consolidated verification on real Apple Silicon macOS is named:

# TermiPad Mendocino

**Internal version identifier:** `1.0.0`

**Release channel:** Stable (private verified baseline)

**Code verification baseline:** `6a3bd11` (`Ensure UI tests create a main window`)

**Audit record:** `c361db3` (private beta verification audit update)

"Mendocino" stands for the first complete generation of the local-first tool library: the review inbox, conservative scanning, manual management, command templates, controlled terminal launching, GitHub/AI information boundaries, backup and isolated recovery, health checks, working directories, diagnostics, update notices, and consolidated real macOS verification.

**Stable** only means the baseline has completed the code and real macOS verification defined inside the project; it does not mean Developer ID, Hardened Runtime, notarization, Gatekeeper cold start, or external distribution acceptance are satisfied.

## 3. How P2 relates to stable codenames

A place name is upgraded only after a capability batch is finished, the code is frozen, and the full consolidated verification passes. P2 development must not use up the next stable place name early, so that feature experiments are not confused with a stable version one can fall back to.

| State | User-facing wording | Suggested semantic version | Git / engineering identifier | Meaning |
|---|---|---|---|---|
| Current stable baseline | **TermiPad Mendocino** | `1.0.0` | `termipad-mendocino-1.0.0` | The verified local P0 + P1 version; contains no P2 features |
| P2-A discovery development | **TermiPad Mendocino — Discovery Preview** | `1.1.0-preview.N` | `p2/discovery-preview` | Only manual discovery, cache, source evidence, and explainable ranking; installs no software |
| Next stable version after P2-A verification | **TermiPad Sausalito** | `2.0.0` | `termipad-sausalito-2.0.0` | The next stable generation after P2-A is complete and fully verified |
| P2-B install review development | **TermiPad Sausalito — Install Review Preview** | `2.1.0-preview.N` | `p2/install-review-preview` | Only develops the controlled install plan and review UI; does not yet mean a general one-click install |
| Next stable version after P2-B verification | **TermiPad Morro Bay** | `3.0.0` | `termipad-morro-bay-3.0.0` | Used only after install assistance through restricted channels completes security acceptance |
| Future read-only environment report | **TermiPad Avalon — Environment Preview** | `3.1.0-preview.N` | A separate future project | Only shows ecosystem and version state; no automatic upgrade, uninstall, or conflict resolution |

Every preview version must be clearly marked **Preview** in the product documentation and UI, and must be able to fall back to the previous stable codename at any time. A preview does not rewrite the stable version's backup format, data storage path, Keychain service, bundle identifier, or user commands.

## 4. Reserved codename pool

The following names are a candidate pool for later stable generations, not a committed order of features:

| Order | Place-name codename | Condition of use |
|---|---|---|
| 1 | **Mendocino** | The current verified stable P0 + P1 version |
| 2 | **Sausalito** | After the P2-A discovery capability is complete, frozen, and verified |
| 3 | **Morro Bay** | After P2-B controlled install assistance completes its separate security acceptance |
| 4 | **Avalon** | A later batch of new stable capabilities with clear, safe boundaries |
| 5 | **Solvang** | Future candidate; used only when the next stable generation is needed |
| 6 | **Arcata** | Future candidate; used only when the next stable generation is needed |

The names themselves do not indicate quality, security level, geographic origin, or cooperation with local institutions, nor are they a legal conclusion about trademark or domain availability. Before any future external distribution, the final name still needs a formal check at the trademark, domain, App Store, and local legal levels.

## 5. Adoption rules

From now on:

1. The verified stable baseline is uniformly called **TermiPad Mendocino**, not "Shelldex" or a generic "stable version".
2. During P2-A implementation use **TermiPad Mendocino — Discovery Preview**; it must not be described as the next stable version.
3. **TermiPad Sausalito** is used only when P2-A's scope, tests, and consolidated real macOS verification are all complete.
4. External distribution still needs to separately satisfy Developer ID, Hardened Runtime, notarization, Gatekeeper cold start, and real old-store upgrade verification; place-name codenames do not bypass these gates.
5. The technical name `TermiPad` and the existing local data identifiers are not changed at this stage, to protect the verified Mendocino baseline.
