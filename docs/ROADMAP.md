# Belvedere roadmap

What is planned, what is open, and what is done, one line each. The reasoning, the
investigation and the decisions behind an item are in [FORK-NOTES.md](FORK-NOTES.md), under
*Item notes*, by the same ID. What a release says to readers is in `docs/release-notes/`.

IDs are permanent: **F** feature, **S** security, **H** housekeeping, **UF** an upstream
feature being watched, **UC** a contribution to upstream. A number is never reused or
changed. The release an item belongs to is a column, because a target slips and an ID must
not. Older notes use earlier numbering; the mapping is in FORK-NOTES, *ID mapping*.

## Plan

**2.0, in progress** on `feat/2.0.0`. Its scope is everything under *2.0* in Done below. Before it ships:

- Branch-wide security review of `v1.3.2..HEAD`.
- Hand tests: manual checklist sections 5e and 5f, and the ⌘N row.
- The build is universal and the minimum is macOS 26 (H10, H11). The x86_64 slice is built and checked for presence but has not been run; the maintainer will test it on an Intel Mac running macOS 26 before release (manual checklist, section 6). Rosetta is never used.
- `just release major`, then `just publish --go`. Each needs an explicit go-ahead.

**Next (2.1):** F19, F7 and S7 are the candidates. S7 matters most for the security posture; F19 has an open sandbox question to settle first.

**Unscheduled:** the ideas, upstream work and housekeeping under Open.

## Open

| ID | Item | Where it stands | Release |
|---|---|---|---|
| **F19** | Quick Look repair setting | A setting that checks Belvedere’s Quick Look extension is the one handling Markdown, and repairs it. Open question: can a sandboxed app do that at all. | 2.1 candidate |
| **F7** | ⌘R reload from disk | Revert to Saved is done; re-reading a file that has no local changes is not. | 2.1 candidate |
| **S7** | Trusted folders and bookmarks | Trust a folder, take a security-scoped bookmark, and drop the `/` read-only entitlement. | 2.1 candidate |
| **F22** | Mermaid size differs 1–4 px between reader and editor | Cause unproved. Ships as a known limitation in 2.0; the layout test allows 4 px after a diagram. | 2.0, known |
| **F12** | Reword the “Continue” button on leaving edit mode | Idea: the word does not say the changes stay unsaved. | — |
| **F13** | Edit as plain text | Idea: a plain-text edit mode for exact copy and paste. | — |
| **F14** | Drop a folder on a window or sidebar to open it | Works on the Dock icon only. | — |
| **F15** | Search the text of files across the opened folder | Idea, on ⇧⌘F, beside Go to File on ⇧⌘O. | — |
| **F18** | Stray whitespace after an italic table cell | Seen once while editing; not reproduced. | — |
| **UC1** | Offer click-to-load upstream | As its own PR, once the containment PR (#337) is resolved. | — |
| **UC2** | Pitch an optional network-egress block upstream | Low priority; the maintainer floated it. | — |
| **UF1** | Upstream render-extension registry (their PR 429) | Reviewed, not imported; revisit if it merges and is reviewed. | — |
| **H4** | Delete six old Belvedere releases on the tap repo | Due on or after 2026-10-28. | — |
| **H5** | Understand the Greptile comments on our upstream PRs | Not started. | — |
| **H6** | Two click-to-load test gaps | The `too large` label and duplicate references to one blocked file are untested. | — |

## Done

Newest release first.

### 2.0 (on `feat/2.0.0`, not yet released)

| ID | Item | Outcome |
|---|---|---|
| **F9** | Open Folder from inside the app | File ▸ Open Folder…, no shortcut; Dock drop; works with no window open. |
| **F17** | Tab in a table cell selects its contents | Tab, Shift-Tab and Enter select the next cell’s text. |
| **F20** | Search for Document is now Go to File… | In the Go menu, still ⇧⌘O. |
| **F23** | Full Width default, Quick Look Width, a width per window | Plus Single new lines (Reflow default), and the reader’s place kept on any re-render. |
| **F24** | English only | Chinese localization removed. |
| **F5** | Link destination bar | A native bar shows where the hovered link really goes. |
| **F6** | ⓘ callout for the outline-highlight setting | Labelled row, subtitle and popover in Settings. |
| **F10** | ⌘N opens a window, not a tab | Whatever the Prefer tabs setting says; ⌘T still opens a tab. |
| **F11** | ⌘O into a file that is already open | Decided: the window that has the file is raised; otherwise a new window. |
| **S8** | Each window has its own folder boundary | Audited, nothing shared; a test forbids a static boundary. |
| **H8** | Rename project, folders and keys to `belvedere` | `belvedere://`, `belvedere.*` settings keys, one-time key migration. |
| **H10** | Minimum macOS is 26 | Every `#available(macOS 26)` check and fallback removed: one code path for the window chrome. 26.1 and 27 checks stay. |
| **H11** | Universal build | Release builds carry arm64 and x86_64, and the build script checks both. |
| **F21** | Go to File matched scattered letters | A letter may sit at most three characters past the last, unless at a word start. |

### 1.3.2

| ID | Item | Outcome |
|---|---|---|
| **F8** | Wide tables squeezed to a letter per line | Regression from 1.3.0 fixed. |

### 1.3.1

| ID | Item | Outcome |
|---|---|---|
| **S3** | Leaving edit mode dropped the opened-folder boundary | Saving and leaving edit mode no longer reset the folder boundary. |
| **S4** | Boundary parameters defaulted to `nil` | Defaults removed, so a missing boundary is a build error. |
| **F4** | Dev builds say so in About | About shows `Version x (dev <commit>)` for non-release builds. |
| **S6** | Belvedere never writes inside an app bundle | `AppBundleWriteGuard` refuses any path inside a `*.app`. |
| **H7** | Sponsor material removed | Funding file, sponsor logos, Amore skill files and upstream logo deleted. |

### 1.3.0

| ID | Item | Outcome |
|---|---|---|
| **H3** | `brew uninstall --zap` left folders behind | Fixed in the tap: zap now covers the Quick Look, group and script folders. |

### 1.2.2

| ID | Item | Outcome |
|---|---|---|
| **S2** | A link could start a program | A clicked link naming an app, installer or executable is shown in Finder, never run. |

### 1.1.0

| ID | Item | Outcome |
|---|---|---|
| **F3** | Homebrew tap | Public `inquinity/homebrew-tap`; `brew install --cask inquinity/tap/belvedere`. |

### 1.0.6

| ID | Item | Outcome |
|---|---|---|
| **F1** | Product name and icon | Named Belvedere, new bundle identifier, Split Signal / Geometric B icon. |
| **S1** | CSP on the app preview page and editor | Content-security policy in place; math and editing verified. |
| **F2** | Click-to-load for deferred content | Out-of-boundary local images show a placeholder with Load; remote images are labelled only. |
| **H1** | Pass/fail criteria in manual-test files | `EXPECT` / `FAIL IF` notes in every fixture, plus the manual checklist. |
| **H2** | Application menu still said Markdown Preview | Renamed; Check for Updates and crash-report items removed. |

### No release (tooling, closed or resolved)

| ID | Item | Outcome |
|---|---|---|
| **H9** | Stray Belvedere builds in the application list | Dev builds go to `build.noindex`; `just clean-apps` unregisters strays. |
| **S5** | Launch arguments saved as shared settings | Not reproducible; closed. |
| **F16** | Table editing failures on macOS 27 | A test-harness fault, not an editor bug. |

### Earlier milestones

| # | Milestone | Status |
|---|---|---|
| **M0** | Repo setup: remotes, `rerere`, tracking scripts, notes | done |
| **M1** | Upstream contributions: advisory, CSP, URI allowlist | in progress; advisory filed, containment PR #337 open upstream |
| **M2** | Identity and release: team, bundle IDs, app group, release pipeline | done |
| **M2b** | New app icon | done |
| **M3** | Deprivileging: telemetry stubbed, Sparkle removed, `network.client` dropped | done |
| **M3b** | Quick Look CSP | done |
| **M4** | Containment: `md-asset:` confinement | shipping here; open upstream |
| **M5** | Distribution: notarized DMG, Homebrew tap | done |
