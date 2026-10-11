# TermiPad P2: discovery, controlled install, and dependency governance design

**Status:** P2-A has passed real macOS verification; P2-B controlled install review and P2-C read-only environment report have entered the implementation batch and await consolidated real macOS verification. Automatic install, upgrade, uninstall, and cross-ecosystem dependency arbitration remain unimplemented.

**Scope:** A private native macOS Swift/SwiftUI app. This document splits the original plan's "GitHub trending project discovery, browsing, one-click install" and "dependency governance" into verifiable product phases; it never turns recommendation metadata, READMEs, AI output, or network responses directly into executable commands.

**Design date:** 2026-08-25.

> P2's goal is not to turn TermiPad into a package manager, but — without losing the core identity of "an icon launch library for directly interactive CLIs the user has installed" — to let users discover candidate projects, understand the impact of installing, and hand a reviewed install action to the terminal they chose.

## 1. Original intent and the new boundary

The original technical plan defined P2 as two follow-up capabilities: discovery and one-click install of trending new GitHub projects, and dependency conflict governance across npm, pip, Homebrew, and Cargo. It also stated explicitly that GitHub has no official Trending API and that one-click install of an unfamiliar project must first show a project summary and require user confirmation. That judgment is right, but it does not cover the supply-chain execution risk of the install stage.

The command objects of P0/P1 are **local interactive CLIs the user has installed and confirmed**. Once P2 can suggest or perform installs, four new responsibilities appear: TermiPad must explain the basis for a recommendation; must limit download and install sources; must show the user the file, network, dependency, and executable code impact of an install; and must avoid treating failures, same-named executables, or service-type components as launchable tools after installing.

| Dimension | Existing P0/P1 model | Model that must be added after P2 |
|---|---|---|
| Object | Locally installed executables | Remote discovery items, install candidates, install receipts, and version snapshots |
| Trust source | Local scan, conservative GitHub metadata | GitHub discovery, official package indexes / restricted install channels, user review |
| Risky action | After a user click, launching an already owned command in the terminal | After a user click, possibly downloading, unpacking, compiling, and executing third-party code |
| Done criterion | The candidate enters the inbox and the user confirms | Pre-install preview, explicit consent, terminal execution, independent local verification, then entering the review inbox |
| Responsibility boundary | Does not install third-party software | No silent installs; does not decide source, version, permissions, or dependency strategy for the user |

## 2. Recommended decision: "discover → review → controlled terminal install → verify and collect"

Making P2 a frictionless "one-click install" is not recommended. The product can keep a short entry label, but the real behavior should be **one reviewed terminal install**: the user first sees a non-editable but copyable install plan and the full command, then explicitly chooses "Copy command" or "Run in my chosen terminal". No network content may be concatenated directly into a shell command.

| Option | User experience and capability | Security and product trade-offs | Cost | Setup complexity |
|---|---|---|---|---|
| A. Discovery and browsing, no install | Shows candidates, evidence, and official links; after the user installs by themselves, the existing scan collects the tool | Lowest risk, but the path from discovery to use is longer | Low; only user-triggered public API queries | Low |
| B. Reviewed terminal install from restricted sources (**recommended**) | Support official Homebrew formulae first; after reading the plan the user copies it or hands it to the terminal, then rescans when done | Keeps the user in control and strictly limits install sources; does not try to solve every ecosystem uniformly | Low; no server and no background polling | Medium |
| C. Cross-ecosystem automatic install, automatic upgrade, and global dependency governance | Full coverage of npm, pip, Cargo, and Homebrew with automatic choice of isolation | Product promises and the attack surface expand sharply; needs environments, locking, rollback, authorization, logging, and long-term security response | High; needs ongoing compatibility and security maintenance | High |

**Current scope:** A is done; B's implementation is limited to statically reviewed Homebrew core formula install plans and an explicit terminal handoff; C's implementation is limited to a read-only environment report the user triggers manually. P2-B's product is "install assistance through a trusted channel", not a general software installer; P2-C still includes no automatic upgrade, uninstall, or cross-ecosystem conflict arbitration.

## 3. P2-A: trending discovery and candidate browsing

### 3.1 Product definition

Add a "Discover" page to the sidebar. It is neither the library nor an app store; its content is a set of **remote project candidates awaiting review**. Every card must clearly show: project name, repository owner, repository link, license information (if the API returns it), created / last pushed time, star count, fork count, whether it is a fork, whether it is archived, the reason for the recommendation, the data time, and the statement "this is not an official Trending ranking".

GitHub Search returns at most 1,000 results, sorted by a multi-factor "best match"; it is not an official trending list. P2 therefore must not use "official GitHub trending" or "Trending" as a factual label and should use "TermiPad discovery candidates (explainable ranking)". The search API may also return `incomplete_results`; when it does, that round's results must be marked incomplete instead of presenting the ranking as a stable fact.[1]

### 3.2 Explainable local heuristics

The first version does not use AI to rank projects and does not scrape arbitrary web pages. It builds a **transparent heuristic** only from fields the GitHub public repository API already provides and that can be shown and cached: recent activity, a proxy for star growth, topic tags, whether a license exists, non-fork, non-archived, and whether interactive CLI signals appear in the README/description. Any score is used only for local sorting and cannot be treated as a security rating or quality guarantee.

A recommendation must pass the following mandatory filters before it can be presented as "install channel to be checked": a public repository, non-archived, non-fork, with a clear project homepage or README, and without obvious signals of being service/daemon/library-first. Projects that cannot be judged can still be shown as "browse candidates", but with no install entry.

### 3.3 Network, cache, and privacy

P2-A is off by default; `api.github.com` is accessed only after the user manually clicks "Refresh Discovery". There is no always-on background monitoring and no daily automatic fetch, and the library, commands, paths, variable values, API key, or the user's GitHub identity are never uploaded. Anonymous public requests by default only suit low-frequency personal use; GitHub sets a general limit of 60 unauthenticated REST requests per IP per hour, and search has stricter dedicated limits.[2] The search endpoint currently allows 10 unauthenticated requests per minute and 30 authenticated requests per minute.[1]

The implementation must store locally the normalized request parameters, response time, ETag, `Last-Modified`, rate-limit headers, and the minimized display fields. Refreshes are strictly serial; on `429`, `403`, or `x-ratelimit-remaining: 0`, stop and back off per `Retry-After` or `x-ratelimit-reset`. GitHub explicitly recommends avoiding polling, avoiding concurrent requests, and using conditional requests and `304 Not Modified` to cache results.[3] If the user later chooses to connect their own GitHub account, the token is stored only in the Keychain, with minimal scopes and only to raise the rate limit; P2-A does not need that token to work.

### 3.4 Non-goals of P2-A

P2-A does not fetch GitHub owner avatars, does not extract executable commands from READMEs, does not accept candidates automatically, does not treat the star count as a security score, does not run install check commands, does not open third-party web pages, and does not create background sync tasks.

## 4. P2-B: controlled terminal install assistance

### 4.1 The only supported channel in the first version: official Homebrew formulae

P2-B supports only a Homebrew that already exists on the user's machine, and only **official formulae from `homebrew/core`**. It does not install Homebrew itself; does not run `curl | sh`; and does not support casks, unofficial taps, tap URLs, Git URLs, `--HEAD`, local paths, `sudo`, environment variable prefixes, pipes, redirection, command substitution, or chained commands.

Choosing Homebrew formulae is scope control, not an absolute promise about software safety. Homebrew's official core channel lowers supply-chain risk through maintainer review, checksums in reviewed metadata, a signed JSON API, and official bottle builds; the official documentation also stresses that third-party taps are executable code and should not be trusted by default.[4] For casks, Homebrew states that they usually install upstream precompiled apps directly, with a weaker trust model than core formulae; so casks are not in the first version of P2-B.[4]

If Homebrew does not exist, its version cannot be read, or the channel is not official core, the UI shows only the install conditions and "Copy link to official instructions"; it never installs the package manager on the user's behalf. Homebrew itself also requires the user to confirm what its install script will do before running it.[5]

### 4.2 An install plan, not a remote command

There must be no "README command mapping" between remote discovery items and install channels. An installable project must go through a locally signed / shipped-with-the-app `InstallCatalog` mapping that contains at least: the stable GitHub repository ID, the allowed Homebrew formula name, the set of expected CLI executable names, the allowed architectures, a license note, the mapping review version, and the review time. Mapping records can only be changed by official TermiPad updates; the GitHub API, AI, READMEs, search titles, and web content cannot create or modify them.

After the user chooses "Review install", the app presents the following as a read-only `InstallPlan`:

| Required field | Purpose |
|---|---|
| Repository, Homebrew core formula, mapping review time | Lets the user tell the discovery source from the actual install source |
| Exact version / available version, target architecture, expected binaries | Avoids near-miss names or unexpected binaries |
| Full fixed command | The user can copy it, read it, and double-check it in an external terminal |
| Impact notice | May download, write to the Homebrew prefix, resolve dependencies, and run package-manager steps |
| Limits of trust | States explicitly that "an official channel / checksum does not mean free of malice or right for your environment" |
| Installed / conflict / unknown state | Read-only pre-check result; an unknown state forbids default execution |
| Cancel and copy paths | Copy is always available, and cancel leaves no install state behind |

The install command is compiled from a local tokenized recipe; the first version allows only argument sequences equivalent to `brew install --formula <approved-formula>`. The compiler must not accept a piece of free text; the formula name is checked by both a strict regex and an allowlist, and before execution the tokens are re-serialized into the displayed text. Any input that does not fit the syntax or contains newlines or shell metacharacters must be rejected and written to local diagnostics containing only the fixed event category.

### 4.3 User confirmation, the terminal boundary, and collection

The default primary button is "Copy install command". "Run in terminal" becomes available only after the user checks "I reviewed the full command and its impact", and the button shows the actual formula name. TermiPad still hands the command to the Terminal.app, iTerm, Warp, or copy target the user chose in Settings; it never runs the package manager directly in the app process, requests admin privileges, enters passwords, bypasses terminal Automation authorization, or hides output.

A terminal returning does not mean success. Back in TermiPad the user must deliberately click "Verify and scan"; the app only does the existing local PATH / restricted directory scan, health check, and review inbox flow. A library record is created only when an expected executable allowed by `InstallCatalog` is found and the user confirms. Install failures, extra files, service-type components, same-named files at mismatched paths, or scan uncertainty must never lead to automatic collection.

### 4.4 Install records, uninstall, and privacy

The local `InstallReceipt` stores only: channel, catalog ID, formula, user confirmation time, plan version, the verification result enum, and the tool ID the user linked manually. It does not store full terminal output, the Homebrew prefix, absolute paths, environment variables, download URLs, command history, or user directories. The default JSON backup contains no receipts; diagnostics record only fixed categories such as install plan opened / copied / handed to terminal / verification succeeded or failed.

P2-B offers no "one-click uninstall" or "rollback". Uninstalling, like upgrading, can affect other tools; it can be discussed only after a future controlled version governance design provides dependency impact preview, explicit confirmation, failure recovery, and an evidence model.

## 5. P2-C: splitting dependency and version governance correctly

"Preventing duplicate installs and version conflicts and automatically choosing the most suitable isolation" is not a general cross-ecosystem operation. Package managers differ in sources, dependency resolution, install locations, lifecycle scripts, lock files, and rollback ability. So P2-C cannot start from "automatic arbitration"; it can only start from a **read-only inventory and local pre-checks**.

| Ecosystem | Known risks / semantics | Actions P2 allows | Actions forbidden in the first P2 version |
|---|---|---|---|
| Homebrew core formula | Official core has review and checksum mechanisms, but installing still changes the user's prefix and dependency set | Detect installed state, read-only `info` / version summary, single-formula install plan | Third-party taps, casks, uninstall, upgrade, `--HEAD`, automatic dependency repair |
| npm | `npm install`/`npm ci` can run lifecycle scripts such as `preinstall`, `install`, `postinstall`, and `prepare`.[6] | Only show ecosystem risks and a copyable command during the P2-C research period | Automatic / terminal-executed global npm installs, Git URLs, promises to bypass lifecycle scripts |
| pip | By default it does not protect against remote tampering and may run arbitrary code from distributions; the secure mode requires local hashes, pinning of all dependencies, and in common cases a binary-only policy.[7] | Only show environment detection, a virtual environment suggestion, and a copyable command | Modifying the system Python, `--break-system-packages`, automatically creating/choosing environments, unlocked installs |
| Cargo | `cargo install` may re-resolve dependencies by default; only `--locked` uses the lockfile shipped with the package.[8] | Read-only listing of install records and versions; later, previewing a pinned crate plan | Git sources, floating branch/tag references, automatically falling back to an install without a lockfile |

P2-C's first deliverable should be an "environment and install source report": per tool, show the detected package manager, the install location category, the known version, whether it is linked to a TermiPad receipt, whether it can be checked safely, and the reason it "needs the user to handle it in the terminal". It must not try to solve dependency trees across Homebrew/npm/pip/Cargo, nor automatically interpret "a newer version" as "should upgrade".

pip itself states that the install process selects dependencies and may build wheels; it offers `--dry-run --report` to produce a JSON resolution report, but failure recovery is not something it promises.[9] Cargo also states that the cost of `--locked` is not getting dependency fixes or updates.[8] These differences show that TermiPad can at most present the plans and evidence each ecosystem gives, and cannot claim to have computed a general "optimal isolation / conflict-free solution".

## 2026-08-25: current implementation boundary of P2-B / P2-C

This batch realizes the original plan's "one-click install" as **controlled install review**, and "dependency and version governance" as a **read-only environment report**. Both aim to add visible information and user confirmation, and do not move package-manager downloads, script execution, upgrades, uninstalls, or conflict arbitration into TermiPad.

| Capability | Current implementation boundary | Explicit non-goals |
|---|---|---|
| P2-B controlled install review | A statically reviewed catalog shipped with the app; matches only the exact full GitHub repository names listed; currently generates only Homebrew core formula plans with a fixed `brew install <formula>`; shows the channel, repository, expected CLI, catalog revision, review date, and full command; the plan can be handed to the user's chosen terminal only after they explicitly check that they reviewed it. | Does not read README install instructions; accepts no remote commands; no third-party taps, casks, URLs, Git repositories, or npm/pip/Cargo installs; no in-app execution; does not wait for the install result; no automatic collection. |
| P2-C read-only environment report | Only after the user clicks does it check Homebrew, Cargo, npm, pnpm, Bun, and Python at fixed absolute paths; each path only runs `--version`, and the output is kept only on the current page. | Does not enumerate PATH; runs no shell; uses no user-supplied paths or arguments; no network; no install, upgrade, uninstall, or repair; saves no paths, versions, or reports. |

> Even if the user hands a plan to the terminal, the later download and execution are still reviewed by the user in the terminal and package manager they chose. TermiPad does not interpret "command handed off" as "install succeeded", and never writes any executable into the library automatically. To collect a new CLI, the user must still run a local scan and confirm explicitly in the review inbox.

Diagnostics add only four fixed event categories: environment report requested, install plan viewed, install plan handed off, install plan handoff failed. Diagnostics never record the formula, repository name, command, path, or version text.

## 6. Attack surface and mandatory controls

| New attack surface | Typical failure mode | P2's mandatory control | Residual risk and user notice |
|---|---|---|---|
| Manipulated popularity ranking | Stars, forks, or descriptions are manipulated | Transparent heuristics, the unofficial ranking label, source fields, and timestamps | Popularity does not mean safety, maintenance quality, or suitability |
| Same-named / look-alike projects | Typosquatting, slopsquatting, impersonating repositories | Discovery and the install catalog are separate; installs allow only stable repository ID mappings | The user still needs to read the project and channel information |
| README / AI prompt injection | Remote text induces command execution | README/AI never generate install recipes; AI cannot change commands | Remote descriptions are reference content only |
| Repository takeover or release change | Content is swapped after a project was discovered | Use the reviewed catalog, show the review time, re-verify the channel | Official channels and signatures lower the risk but do not guarantee the absence of malice |
| Code execution during download/build | Package lifecycle, compilation, post-install | P2-B is Homebrew core formulae only; npm/pip/Cargo are not executed | Even after channel review, installing may still execute third-party code |
| Third-party tap/registry mixed in | Loading executable recipes or dependency confusion | Unofficial taps, replaced registries, Git URLs, and extra indexes are forbidden | Any future extension must set a separate per-ecosystem policy |
| Shell injection | Network fields reach the shell, arguments are concatenated | Token recipes, allowlist, rejection of metacharacters, no free-text commands | Existing user-defined launch commands remain the user's responsibility |
| Privilege escalation | `sudo`, password entry, writes to system directories | Recipes forbid `sudo`; the app never reads or enters passwords | The user can do privileged operations in an external terminal themselves; TermiPad does not assist |
| PATH / binary confusion | A same-named executable is collected by mistake | Expected executable allowlist, health check, review inbox | When uncertain, keep it pending and do not add it automatically |
| Privacy expansion | The library, tokens, or paths are sent in the background | Off by default, manual refresh only, minimal field cache, Keychain, no path/command logs | GitHub can still see the request IP and the public query |
| API rate limiting / unavailability | A refresh triggers rate limiting or error retries | Serial requests, ETag, backoff, cache fallback, no automatic retry storms | Discovery may be temporarily unavailable without affecting the local library |

## 7. Suggested data and module boundaries

P2 should add separate modules and never stuff remote candidates directly into `TerminalTool`:

```text
DiscoveryService          only fetches and caches remote DTOs; produces no commands
DiscoveryRanking          only does explainable ranking; no security rating
InstallCatalog            the reviewed mapping shipped with the app; remote data cannot modify it
InstallPolicy             pure-function policy for channels, arguments, versions, permissions, and forbidden syntax
InstallPlanCompiler       generates the read-only install plan from tokenized recipes
InstallReviewView         shows evidence, impact, the exact command, and explicit confirmation
TerminalLauncher          reuses the existing user-chosen terminal / copy boundary, with no added privileges
InstallVerifier           reuses the scan, health check, and review inbox; never collects directly from a terminal exit code
EnvironmentReportService  read-only ecosystem detection and version snapshot, no automatic repair
```

The suggested core models are `DiscoveryItem`, `DiscoveryEvidence`, `CatalogEntry`, `InstallRecipe`, `InstallPlan`, `InstallReceipt`, `EnvironmentSnapshot`, and `VerificationResult`. `CatalogEntry` and `InstallRecipe` must be static data that ships with the app version and is auditable and unit-testable; `DiscoveryItem` is expirable cache data; `InstallReceipt` is stored only on this Mac and stays out of backups by default.

## 8. Implementation phases, acceptance, and exit conditions

| Phase | Deliverable | Security acceptance that must pass | What it does not do |
|---|---|---|---|
| P2-A0: policy and test skeleton | Data model, cache, rate limiting, ranking explanation, network switch | All networking off by default; degrades gracefully without a token; every API error and rate limit is testable | Shows no install button |
| P2-A1: discovery browsing | Manual refresh, cache, source evidence, the unofficial ranking notice, copy/open link | ETag/backoff, avatars forbidden, README commands forbidden, incomplete-result marker, privacy diagnostics audit | No automatic refresh or recommending into the library |
| P2-B0: install plan | Static Homebrew core catalog, pre-check, command compilation, review UI | Policy fuzz/unit tests reject all shell metacharacters, taps, URLs, `sudo`, and unknown formulae; plan snapshot tests | Does not actually run an install |
| P2-B1: controlled terminal handoff | Copy first, terminal handoff after explicit confirmation, install receipt, rescan | Copy fallback when Automation is denied; no automatic collection from a terminal exit code; UI/unit tests cover cancel, failure, and same-name conflicts | Does not install Homebrew, uninstall, or upgrade |
| P2-C0: read-only environment report | Homebrew/npm/pip/Cargo detection, version and source report | Runs no install/upgrade; does not write to the user's environment; output contains no paths, commands, or tokens | Does not resolve dependency or version conflicts automatically |
| P2-C1: research on controlled single-ecosystem upgrades | A separate project only after signed releases and trials with real users | A separate threat model per ecosystem, with rollback, conflict, and failure recovery verification | No unified cross-ecosystem solver |

Every phase should extend the static policy guards in `scripts/verify-macos.sh`, the Swift unit tests, the native Xcode build, and the UI smoke tests. P2-B/C change the user trust model to "a click may lead to third-party code being installed", so before external distribution, Developer ID, Hardened Runtime, notarization, Gatekeeper cold start, and real old-store upgrade verification must also be completed; these existing external gates do not go away because of the P2 design.

## 9. Recommended first development batch

Once implementation is approved, only **P2-A0 + P2-A1** should start. This gives the product the value of "discovering new CLIs" without changing the P0/P1 boundary of "launch commands run only for installed tools". After it is done and passes consolidated real macOS verification, the user decides whether to open P2-B0's Homebrew install plan; that phase still runs no install.

P2-B1 needs a separate product confirmation, because it is the first time TermiPad extends from a "launcher" to "an assistant that hands install commands to the terminal". It should be implemented only after the user explicitly accepts the source restrictions above and confirms the experience and diagnostics boundaries.

## References

[1]: https://docs.github.com/en/rest/search/search?apiVersion=2026-03-10 "GitHub: REST API search endpoints"
[2]: https://docs.github.com/en/rest/using-the-rest-api/rate-limits-for-the-rest-api "GitHub: REST API rate limits"
[3]: https://docs.github.com/en/rest/using-the-rest-api/best-practices-for-using-the-rest-api?apiVersion=2026-03-10 "GitHub: REST API best practices"
[4]: https://docs.brew.sh/Homebrew-Security-and-Supply-Chain "Homebrew: Security and supply chain"
[5]: https://docs.brew.sh/Installation "Homebrew: Installation"
[6]: https://docs.npmjs.com/cli/v11/using-npm/scripts/ "npm: Scripts and lifecycle events"
[7]: https://pip.pypa.io/en/stable/topics/secure-installs/ "pip: Secure installs"
[8]: https://doc.rust-lang.org/cargo/commands/cargo-install.html "Cargo Book: cargo install"
[9]: https://pip.pypa.io/en/stable/cli/pip_install/ "pip: pip install"


## Implementation status — 2026-08-25

**TermiPad Mendocino — Discovery Preview** has started implementing the local code batch for P2-A0 and P2-A1. The batch covers only the fixed public GitHub query, manual refresh, ETag conditional caching, serial requests, rate-limit information, non-fork / non-archived filtering, explainable ranking, the local cache, a bilingual preview UI, an off-by-default settings switch, and the corresponding unit/UI regression tests.

This batch contains **no** install, uninstall, upgrade, Homebrew invocation, npm/pip/Cargo invocation, command generation, terminal handoff, automatic collection, README scraping, AI ranking, GitHub identity connection, or background refresh. Remote items are not written to the SwiftData library, the review inbox, JSON backups, or the privacy-preserving diagnostic package. After implementation, the full consolidated verification must still be run in a real macOS environment before this batch can be marked as passed.
