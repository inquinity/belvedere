# Fork notes

This repository is a fork of [pluk-inc/markdown-preview](https://github.com/pluk-inc/markdown-preview),
maintained by [inquinity](https://github.com/inquinity). It exists for one reason:

> **The upstream app makes outbound network connections that are not acceptable on a
> corporate network.** This fork removes them. It does not add features.

Everything else — reading, printing, PDF export, Quick Look — is upstream's work and
should stay upstream's work.

## Relationship to upstream

| Remote | URL | Role |
|---|---|---|
| `origin` | `inquinity/belvedere` | This fork. Where our `main` lives. |
| `upstream` | `pluk-inc/markdown-preview` | The base project. Read-only; never pushed to. |

Upstream is actively maintained (142 commits in the two months before this fork was
cut), so staying close to it is worth real effort. Every change here is shaped to keep
merges cheap.

## What upstream sends over the network

Recorded here because it is the whole reason for the fork:

| Component | Destination | Upstream default | Here |
|---|---|---|---|
| Sentry crash reporting | `sentry.io` (org `pluk-inc`) | on | stubbed |
| PostHog usage analytics | `us.i.posthog.com` | on — opt-out, not opt-in | stubbed |
| Sparkle auto-updater | `release.md-preview.app` | on, automatic checks | excised |

None of these are wrong for a consumer app. They are simply incompatible with
our use.

**The guarantee is that the code is gone — not that the sandbox forbids it.**

An earlier version of this document claimed both. That was wrong, and the
correction matters: `com.apple.security.network.client` was removed from both
targets in M3, and **both surfaces rendered blank**. A sandboxed app cannot
complete a WKWebView load without that entitlement. It is not about `md-asset:`
subresources — the Quick Look extension inlines everything and failed the same
way — WebKit routes every resource load through its networking process, and the
sandbox gates that on this entitlement.

So the entitlement is back on both targets and cannot be removed. What holds:

| Claim | Enforced by |
|---|---|
| The app never contacts a server on its own | The code is gone — see the stubbed reporters and the excised updater, guarded by `ForkPostureTests` |
| A previewed document cannot phone home in Quick Look | `QuickLookContentPolicy`, a CSP in the page |
| A previewed document cannot phone home in the app window or the editor | `PreviewContentPolicy`, a CSP in the page |

Verify empirically rather than by reading entitlements, which is what misled us:

```bash
sudo lsof -i -a -p $(pgrep -f "Belvedere") -r 2
```

## Branch model

```
upstream/main          remote-tracking only; never a local branch we edit
main         (origin)  our product line: upstream + our changes
fork/<topic>           short-lived; merged with --no-ff, then deleted
contrib/<topic>        cut from upstream/main; ONE fix each; for PRs to pluk-inc
```

`contrib/*` branches are cut fresh from `upstream/main` and contain only the fix being
offered — never our deprivileging — so the PR diff is exactly what upstream is being
asked to review.

### Syncing with upstream

```bash
./bin/check-upstream.sh              # read-only: has upstream moved?
git fetch upstream
git merge upstream/main              # merge, never rebase
```

Before merging, read `docs/Upstream-Changed.md`: it lists every upstream change
Belvedere took with changes or declined, and what keeps each decision in place. After
merging, add a section there for this sync — what was reshaped, declined or kept
ours, and why. Release notes say what changed for readers; that file says what was
decided.

**Merge, never rebase.** `main` is published and others may build from it; rebasing
means force-pushing over history they hold. `git rerere` is enabled in this clone so
each conflict resolution is recorded once and replayed on later merges — if you clone
fresh, re-enable it:

```bash
git config rerere.enabled true
git config rerere.autoupdate true
```

### Merge commit convention

Two kinds of merge land on `main`. Prefix them so the audit trail stays readable:

```
Fork: remove Sentry and PostHog telemetry
Sync: upstream/main @ a1b2c3d
```

`git log --merges --grep='^Fork:'` is then a complete changelog of everything we have
done to the base project.

### Reviewing what this fork changes

```bash
./bin/show-private-changes.sh --stat     # summary
./bin/show-private-changes.sh            # full diff
./bin/show-private-changes.sh --commits  # commit log
```

This is the authoritative answer, independent of branch structure. Both scripts are
ported from the maintainer's earlier fork of MDviewer.

## How changes are applied

Upstream churns `belvedere/App/AppDelegate.swift` (1,276 lines) and
`belvedere/Features/Settings/SettingsModel.swift` heavily. A naive removal would edit
both in six places and conflict on every sync. So each change picks the approach with
the smallest permanent conflict surface:

| Component | Approach | Why |
|---|---|---|
| Sentry | **Stub** — keep `CrashReporter.swift` and its `isEnabled` / `start()` signatures, drop `import Sentry`, empty the bodies | All four `AppDelegate` call sites and three `SettingsModel` call sites keep compiling untouched |
| PostHog | **Stub** — same for `UsageAnalyticsReporter`; `isEnabled` returns `false`, writes ignored | Same |
| CLI installer | **Orphan** — remove only the menu item registration and the entitlements; leave the now-unreachable installer code in place | Costs one line instead of four blocks in `AppDelegate` |
| Sparkle | **Excise** | `SPUStandardUpdaterController` / `SPUUpdater` are concrete types with KVO observers bound to them; faking them is more fragile than deleting. The plist keys and `mach-lookup` entitlements have to change regardless. |
| Reopen snapshots (upstream 0.0.63) | **Excise** — delete `DocumentSnapshotCache.swift` and its call sites in `ContentViewController`, `MainSplitViewController`, `DocumentWindowController` and `MarkdownDocument`; keep the spare reader and the no-user-fonts change from the same upstream commit | It wrote a PNG of each opened document's first screen to the app's Caches, up to 40, never removed when the document closed or was deleted — a plaintext copy of exactly the plain notes most likely to be private. An off switch would still ship the code; the maintainer called the code itself a liability. Expect conflicts on syncs that touch those files; keep it out, and `ForkPostureTests` fails if it returns |
| What's New window (upstream 0.0.63) | **Deleted 2026-10-01** — `Features/WhatsNew/`, its strings and its tests are gone; the launch hook and Help-menu item were removed at the sync | It describes Markdown Preview's releases, links to upstream's GitHub, and compares upstream's build numbers (66+) with ours (13+), so it would open for every Belvedere user on every upstream bump. `ForkPostureTests` fails if anything presents it |
| Strict line breaks (upstream 0.0.63) | **Reshape** — keep upstream's setting and renderer; replace its toggle in `GeneralSettingsView` with a *Line breaks* popup (*Keep as typed* / *Join into paragraphs*) and an ⓘ popover from the fork's `InfoPopoverButton` | "Strict" reads as the opposite of what it does. Same stored key, so Quick Look and upstream's rendering are untouched; only one row of an upstream pane differs |
| Performance CI workflows (upstream 0.0.59–0.0.62) | **Delete** `.github/workflows/performance*.yml`; keep `scripts/bench` and `tests/performance` | The fork does not use upstream's benchmark reporting, and the workflows would run on macOS runners for every push and post PR comments with write scope. Re-delete if a sync brings them back |

**There is deliberately dead code in this fork.** The CLI installer in `AppDelegate.swift`
and the emptied reporter bodies are intentional — they are load-bearing for cheap merges,
not oversights. Do not "clean them up."

The same logic gives the general rule:

> **New files are free. Edits to upstream-maintained files are rent.**

Prefer adding a new file over editing an existing one. That is why the internal install
guide lives in `docs/INTERNAL-INSTALL.md` rather than in `README.md`.

## Upstream contribution track

Not everything here is fork-only. Genuine hardening goes back to upstream, because once
merged it stops being our diff to carry:

| Finding | Form | Status |
|---|---|---|
| `md-asset:` scheme has no path containment (`MarkdownAssetResolution.swift:49`) | Advisory → PR | **accepted**; [GHSA-vgmc-h5g6-xh2q](https://github.com/pluk-inc/markdown-preview/security/advisories/GHSA-vgmc-h5g6-xh2q). Maintainer asked us to write the fix — [PR #337](https://github.com/pluk-inc/markdown-preview/pull/337) open, **changes requested** 2026-09-06: bound by an explicitly opened project folder, treat link clicks separately from asset loads, and no silent no-ops. **Reworked and pushed 2026-09-11** (`a18b235`…`d8cf9f3`), taking the maintainer's shape rather than our layered proposal: the boundary follows an explicitly opened folder, clicks are handled apart from asset loads, and a program named by a link is shown rather than run. **Click-to-load is deliberately not part of it** — tested and shipping here, and offered as its own PR as soon as #337 is completed (row below). **Updated 2026-09-11:** upstream's link context menu (`7ce6cd5`) also resolves `md-asset:` links, and once GitHub's *Update branch* merged it in, the PR branch no longer compiled — its CI builds only the test package, so the check stayed green. The menu now passes the document folder the same way the click path does, matching the fix on our `main`; app built and the menu retested |
| Preview document has no Content-Security-Policy | Issue → PR | **closed** 2026-09-15 by the maintainer — [issue #339](https://github.com/pluk-inc/markdown-preview/issues/339) led to [PR #399](https://github.com/pluk-inc/markdown-preview/pull/399), with both working policies attached. Declined: *"we want to preserve remote-image support, so we're going to close this PR. We may revisit an optional privacy setting or a narrower CSP separately."* No consequence for us — `PreviewContentPolicy` and `QuickLookContentPolicy` (table above) stay a fork-only patch, same as before the PR; nothing changes on the next `git merge upstream/main`. Worth re-offering as the optional setting they named, if one gets built |
| `ALLOWED_URI_REGEXP` permits `http`/`https` | Issue → PR, after the CSP lands | **stalled** — premise was landing behind #399; with that closed, revisit as its own issue instead of waiting on a CSP that isn't coming |
| DOMPurify's KEEP_CONTENT lets form controls survive a forbidden `<form>` | PR | **closed** 2026-09-15 by the maintainer — [PR #369](https://github.com/pluk-inc/markdown-preview/pull/369). Declined: *"I've decided to keep the current sanitized HTML behavior. The example doesn't demonstrate credential submission, and I don't think we need the additional restrictions on visible controls for this app."* Reported publicly rather than by advisory: no exfiltration path, patch attached, and the analysis was already public in this fork's history. Both review findings were correct; see *The Mermaid HUD regression* below. No consequence for us — stays a fork-only patch, nothing to reconcile on the next sync |
| Documentation that describes behaviour goes stale silently | Practice → PR | ✅ **merged** — [PR #368](https://github.com/pluk-inc/markdown-preview/pull/368) landed as `e1c5c15`, in upstream 0.0.56. Their own `README.md` Mermaid claim is the motivating example: it concealed #338 for several releases |
| App icon too similar to macOS Preview (upstream's own issue) | Artwork offer | **posted** — concept board added to [#276](https://github.com/pluk-inc/markdown-preview/issues/276) on 2026-09-04. Their issue, opened by a user and endorsed by the maintainer, who said he is considering a rename and a distinct identity. Awaiting a pick |
| Mermaid diagrams do not render in Quick Look, though `README.md` says they do | Issue → PR | ✅ **merged** — [PR #343](https://github.com/pluk-inc/markdown-preview/pull/343) landed as `eddc0d0` and shipped in upstream 0.0.53; [#338](https://github.com/pluk-inc/markdown-preview/issues/338) closed. Their version replaced ours on the next sync |
| No Save button; leaving edit mode silently keeps unsaved edits; Save As… and Revert to Saved always disabled | Feature request → PR | **closed without merging, 2026-10-01** — [issue #378](https://github.com/pluk-inc/markdown-preview/issues/378), [PR #379](https://github.com/pluk-inc/markdown-preview/pull/379). The maintainer closed it because he does not want users asked to confirm when they change the edit mode, since they may want to see how a change looks before saving. It stays in Belvedere as our own feature, including the Save / Revert… / Continue prompt, which works well in use; nothing more goes upstream. Before it closed: Review asked for Save to stay out of the default toolbar and be icon-only; both done on the PR branch. **Belvedere deliberately differs on the first:** Save stays in our default toolbar (one identifier in `toolbarDefaultItemIdentifiers`), placed after Edit so it does not sit beside Share, whose icon is its mirror image; we take only the icon-only change. The one-time insertion into existing toolbars is not restored — everyone on 1.2.0 or later already had Save added by it. Merged into our `main` from the PR branch itself, after syncing with upstream, so the next sync sees the same commit on both sides |
| The Quick Look preview steals keyboard focus, so arrow keys scroll the document instead of moving the Finder selection | Issue → PR | ✅ **merged** — upstream's own issue [#292](https://github.com/pluk-inc/markdown-preview/issues/292), [PR #370](https://github.com/pluk-inc/markdown-preview/pull/370) landed as `d09f500`, in upstream 0.0.58. Review found ⌘A / ⌘C no longer work without a click, which the PR had claimed they did: key events reach the extension only while its view has focus, and not taking focus is the fix. Accepted as the trade and documented on the PR branch. Same patch we'd carried here since 2026-09-11, so the sync sees it as already applied |
| Mermaid diagrams draw at 0 × 0 in the app window since upstream made the article a flex column (#376) | Issue → PR | **merged upstream** — [issue #387](https://github.com/pluk-inc/markdown-preview/issues/387), [PR #388](https://github.com/pluk-inc/markdown-preview/pull/388), in Markdown Preview 0.0.57; our carried copy was superseded by the upstream sync. Shipped broken in our 1.2.0; the manual checklist caught it, the automated tests did not, because the width-toggle test's checks held for a 0-wide figure. The PR pins the size. Merged into our `main` from the PR branch |
| A blocked image is a silent broken image, with no way to see it | PR, after #337 | **planned** — click-to-load: the image renders as a placeholder naming the file, with Load and Load all; only real images are loaded, after the click, and nothing is remembered; Quick Look gets labels only. Tested and shipping here. Kept out of #337 so it does not hold up the security fix, and opened as its own PR as soon as #337 is completed. It must first follow the reworked boundary — the opened project folder, not the document folder — or it would offer Load for images that are now inside |
| A link could start a program (app, script, installer, disk image) with one click, once containment let the click through | PR | **submitted** — [PR #405](https://github.com/pluk-inc/markdown-preview/pull/405), open. Split out of #337 per review; independent of the containment rework, so it applies against `main` as it stands today rather than waiting on #337 to merge. Same fix as ships here (legacy F12, under Done in the backlog), tested on a plain Markdown Preview build with Sentry/Sparkle disabled locally |

The `md-asset:` finding goes through GitHub's private vulnerability reporting (enabled
on upstream), **not** a public issue: it describes an unfixed weakness in a shipping app
with real users.

Nothing about removing telemetry, Sparkle, or the CLI installer is offered upstream.
Those are product decisions, not defects, and filing them would be noise.

### Localization: English only from 2.0

Belvedere ships in English only. The `zh-Hans` bundles (`Localizable.strings` and
`MainMenu.strings`) were removed on 2026-10-05: upstream's translations came with the fork,
the strings added here were written without a native reader and never checked, and nobody
here reads Chinese or will keep them current. A half-translated interface (new keys falling
back to English beside old Chinese ones) is worse than a consistent one, so the language was
dropped rather than frozen. Readers whose system language is Chinese now see English.

To bring it back, the files are in git history (`git log --diff-filter=D --
belvedere/zh-Hans.lproj`); restore them, add `zh-Hans` to the project's known regions and
the variant group in `project.pbxproj`, and expect every key added since to be missing.
Menu lookups in `AppDelegate.swift` match English titles only. A future translation should
be added by someone who will maintain it.

## Roadmap

| # | Milestone | Contents | Status |
|---|---|---|---|
| **M0** | Repo setup | Remotes, `rerere`, tracking scripts, this document, FORK STATUS blocks | ✅ done |
| **M1** | Upstream contributions | Advisory + CSP issue/PR + URI allowlist issue/PR | **in progress** — advisory filed |
| **M2** | Identity & release | Team ID, four bundle IDs, app group, display names; replace the Amore release pipeline; rewrite `CLAUDE.md` / `AGENTS.md` | ✅ done |
| **M3** | Deprivileging | Stub Sentry + PostHog; excise Sparkle; orphan CLI installer; collapse Privacy pane; drop `network.client` and test Quick Look | ✅ done |
| **M3b** | *Conditional* | Quick Look CSP — the extension does need `network.client`, so the page blocks remote content instead | ✅ done |
| **M4** | Containment | `md-asset:` confinement — submitted upstream as [PR #337](https://github.com/pluk-inc/markdown-preview/pull/337) and **carried on this fork ahead of that merge** (cherry-pick of `cb6ae07`) | ✅ shipping here; still open upstream — see below |
| **M2b** | Rebranding | Replace the app icon | ✅ done — Split Signal / Geometric B, regenerate with `swift bin/make-icon.swift --install-mdview` |
| **M5** | Distribution | Notarize (✅ `dist/Belvedere 1.1.0.dmg`), verify on a second Mac (✅ passed on an earlier build), distribute via the public Homebrew tap (✅ `inquinity/homebrew-tap`, from 1.1.0); corporate share / Dropbox stays as a fallback | ✅ done |

## Backlog

Every item has one permanent ID: a type letter and a number. **F** feature, **S** security,
**H** housekeeping, **UF** an upstream feature Belvedere is watching or deciding on, **UC** a
contribution to upstream. Numbers run in one sequence per type, shipped items first and then
open ones, and are **never reused or changed**. The release an item belongs to is a column,
not part of the ID, because a target slips and an ID must not. A shipped item records the
release it shipped in; an item with no release yet shows `—`.

IDs were reset twice before this scheme: the original `F`-numbers (*legacy*) and a
2026-09-30 renumber. The mapping table below carries both, so references in older notes,
commits and code comments still resolve. `B1` (Mermaid in Quick Look) is not listed: it was
an upstream bug, tracked in the Upstream contribution track above.

Planned releases: security fixes as revisions (1.3.1), features as minor releases
(2.0, 2.1). Set 2026-09-30; 1.3.2 was folded into 1.3.1 on 2026-10-01, and the folder-opening
work (F9) moved to 2.0 so that 1.3.1 stays a fixes-only release.

### Open

| ID | Item | Release | Notes |
|---|---|---|---|
| **F5** | Show a link's destination on hover, like a browser's status bar | 2.0 | **not started, requested 2026-09-30.** Hovering a link in the reading view shows where it actually goes in a small bar at the bottom of the window, the way browsers do (Safari's status bar, Chrome's bottom-left bubble), and hides it when the pointer leaves. A convenience, and a security one: link text can say `github.com/…` while the target is somewhere else, and Belvedere is for reading documents someone else sent. Show the **resolved** target, not the text the document wrote: a relative link as the file path it resolves to (from the `md-asset:` base), a web link with its host visible even when long (truncate the middle of the path, never the host), and an internationalised host in punycode, so a look-alike domain cannot pass. Mailto and in-document `#` links shown as such. The page reports hovers through the host bridge (`mouseover`/`mouseout` on `a[href]`) and the window draws a native overlay, so document content cannot style or spoof the bar. App window only — Quick Look has no host bridge. Editor links are out of scope at first. Not security-weakening and not fork-specific, so it could be offered upstream as its own PR. |
| **F6** | An ⓘ callout for *Highlight outline section under the pointer* | 2.0 | **not started, requested 2026-09-30.** Settings › General › Reading. The name alone does not say what changes: the sidebar outline always highlights one section, and this setting decides which. Reuse `InfoPopoverButton` (the *Line breaks* row's ⓘ), a popover on click with an accessibility label such as "About outline highlighting". Draft text — *Off:* the outline highlights the section you have scrolled to. *On:* it highlights the section under the mouse pointer as you move over the document, and goes back to following the scroll when the pointer leaves. Check that last clause against `ContentViewController.pointerDocumentYDidChange` / `updatePointerTracking` before shipping it. Consider a one-line subtitle too, as *Line breaks* has, e.g. "Which section the outline marks as you read." The row is upstream's `Toggle` in `GeneralSettingsView.swift`, so wrap it in `LabeledContent` the way the *Line breaks* row is, and keep the change to that one row. English strings only, as with *Line breaks*. |
| **F7** | ⌘R to reload the open file from disk | 2.0 | **Partly done:** Revert to Saved (⌘R) now discards unsaved changes after a confirmation, from the Save-button work. Still missing: re-reading a file with no local changes. See below. |
| **S7** | Trusted folders, security-scoped bookmarks, and dropping the `/` read-only entitlement | 1.5 | One item: trusting a folder is the moment to take a bookmark. Absorbs the former F9. Trust is proposed upstream on [#337](https://github.com/pluk-inc/markdown-preview/pull/337). See below. |
| **UC1** | Offer click-to-load upstream | — | Offer click-to-load for blocked images (legacy F4) to Markdown Preview as its own PR, once the containment PR ([#337](https://github.com/pluk-inc/markdown-preview/pull/337)) is resolved. It must follow the reworked boundary — the opened project folder, not the document folder. See the Upstream contribution track. |
| **UC2** | Pitch upstream an optional setting to block a document's network egress | — | **not started, low priority** — the maintainer's own idea, offered when closing [PR #399](https://github.com/pluk-inc/markdown-preview/pull/399): *"we may revisit an optional privacy setting or a narrower CSP separately."* Worth a narrow proposal along those lines once someone has time, distinct from and no substitute for `PreviewContentPolicy` here, which stays unconditional regardless of whether this ever lands. If they build it as a user-facing toggle, decide then whether Belvedere adopts it (defaulted to enforced) or leaves the toggle out entirely and keeps its own unconditional enforcement — no reason to pick now. |
| **UF1** | Render extension registry (upstream PR 429) | — | Upstream's open render-extension-registry PR ([#429](https://github.com/pluk-inc/markdown-preview/pull/429)). Reviewed 2026-09-25: **don't import now** — unreviewed by the maintainer, functional bugs flagged. If it merges and the headings are wanted, take the two extensions without the registry. Criteria for any registry-style feature: static compiled-in assets only, no code from outside the bundle, output still through DOMPurify and the CSP, no new network or filesystem reach. |
| **H4** | Delete the six Belvedere releases still on the tap repo | — | **Due on or after 2026-10-28.** Left in place when releases moved to `inquinity/belvedere` on 2026-09-28, so nothing mid-flight broke during the switch. The command, and the check to run first, are in `docs/RELEASE-AUTOMATION.md`, decision 6. Irreversible, so do it deliberately rather than as part of some other change. |
| **H5** | Understand the Greptile review comments on our upstream PRs | — | **not started.** `greptile-apps[bot]` reviews pluk-inc PRs automatically, and its comments land on ours — inline on #337 (`MarkdownWebView.swift`), and in a *Comments Outside Diff* list that is easy to miss outside email. Work out which of its findings on our PRs are real, how much weight the maintainer gives them (does an open finding hold up a merge?), and how to treat outside-diff comments, which attach to whatever the PR branch contains — including upstream code pulled in by *Update branch*. **First triaged, 2026-09-28, on #337:** "Later documents miss snapshots" at `ContentViewController.swift:465`. That is upstream's reopen-snapshot code from #450 (`b0f9668`), merged into the PR branch the same day, not our diff — nothing to do on #337. The finding is accurate (`snapshotSource` is set only while `!webView.hasRequestedDocument`, so only a window's first document is saved), but for Belvedere it points the wrong way: `DocumentSnapshotCache` writes PNGs of the first screen of up to 40 recently opened documents to the app's Caches folder, and this would widen it. **Decided in the 0.0.63 sync (2026-09-29): Belvedere removed the snapshot code entirely** (see *How changes are applied*), so this finding is moot here. |
| **H6** | Two known click-to-load coverage gaps | — | Deliberately left: the `too large` label has no page-level test, and duplicate references to one blocked file are untested. See below. |
| **F12** | Reword the leave-edit-mode button "Continue" | — | **Idea, 2026-10-01 — food for thought.** *Continue* keeps the changes unsaved and leaves edit mode, and it works well, but the word does not say that. Candidates: *Continue without saving* or *Exit edit mode without saving*. Keep Escape as that choice. Needs a decision on the wording and the Chinese string. |
| **F13** | Edit as plain text | — | **Idea, 2026-10-01.** An edit mode that is a plain text field, with no rich editing, for copying and pasting code blocks exactly or making a very particular edit. Decide whether it is a toggle inside the editor, a second mode beside Edit, or a setting; and what it does with the preview, undo and the unsaved-changes prompt. |
| **F14** | Drag a folder onto a window or its sidebar to open it | — | **Future enhancement, requested 2026-10-01.** Dropping a folder on the Dock icon works. This is the same on the window, or the sidebar, opening that window on the folder. The web view is the hard part: a `WKWebView` drop of a file can try to navigate to it, so the drop must be taken before the page, and anything that is not a folder or Markdown file must still do nothing. A dropped folder sets that window's boundary, so it ties to S8. |
| **F15** | Search the text of files across the opened folder | — | **Idea, 2026-10-01.** The VS Code model: **⇧⌘F** searches the contents of every file in the opened folder, where Search for Document (⇧⌘O) matches file names. Belvedere already has the folder as its project. **⇧⌘F is kept free for it** and nothing else may take it. Needs the index to read file contents, which is new reach into the folder and so a boundary question (only files inside the opened folder, no following links out of it); results open as Search for Document's do. |
| **H8** | Rename the Xcode project and folders | — | **Low priority. Needs discussion before any work.** The project and several folders still carry upstream's names (`belvedere`, `Markdown Preview`). Renaming them would make every `git merge upstream/main` harder, since upstream's changes land under the old paths. Decide whether that cost is worth it, and what the rename would cover. |
| **F10** | ⌘N opens a new tab, not a new window | — | **Bug, reported 2026-10-01.** With a window open, ⌘N makes a tab in it. Expected: a new window. `attachToExistingTabGroupIfNeeded` (`DocumentWindowController.swift`) joins the new window to an existing tab group on first show, following the system *Prefer tabs* setting; check whether that setting explains it, and if so decide whether ⌘N should override it (there is a `nextWindowDeclinesTabbing` flag). Needs the intended behaviour defined first, together with S8. |
| **F11** | ⌘O opens the file in the original window, not the one you are in | — | **Bug, reported 2026-10-01.** Repro: open a folder; ⌘N (opens a tab, see F10); drag the tab out into its own window; ⌘O in that window and choose `post.md`. The file opens in the **original** window instead of the window ⌘O was pressed in. Expected: the key window, or a defined rule for where it goes. Two paths handle ⌘O: `AppDelegate.openDocument` (the menu action) and `DocumentWindowController.openDocument`; find which one ran and why it chose that window. Bears on S8, since the window a file lands in decides which boundary it gets. |
| **S8** | Each window must have its own folder boundary | — | **Validation and hardening, requested 2026-10-01.** Check that every window has its own root and context, so keeping `~/` open in one window does not widen what another window may read. Today `openedFolderRoot` is a property of each `DocumentWindowController`, so state is per window controller, and each tab is its own controller; confirm that holds in every path (open, drag-out, merge-all-windows, restore, ⌘O, links, the folder arriving from the CLI) and add tests where a window could pick up another's boundary. **Behaviour to define first:** whether tabs in one tab group share a folder or each keep their own. The safest default is that they do not share, and that a tab's boundary never survives moving to another window. F11 is a live example of a file landing in the wrong window. |
| **F18** | Stray whitespace seen after an italic table cell | — | **Unconfirmed, 2026-10-03.** While editing `*target words*` in a table cell, the cell behaved as if there were whitespace after the text; later it behaved normally and could not be reproduced. Suspect: `captureActiveValue` and the Tab handler read a cell with `innerText`, which can end in a newline in a `white-space: pre-wrap` element. Next step if it returns: write down the exact keys pressed and whether the cell had been edited before. |
| **F19** | A setting to repair Belvedere's Quick Look association | 2.0 | **Requested 2026-10-05.** Another app can take over Quick Look for `.md` (BetterZip and others register preview extensions; a stray dev build did in practice), and the reader sees plain text with no hint why. Add a setting, for example in Settings › General or › Advanced, that says whether Belvedere's extension is the one handling Markdown and offers **Repair**, which re-registers it (`pluginkit -a` on the extension, election `pluginkit -e use -i com.altmansoftwaredesign.belvedere.quick-look`, then `qlmanage -r` and `qlmanage -r cache`). **Open question first:** Belvedere is sandboxed, so check whether it may run those tools or read the extension list at all. If it cannot, the fallback is a button that opens System Settings ▸ General ▸ Login Items & Extensions ▸ Quick Look with a short explanation, and a status line from what the app can observe. Related: the ⌘-Space "Open with" check in the manual test notes. | **Seen in practice, 2026-10-05:** Quick Look showed `.md` files as plain text, with "Open with Belvedere" in the header, because (1) `QLTextView` (the owner's own general text extension, `~/dev/projects/QLTextView`) was enabled (`+` in `pluginkit`) and claims `public.plain-text`, `public.text` and `public.data`, which Markdown conforms to; it reads any file whose bytes look like text (`sniffUnknown: true` in its `PreviewViewController.swift`), so it renders a `.md` as plain text whenever Quick Look hands it one, and (2) Belvedere's own extension was not registered at all, having dropped out of `pluginkit` after being registered earlier the same day for reasons not found. Repair that worked: `pluginkit -a /Applications/Belvedere.app/Contents/PlugIns/belvedere-quick-look.appex`, `pluginkit -e use -i com.altmansoftwaredesign.belvedere.quick-look`, `qlmanage -r`, `qlmanage -r cache`. Belvedere's extension names the exact type `net.daringfireball.markdown`, which should beat a competitor's broader `public.plain-text` once both are enabled; if it does not, the fix belongs in QLTextView, which is ours too: have it leave types that a dedicated viewer owns, such as Markdown, alone. **Confirmed 2026-10-05:** with both extensions registered and enabled, Quick Look uses Belvedere's for `.md` (the exact type beats QLTextView's broader ones), so QLTextView needs no change. What remains is the unexplained loss of Belvedere's registration; if it recurs, that is the thing to chase, and the repair above is the fix. |
| **F21** | Go to File matches names that only contain the letters in order | — | **Reported 2026-10-05.** Typing `man` offered `remote-beacon.md` with the letters scattered through it (**m** in *remote*, **a** and **n** in *beacon*), and as the only result it looked like a hit. `FileSearchMatcher` is a subsequence matcher: a query matches any name that contains its letters in order, however far apart, and ranks by prefix, word boundaries and runs, so a scattered match shows whenever nothing better exists. **Options:** (1) drop a match whose letters are spread over too much of the name, for example a gap of more than a few characters between letters, or the matched span longer than about three times the query; (2) keep scattered matches but show them only when no contiguous, prefix or word-start match exists, and dim them; (3) require every letter to sit inside one word of the name. Whatever is chosen, `tests/fixtures/file-search/matcher-baseline.json` pins today's output and its README says not to regenerate it just to pass; update it deliberately, with the reason. The matcher is upstream's (their #408 and later optimizations). |
| **F22** | The editor's Mermaid diagrams differ slightly in size from the reading view's | — | **Investigated 2026-10-05, not fixed.** `EditorPreviewLayoutTests.testCompleteMixedFormattingDocument` fails by about 1.25 px after a diagram at 1280 px full width, on macOS 26.7 and 27.0.1. **What was found:** the reader initializes Mermaid with `fontFamily: '-apple-system, … "SF Pro Text", …'` (`MarkdownHTML+Mermaid.swift`) and the editor (`EditorHTML.swift`) with none, so the editor's labels measure in Mermaid's default font. Giving the editor the same font made the mixed-document diagram identical in both views (viewBox 437.0156 × 70, height 160.20), **but** made `testMermaidWithRealBundledRenderer` fail at every width, because with the same font its `A[Source] --> B[Preview]` diagram still came out 4 px wider in the editor (viewBox 294.05 vs 290.05), so the editor ended 1.4 to 3.9 px shorter after the diagram. Net effect of the one-line change: one failing test traded for another, so it was reverted. **Conclusion:** the two pages also measure text differently for a reason beyond the font family. Look at what Mermaid inherits where it measures: letter-spacing, kerning or font features, `text-rendering`, `white-space` and `font-size` on `.cm-content` against `.markdown-body`. Impact for readers is about a pixel after a diagram when switching between reading and editing. | **Second investigation, 2026-10-05.** *Established:* the diagram width is fixed when Mermaid measures the labels, not when it draws them (the drawn label is 176.23 px wide in both views); the two views give different `viewBox` widths for the same source and the same configured font (`A[Source] --> B[Preview]`: reading view 290.05, editor 294.05; `A[Draft] --> B[Review] --> C[Publish]`: 434.20 against 437.02), and the difference depends on the diagram, not on a fixed amount. Re-rendering the same source in the reading view with `mermaid.render(...)`, the call the editor uses, gives the editor's number (294.05), so the reading view's first render, through `mermaid.run`, is what differs. *Ruled out:* page timing (`document.fonts.ready` and a 150 ms delay before the first run changed nothing), inherited text styles (a plain span measures 51.06 px in `<body>`, in `.mermaid` and in `article` alike), the configured font alone (it fixes the mixed document and breaks the simple one), and passing the stage as `render`'s third argument (no change, so the vendored `mermaid.render` probably ignores it). *Likely cause, not proved:* `mermaid.run` builds its temporary measuring SVG inside the `.mermaid` node, a flex container with padding, while `mermaid.render` builds it on `<body>`, and Mermaid's label boxes or layout come out a pixel or two narrower per node there. *Options:* make the reading view render through `mermaid.render` like the editor (changes the reader's core diagram path, which Quick Look, print and the popup share, so it needs the Mermaid tests and a hand check of each); or relax the test tolerance after a diagram to about 4 px with a comment, since the visible effect is a pixel or so when switching between reading and editing. Nothing was changed in the code. |

### Done

Ordered by the release each shipped in. **1.3.1 is published**; items marked 2.0 are done on `feat/1.4.0` and not yet released.

| ID | Item | Shipped in | Notes |
|---|---|---|---|
| **F1** | Pick a final product name and icon | 1.0.6 | ✅ done — **Belvedere**, with the bundle identifier changed to match. Icon is Split Signal / Geometric B (concept 2). See below. |
| **S1** | CSP on the app preview page and editor (`PreviewContentPolicy`) | 1.0.6 | ✅ done and verified — math and editing confirmed working after the CSP landed. |
| **F2** | Click-to-load for deferred content | 1.0.6 | ✅ **local case done** — out-of-boundary images render as a placeholder with Load, verified end to end in the running app. Remote images are labelled but not loadable; see below. Not part of the containment PR (#337); offered upstream as its own PR once that is completed — see the Upstream contribution track. |
| **H1** | Manual-test `.md` files need pass/fail criteria a human can read off the screen | 1.0.6 | ✅ done — `EXPECT`/`FAIL IF` notes in every fixture, plus `docs/MANUAL-TEST-CHECKLIST.md` for upstream's `samples/`. See below |
| **H2** | Application menu still said "Markdown Preview" | 1.0.6 | ✅ done — see below. Its two adjacent findings ("Check for Updates…", "Send Anonymous Crash Reports") are also resolved — both removed from the menu on request, see below. |
| **F3** | Homebrew tap ([`inquinity/homebrew-tap`](https://github.com/inquinity/homebrew-tap)) | 1.1.0 | ✅ done — **public**, not private: discoverability, not authentication, is the intended limit on who installs it. `brew install --cask inquinity/tap/belvedere`. DMGs are GitHub Releases on [`inquinity/belvedere`](https://github.com/inquinity/belvedere/releases), so no token is needed. 1.1.0 through 1.2.4 were first released on the tap repo itself, while the source was still private; moved and backfilled 2026-09-28 once it was public — see `docs/RELEASE-AUTOMATION.md`, decision 6. First published version: 1.1.0. |
| **S2** | A link could start a program | 1.2.2 | `activateLink` in `MarkdownWebView.swift` hands a clicked link's target to `NSWorkspace.shared.open` once containment allows it — and containment says the file is inside the document's folder, not that the document may *start* it. A relative link to `tools/setup.command` therefore ran it on one click. **Fixed:** a target the system would run or install (app bundle, Unix executable, installer, disk image) is now shown in Finder after a confirmation. **Correction:** this row previously said absolute `file://` links were the problem — they are not reachable that way, because `ALLOWED_URI_REGEXP` strips `file:` hrefs before a document is rendered. That path is hardened anyway, upstream in [PR #337](https://github.com/pluk-inc/markdown-preview/pull/337). **Updated:** since the #337 rework landed on `main`, a clicked link is no longer gated by containment at all — the click is the decision, matching upstream. The executable/installer check above is what still stands between a link and `NSWorkspace.shared.open`, and now applies to every link, not only ones containment used to let through. |
| **H3** | `brew uninstall --zap belvedere` left folders behind | 1.3.0 | ✅ **fixed in the tap, 2026-09-29** (`05ed469`, "belvedere: zap the Quick Look, group and script folders"). `zap` had trashed only the app's container. It now also covers the Quick Look extension's container, both group containers and the four `~/Library/Application Scripts` folders. It drops the `HTTPStorages` and `Preferences` paths, because a sandboxed app never writes those outside its container. **The stray `~/Library/Preferences/45GJWJVQN2.com.altmansoftwaredesign.belvedere.plist`** holds one key, `belvedere.appearance`, and was written once, at 22:54 on 2026-09-25, during the 0.0.62 sync. Only an unsandboxed process writes an app-group suite there, which means an unsigned build run directly, not the shipped app. So it stays out of `zap`; it has since been deleted. **The investigation found a real bug, fixed 2026-09-29:** releases through 1.2.4 were signed for an app group literally named `$(DEVELOPMENT_TEAM).com.altmansoftwaredesign.belvedere` (macOS makes the folder `--DEVELOPMENT_TEAM-.…`), not the `45GJWJVQN2.…` the code reads. So the app and Quick Look could not share settings. `bin/build.sh` now expands the entitlements and checks the signed group before notarizing; see *`bin/build.sh` signs outside Xcode, so it expands the entitlements itself* under Distribution. Settings actually carrying over to Quick Look is not yet confirmed on screen; the first Developer ID build after the fix is the test. `zap` covers both folder names, since earlier installs keep the `--DEVELOPMENT_TEAM-` ones. |
| **S3** | Leaving edit mode or saving dropped the opened-folder boundary | 1.3.1 | ✅ **fixed in 1.3.1.** Saving, leaving edit mode, `rerenderCurrentPreview` and an image rename re-displayed the open document through `renderCurrentDocument`, which reconsiders the opened folder as if a new document had loaded. They now call `displayCurrentDocument`. Not covered by an automated test: the window controller is not in the SPM test package, so this was checked by hand. **Hand-tested 2026-10-01** on build `1.3.0 (dev 308102e)` with `tests/fixtures/relative-assets/post.md` and `tests/fixtures` opened as a folder: the shared image kept rendering after ⌘E twice and after a save. `applyLoadedMarkdown` (a reload after the file changes on disk) still uses `renderCurrentDocument` and can drop the boundary the same way for a document outside the opened folder; left alone because the same function also serves first loads. |
| **S4** | Boundary parameters defaulted to `nil` | 1.3.1 | ✅ **fixed in 1.3.1.** `assetBaseURL` and `containmentRoot` no longer have defaults on `MarkdownWebView.display`, `ContentViewController.display`, `MainSplitViewController.display` and `enterEditMode`, so a caller that forgets them fails to compile. |
| **F4** | Dev builds say so in About | 1.3.1 | `bin/build.sh` stamps `BelvedereBuildStamp` into the built Info.plist (`release` under `--release`, else the short commit, `+` for a dirty tree) and About shows `Version 1.3.1 (dev <commit>)`. A build run from Xcode, which skips `bin/build.sh`, shows `(dev build)`. See the note on the build number under About. |
| **S6** | Belvedere never writes inside its own app bundle | 1.3.1 | ✅ **done.** `AppBundleWriteGuard` refuses any path inside an application bundle: the running app's, or any folder named `*.app`. The first version checked only the running app's bundle, and a dev build run from `build/` opened and saved a file in the installed `/Applications/Belvedere.app` and broke that copy's code seal; an installed Belvedere is the same developer as the build, so macOS allows it. It lives in a new file (so `DocumentWindowController+EditSession.swift` keeps small, one-line calls) decides from the path alone, following symlinks, ignoring case and judging a file that does not exist yet by its nearest existing folder. Applied at: entering edit mode (a bundled document gets an explanation instead of an editor; no edit mode means no Save), the Save As… panel, the one function that writes the document, pasting an image, and the export panel. Save As… to a copy elsewhere still works and the window then follows the copy. The 1.3.0 read-only `Acknowledgements.md` guard stays as a second layer. Image rename is guarded too (an image reached through an opened folder can sit in the bundle), and `ForkPostureTests.testEveryWriteSiteStillCallsTheAppBundleGuard` fails if a write site loses its call. **Not covered:** hard links (a second name for a bundled file outside the bundle); the gap between the check and the write, which a swapped symlink could use; and the system print dialog's own *Save as PDF*, which writes where the reader chooses and is not ours. Tests: `AppBundleWriteGuardTests`. **Hand test:** open `Acknowledgements.md` from inside the build you are running **and** from `/Applications/Belvedere.app` if it is installed (File ▸ Open…); press ⌘E in each and expect the explanation. **Hand-tested 2026-10-01** on build `1.3.0 (dev 93963f2)`: edit mode refused for the file in the running build's bundle and in `/Applications/Belvedere.app`. A false positive to know about: a document inside any folder named `Something.app` is refused too. |
| **H7** | Remove the sponsor material | 1.3.1 | ✅ **removed.** `.github/FUNDING.yml` (it showed a Sponsor button on this repository that paid upstream's maintainer), `docs/sponsors/`, the Amore skill files and their `skills-lock.json` entry, and `docs/markdown-logo.svg`. Left on purpose: upstream's own `CHANGELOG.md` entries about sponsors, and the upstream credit in the README, Acknowledgements and license file. The files remain in git history. Kept out on upstream merges by *Standing removals* in `docs/Upstream-Changed.md`. |
| **F9** | Opening a folder from inside the app | 2.0 | ✅ **done, hand-tested 2026-10-01 and again 2026-10-05 on the rebuilt `feat/1.4.0` (menu item, no shortcut, Dock drop, Go to File)** on build `1.3.0 (dev 86c58aa)`. File ▸ Open Folder… has a folders-only panel, so **Open** chooses the selected folder, or the one being shown, instead of drilling in; it works with no window open; Search for Document's empty-state button uses it. A folder dropped on the Dock icon opens (a `public.folder` document type ranked Alternate, guarded by `ForkPostureTests`). **Not found:** why the old Open… panel drills into a folder; it was left as it is. **Not done:** dropping on a window, now F14. **Shortcuts, decided 2026-10-01:** Open Folder… has none, as in VS Code; Search for Document keeps ⇧⌘O, which it shipped with in 1.3.0; ⇧⌘F is held for a search of text across the opened folder (F15). Both other arrangements were tried and reverted. |
| **S5** | Launch arguments saved as shared settings | — | ❌ **not reproducible, closed 2026-09-30.** The note assumed `UserDefaults.standard` leaks a launch argument into the migration. It does, but every `UserDefaults`, the shared group suite included, also searches the argument domain, so the migration sees the value as already set and skips instead of copying. Nothing is written; the migration simply retries on the next normal launch. Checked by running a test against the unchanged code, which passed. No code change. |
| **F16** | Table editing in edit mode on macOS 27 | — | **Resolved 2026-10-02: a test-harness fault, not an editor bug.** Nine editor tests about table cells failed on macOS 27.0.1 and passed on macOS 26.7 (same Xcode 27.0, same code, same `mdedit.min.js`; they fail the same way on unmodified upstream). Cause: the harness (`WebViewLayoutHarness`) built a `WKWebView` with no window, and on macOS 27 such a page is never active, so `cell.focus()` made the cell the active element but fired **no focus event**; the table cell never revealed its Markdown and the tests saw rendered text. With the view inside a window the same code fires the event and the cell reveals `**target words**` as designed (checked with a throwaway diagnostic on macOS 27). Fix: the harness hosts the web view in a borderless window far off screen. After it, all nine pass on macOS 27 and the whole suite is 566 tests with one failure. **Not hand-tested in the app on macOS 27**: a real window always supplies the active page, so editing a table there should be unaffected, but nobody has tried it. A tenth test, `testCompleteMixedFormattingDocument`, fails on both systems by 1.25 px against a 1 px limit after a Mermaid diagram; that is a separate, minor mismatch between the reading view and the editor, still open. |
| **F17** | Tab into a table cell selects the cell's contents | 2.0 | ✅ **done on `feat/1.4.0` and hand-tested 2026-10-05** (Tab works, per the reader) with `tests/fixtures/editor/table-cells.md` section 5. Review notes, not acted on: Enter still moves right where spreadsheets move down, and the focus after an edited Tab is applied two frames late, so a click in that gap could be overridden. Tab, Shift-Tab and Enter now focus the next cell and select all of its text (the revealed Markdown, for a formatted cell), as Word, Numbers and Google Docs do. The focus tint alone looked like a selection but selected nothing. Change is in `scripts/editor-bundle/entry-cm.js` (`focusCell`, `selectsContents`), with `mdedit.min.js` rebuilt by `npm ci --ignore-scripts && npm run build`; a rebuild of the unchanged source first reproduced the committed bundle byte for byte, so the bundle was never stale. Test: `EditorFormattingTests.testTabSelectsTheNextCellsContents` (both the unchanged-table and edited-cell paths). Context-menu row and column actions keep their old focus behaviour. |
| **H9** | Keep stray Belvedere builds out of the application list | — | ✅ **fixed 2026-10-05.** Unregistering from Launch Services (`bin/clean-app-registrations.sh`, `just clean-apps`) was not enough: Spotlight lists files on disk, so a dev build, an Xcode DerivedData build and two `(Dev)` apps kept showing as five Belvedere apps while only `/Applications/Belvedere.app` is real. The real fixes: **`bin/build.sh` now builds into `build.noindex/`** (Spotlight and Launch Services skip folders ending `.noindex`; `bin/install.sh`, `bin/bundle.sh`, `just clean` and `.gitignore` follow), and this project's Xcode DerivedData was deleted. Spotlight now lists one Belvedere, Launch Services has no strays, and the only registered Quick Look extension is the installed one. **Still to know:** Xcode builds from the IDE go to `~/Library/Developer/Xcode/DerivedData` and will be indexed again; exclude that folder in System Settings ▸ Spotlight ▸ Search Privacy, or set Xcode's DerivedData location to `build.noindex`. Command-line builds can use `-derivedDataPath build.noindex/DerivedData`. **Side effect, handled:** with the Dev apps unregistered the default for `.md` fell to Xcode. `bin/set-default-app.swift` (`just default-app /Applications/Belvedere.app`) sets Belvedere as the default for every document type it declares, reads each back, and waits for the Launch Services daemon, which applies a change a moment late; `--check` shows the current defaults. `public.markdown` cannot be set (OSStatus -50) and stays with whatever app holds it; `.md` files are `net.daringfireball.markdown`, so that does not matter for them. |
| **F20** | Search for Document is now Go to File… in the Go menu | 2.0 | ✅ **done on `feat/1.4.0`, hand-tested 2026-10-05 on build `1.3.1 (dev f5e40a7)`.** The file-name palette (⇧⌘O) jumps to a file in the opened folder and never searched inside one, so *Search for Document* misdescribed it and sat in File beside Open…. It is now **Go ▸ Go to File…**, the toolbar label is *Go to File*. VS Code and the JetBrains IDEs use *Go to File*; Xcode calls it *Open Quickly*. ⇧⌘O is unchanged and ⇧⌘F stays reserved for F15. Internal names (`searchForDocument`, `FileSearch*`) were left alone. |
| **F8** | Wide tables were squeezed to a letter per line in the reading view | 1.3.2 | ✅ **fixed, a regression in 1.3.0 and 1.3.1.** Reported 2026-10-01 and again 2026-10-05, with the fork notes' own roadmap table unreadable ("M" over "0", "setu" over "p") next to VS Code's rendering as the reference. **Cause:** upstream's #431 (2026-09-23, in 0.0.62) added `overflow-wrap: anywhere` to `article.markdown-body`; every table cell inherits it, and `anywhere` also lowers a cell's minimum width to one character, so beside one wide column the auto table layout squeezed the others to a letter each. 1.2.4 did not have it. **Fix:** `th, td { overflow-wrap: break-word; }` in `MarkdownHTML+Stylesheet.swift`, which still breaks a string that cannot fit but keeps each column at least as wide as its longest word; the table already scrolls sideways. Measured on the roadmap table at a 1350 px window: column widths [36, 57, 494, 232] became [54, 109, 447, 210]. Test: `TableColumnLayoutTests`, which fails without the fix. **Not changed:** the editor's table cells, which were not reported, and `.md-frontmatter` tables, which use a fixed layout on purpose. |
| **F23** | Content width: Full Width by default, Quick Look Width, a width per window, and the reader's place kept | 2.0 | ✅ **done and hand-tested 2026-10-05** on build `1.3.2 (dev 7c49007)`: Full Width default, the place kept when the width changes, a default that reaches new windows and tabs only, and paragraphs reflowing under Join into paragraphs. (1) The saved default is now **Full Width**: the text uses the whole window and follows it as it grows or shrinks. (2) The capped 820 px column, which was called *Normal*, is now **Quick Look Width**, because it wraps lines where a Quick Look preview does; it is still stored as `normal`, so nothing saved needs migrating. A user who never saved anything, **including one who had chosen Normal on purpose** (the old code stored nothing for Normal), now gets Full Width. (3) **Each window keeps the width it opened with.** **Settings › General › Default content width** is the saved default, and it reaches **new windows and tabs only**; a window or tab that is already open does not change when the default does. **View ▸ Content Width** changes the front window alone and is not saved. (The first version let open windows follow the default; that was reported on 2026-10-05 and removed.) (4) Changing the width, the font or the line-break choice used to send the reader back to the top, because the page is re-rendered from scratch; the reader's place is now captured first as the heading above the top of the window plus the fraction of the way through that section, and restored once the new page is ready and has measured its headings (`ContentViewController.reloadPreviewForSettingChange`, `captureSectionAnchor`). A first version restored a source position, as the edit-mode switch does; it did not hold in the reading view. Three things changed together to fix it (the web view is laid out before the reload, the restore waits for the new page, and the anchor is a section), so which one was the cause is not known. Edit mode still uses its own source anchor and works. (5) The editor re-flows live (a `--mdp-column-max` custom property in `EditorHTML`) and keeps its line the same way. `ContentWidthSetting` moved to its own file so the test package compiles it; the Quick Look target lists it in the project's membership exceptions. Tests: `ContentWidthSettingTests`. **Not covered by a test:** keeping the reader's place, which needs the running app. | **Single new lines (same change, 2026-10-05):** the *Line breaks* setting is renamed **Single new lines** with the choices **Reflow (like a README)**, the default, and **Break (like a comment)**, and it follows the width's scope: Settings holds the default for new windows and tabs only, and **View ▸ Single New Lines** changes the front window alone, unsaved (`ContentViewController.strictLineBreaks`, `SingleNewLineStyle`). It is a view setting only: the editor always shows source lines, and the file is never changed. Reflow is now the default, because breaking at the document's own line ends enforces its author's wrapping and a hard-wrapped file (this one is wrapped at about 85 columns) then ignores the window; the principle is that Belvedere should show a Markdown file the way other tools do, with Quick-Look-style fixed layouts as options, not core behaviour. The stored value is unchanged (`strictLineBreaks`, true means join); the default is now stored as nothing and *Keep as typed* is stored as an explicit false. A reader who had chosen *Keep as typed* before had nothing stored and now sees Join. `EditorPreviewLayoutTests` measures parity against the editor with newlines kept, since the editor shows each source line. |
| **F24** | Belvedere is English only | 2.0 | ✅ **done on `feat/1.4.0` (the 2.0 branch).** `belvedere/zh-Hans.lproj/` removed, `zh-Hans` taken out of `project.pbxproj`, and the menu-title sets in `AppDelegate.swift` made English-only. The reasoning, and how to restore it, is under *Localization: English only from 2.0*. Listed in `docs/Upstream-Changed.md` under standing removals. Not done: the `release-process` skill under `.agents/` still names the Chinese file; it describes upstream's pipeline, which this fork does not use. |

The former F9 (*Trusted folders*) was folded into S7: trust and bookmarks are the same act seen twice.

### ID mapping

| Legacy | 2026-09-30 | Now |
|---|---|---|
| F1 | — | F3 |
| F2 | — | S1 |
| F3 | S5 | S7 |
| F4 | — | F2 |
| F5 | — | H1 |
| F7 | — | H2 |
| F8 | — | F1 |
| F9 | S5 | S7 |
| F10 | F3 | F7 |
| F11 | H3 | H6 |
| F12 | — | S2 |
| F13 | UC2 | UC2 |
| F14 | H1 | H4 |
| F15 | — | H3 |
| F16 | H2 | H5 |
| F17 | S4 | S6 |
| F18 | F1 | F5 |
| F19 | F2 | F6 |
| — | S1 | S3 |
| — | S2 | S4 |
| — | S3 | S5 |
| — | UC1 | UC1 |
| — | UF1 | UF1 |

**Stale expectations, and the practice written to stop them.** Five times in this
repository a fixture or a README has asserted the *opposite* of current behaviour:
`path-traversal.md` denying containment existed three releases after it shipped; the
Mermaid example calling a fixed bug an accepted Quick Look limitation; `post.md` expecting
a broken-image icon after placeholders replaced them, and later giving one expectation for
two surfaces that had diverged; and `inline-html.md` expecting an empty section where a
placeholder now appears, plus calling task checkboxes unclickable after clicking them
became a feature.

Every one was accurate when written. Each went stale because something *else* changed, and
each cost a round trip in which a correct result was reported as a bug.

The practice — update the claim in the same commit as the behaviour — is now recorded
twice, deliberately. `docs/MANUAL-TEST-CHECKLIST.md` carries the fork-specific version with
the five examples, for whoever runs a release check. `AGENTS.md` carries an
upstream-neutral version with no fork references, so it can be lifted onto a `contrib/`
branch as-is. Upstream has the same problem and a better example of it than any of ours:
their `README.md` claimed Mermaid rendered in both surfaces while it was broken in Quick
Look, and that mismatch was read as documentation drift rather than as the bug it was.

**H6 — the two click-to-load gaps left open on purpose.** An audit of the deferred-image behaviour
space closed four gaps and left these two, recorded so they are decisions rather than
oversights.

**No page-level test of the `too large` label.** The condition is covered twice already —
`DeferredAssetLoader` refuses oversize input before encoding, and `InlineLocalAssets`
reports `tooLarge` for both the per-image and cumulative caps — and the label itself goes
through `describeFailure`, the same mapping that `notAnImage` exercises end to end. A page
test would pin the string and little else. It becomes worth writing if the reason ever
needs different treatment in the UI than the other refusals, such as offering to load it
anyway.

**No test for two references to the same blocked file.** Each `<img>` gets its own token
and placeholder, so clicking one leaves the other blocked, and "Load all" asks the host
twice for the same path. Neither is wrong, but neither is asserted, and the second is
mildly wasteful. Worth doing if deferred loads ever become expensive — a remote fetch
would make a duplicate request visible — or if a reader reports that loading an image
left an identical one still blocked further down the page, which is the confusing shape
this could take.

Both are small. They are listed because "we know and chose not to" is a different state
from "nobody looked", and the difference is invisible six months later.

**F7 — ⌘R to reload the open file.** Requested as a missing feature; it is really a
half-present one.

**Update — partly done.** The Save-button work, offered upstream in [PR #379](https://github.com/pluk-inc/markdown-preview/pull/379) and closed there without merging (it is on
our `main` and is ours now) took the first option described below: it implements `revertDocumentToSaved:` on
the window controller, so ⌘R now asks for confirmation and discards unsaved changes whenever
there are any. With nothing changed it stays disabled. What this item still lacks is
re-reading a file that has *no* local changes — and retitling the menu item to *Reload from
Disk* is no longer an option, because it now genuinely reverts.

`MainMenu.xib` already carries a **Revert to Saved** item bound to ⌘R and wired to
`revertDocumentToSaved:`. Until the Save-button work it was **permanently disabled**:
`MarkdownDocument` overrides `isDocumentEdited` to return `false` and `autosavesInPlace`
to `false`, so AppKit's own validation greys the item out. There is nothing to revert
*to*, as far as NSDocument is concerned. So the shortcut looked supported, did nothing,
and gave no clue why.

**Most of the time nothing needs reloading, which is worth knowing before building this.**
`FileWatcher` already watches the open document with a `DispatchSource` on an `O_EVTONLY`
descriptor and calls `loadFile(at:)` on change, so an edit made by another process appears
on its own. It handles the awkward cases too: atomic-rename saves (Vim, VS Code) replace
the inode, so the watcher reopens against the path, and a rename is followed via
`F_GETPATH` on the still-open descriptor and updates the window without re-rendering.

Auto-reload is deliberately suppressed in exactly one situation — while the reader is
editing, or has uncommitted editor changes — because reloading there would clobber work in
progress. That is the gap a manual command fills, alongside the case where a watcher
misses an event.

So the work is: make the existing item do something rather than adding a new one. Either
implement `revertDocumentToSaved:` on the window controller (bypassing NSDocument's
validation, which is keyed to an edited-state this app does not maintain), or retitle it
**Reload from Disk** — the string already exists in `Localizable.strings`, currently used
only as a button in the editor's conflict alert. Retitling has the advantage of being
honest: nothing is being reverted, the file is being re-read.

### What is fork-only, and what is not

The **`Belvedere` name and the Split Signal icon are fork-only by intent**. They exist
precisely to stop the Dock collision with upstream's own build, so contributing them would
recreate the problem they were chosen to solve. That puts them alongside telemetry,
Sparkle and the CLI installer on the list of things never offered upstream.

**Rendered Fold and the concept round are the exception, and deliberately so.**
`artwork/app-icons/README.md` describes Rendered Fold as the public `markdown-preview`
artwork: it was drawn for upstream's identity, not this fork's.

**Do not delete `docs/icon-concepts/`.** Sixteen megabytes of oversized exploration
renders look like obvious cleanup once `artwork/` holds the production sets — and they are
not. They are the decision material for a choice upstream's community has not made yet:
the ten concepts, the Dock-scale comparison board and the market survey behind them. The
production sets are two *answers*; the concept round is the *question*, and it needs to
survive until someone over there picks. Deleting it would mean regenerating a whole round
to hold the same conversation.

The concept board **has been posted**, to [#276](https://github.com/pluk-inc/markdown-preview/issues/276)
— upstream's own issue, opened by one of their users and endorsed by the maintainer, who
replied that he wants to move away from the Preview-alike icon and is considering a rename
and a distinct identity. So this is not an unsolicited proposal: they asked, in public,
first.

**If upstream picks Split Signal, this fork moves to Rendered Fold.** Decided in advance,
so it needs no deliberation later. The board offered all ten and our vote was for 1 or 2;
2 is the icon wired in here, so their choosing it would put the same mark on both apps and
bring back the Dock collision `Belvedere` exists to prevent. Concept 1 is already built as a
full production family in `artwork/app-icons/rendered-fold/`, so the switch is:

```bash
swift bin/make-icon.swift --install-rendered-fold
```

plus a rebuild. That flag was added for exactly this contingency — the installer
previously hardcoded Split Signal, so the escape route this decision depends on did not
actually exist. Round-tripped both ways and back to byte-identical. Drawing the art in code rather than exporting it once is much of the
reason this is a one-command change instead of a design round.

Watch for the same on the name: the maintainer floated renaming the app. `Belvedere` was
picked to avoid *their current* name, so a rename upstream could either dissolve the
problem or create a new collision.

This is the opposite of how the security work is treated. Containment (#337), the Quick
Look Mermaid fix (#343) and the CSP (#339) are upstream's defects and go back to them;
identity is a product decision. `contrib/*` branches are cut from `upstream/main`, so
nothing under `artwork/` or `docs/icon-concepts/` can reach one by accident — but the rule
is written down rather than left to that.

### Deferred, with reasons

**CSP on the app preview page and editor (legacy F2). Implemented as
`belvedere/Rendering/PreviewContentPolicy.swift`.** With
`com.apple.security.network.client` proven un-removable, this is the control that stops a
document reaching the network, not the sandbox.

Applied at all three `loadHTMLString` sites in `MarkdownWebView` and at the editor's, so
reading and editing are both covered. Kept separate from `QuickLookContentPolicy` on
purpose: that page inlines its vendor bundles and carries images as `data:`/`cid:`, while
this one fetches scripts and images over `md-asset:`. One shared policy would have to
permit the union, which is weaker than either.

`'unsafe-inline'` is unavoidable for scripts and styles — the host bridge, the DOMPurify
bootstrap, the theme injection and CodeMirror are all emitted inline. `script-src
md-asset:` is required because the reader lazy-loads KaTeX, highlight.js and Mermaid over
the scheme after first paint; the handler serves only an allow-listed set of bundled
files, so it is narrower than it appears. `font-src data:` covers the bundled KaTeX CSS,
which carries its fonts as base64.

**A CSP fails silently** — a blocked resource is an unrendered element, not an error, so
unit tests pinning the policy string cannot tell you the page still looks right. **Verified
by eye**: math renders and editing works in the app window with the policy applied.
Diagrams were not part of that check — Mermaid was separately found not to render in
Quick Look at all (B1, an upstream bug), and its status in the app window under this CSP
has not been explicitly confirmed either way.

**M2b — the app icon. Done, with Split Signal / Geometric B.** The fork shipped upstream's icon, so two
identically named and identically iconed apps sat in the Dock — and upstream has an open
issue that their icon is too close to macOS Preview's.

`belvedere/AppIcon.icon` is an Icon Composer document: an `icon.json` manifest plus one
PNG layer in `Assets/`. The selected Split Signal / Geometric B layer contains the approved
full composition—shaded forest-green body, raised ivory panes, their soft shadows, and the
yellow backlight—with transparent outer corners for native treatment. Its left pane retains
the three source grooves, while the custom disconnected B identifies Belvedere in the lower
two-thirds of the rendered pane. The same light shows through the central split, the right
ends of the grooves, and the B; it is not a flat gold seam painted between them.

`swift bin/make-icon.swift --install-mdview` regenerates the installed layer. The
script resamples Belvedere from its approved checked-in master and draws the public
Rendered Fold set with deterministic AppKit paths. It produces conventional 16–1024 px
iconsets, compiled ICNS files, and flattened previews under `artwork/app-icons/`.

`docs/app-icon.png` and the README screenshots are upstream marketing assets and are left
alone.

The product is also renamed: **Belvedere**, so it no longer collides with an upstream
install in the Dock, in Finder, or in the list of running apps. `PRODUCT_NAME` carries it
(`Belvedere (Dev)` for Debug), and the display name in `Localizable.strings` follows — values
only, since the keys are the identifiers `L()` looks up.

**The bundle identifier deliberately still says `markdown-preview`**
(`com.altmansoftwaredesign.belvedere`). Renaming it again would mean a new app
group, discarded preferences and another LaunchServices re-registration, all for a string
no user sees. The mismatch is intentional; do not "tidy" it.

**Click-to-load for deferred content (legacy F4).** Quick Look blocks remote images outright
(M3b), which is right for a surface reached by pressing space on a file you did not
choose. The app window is a deliberate act, so the answer there is the one mail clients
settled on: do not load, show the reader what was withheld, and offer it. Containment
creates the same situation for a *local* file outside the boundary. The affordance is
identical in both cases, and building it twice is the waste.

**The two actions are framed around the document, not the folder**, because that is how a
reader thinks: *Load this image*, and *Load all images in this document*. The batch action
is the one needing care, and not for the obvious reason. Point an `<img>` at
`../../etc/passwd` and the file is read, fails to decode and renders broken; document
content cannot observe that, since handlers are stripped and no script runs, so nothing
leaves the machine. The case that matters is a file that really *is* an image: a document
referencing `~/Pictures/passport-scan.png` gets it rendered inline, and this app has PDF
export and print — so the reader can export, share the PDF, and carry a private image out
without knowing. A blanket grant also lets document content choose which arbitrary files
reach the system image decoder.

So the batch action admits only things that are actually images (extension and magic
bytes), shows what it is about to grant before granting it, and never persists. A
reference that is not an image is surfaced rather than hidden — a document pointing an
`<img>` at `/etc/passwd` is not a broken layout, it is probing, and no other viewer tells
you that.

**Shipped for both kinds of block.** A local file outside the boundary, and a remote
image, each render as a placeholder naming what was withheld, with a Load button that asks
the host. The host verifies the bytes really are a raster image before answering with a
`data:` URL. Verified end to end in the running app: a real PNG loads on click, and a text
file renamed `.png` comes back "not an image" with the dead action removed.

**Quick Look says why, and the reason comes from the inliner.** The first labels there
were misleading: a file sitting one folder up, present and perfectly readable, was
reported as `load failed`, which sends a reader hunting a broken file that is not broken.
It was refused by the boundary — a different fact, and the one worth saying.

The page cannot work that out in Quick Look, because the preview loads with a nil base URL
and has no document folder to compare against. `InlineLocalAssets` does know: it made the
decision. So the refusal reason now rides along on the element as
`data-mdp-refused="outsideFolder"` (or `missing`, `unreadable`, `tooLarge`), and the page
renders the label from that rather than guessing. Quick Look reads
`outside this folder — Quick Look cannot load it`, naming both the cause and the surface
limitation, since the same file loads with one click in the app window.

One case deliberately gets no reason: a percent-encoded scheme or fragment. Those are
disguised remote references rather than boundary escapes, and labelling them
`outside this folder` would be a confident wrong answer.

**Quick Look gets labels, never grants — and the first cut got that wrong.** The rule was
already written down (see "Quick Look is a different surface"), and the implementation
ignored it: Load buttons appeared in Quick Look, on *every* failed image, and clicking one
spun on "Loading…" forever.

Two causes, and the second explains the first. Quick Look registers no `mdPreviewHost`
handler, so `post` is a no-op there and nothing could ever answer a request. And the
Quick Look page loads with `baseURL: nil`, so `document.baseURI` is not the document's
folder and the in/out-of-folder check called *everything* external — which is what put a
button on the inside-folder cases too.

The fix ties the affordance to the bridge: `canGrant = hasHostBridge`. No host, no button,
no "Load all", and no round trip to ask why something failed. That is a mechanical check
that happens to land exactly on the policy boundary, because the absence of the bridge and
the absence of consent are the same fact — Quick Look is reached by pressing space on a
file Finder selected.

Labels still appear, because a label is information rather than an affordance: it tells a
reader why nothing rendered and grants nothing. But the label stays generic there
(`load failed`) rather than naming a boundary decision that was never made.

**Why a non-image still gets a Load button.** The obvious refinement — check eligibility
when drawing the placeholder, and omit the button for something that is not an image — is
the wrong trade. Eligibility is decided by magic bytes, which means reading the file, so
pre-checking every reference at render time would read every path a document names.
Reading `/etc/passwd` to decide whether to draw a button still reads `/etc/passwd`, which
is the automatic access containment exists to prevent. The button is therefore offered for
any blocked local reference, nothing touches disk until the reader asks, and a refusal is
reported afterwards as `load failed: not an image`. Phrasing it as the outcome of the
action matters: "not an image" alone reads as a property of the file rather than as the
result of the click just made.

**Remote images are click-to-load too, and the decision the second half needed is
this one.** Fetching a remote image tells its host that this reader opened this document,
which is the disclosure the CSP exists to prevent — so nothing is fetched on open, the
page itself still reaches nothing (`img-src` remains `md-asset: data:`), and the click is
the whole of the consent. What the click then buys is deliberately small:

- **One image per click, and no memory of it.** "Trust this host" is the obvious feature
  and the wrong unit. A large code-hosting host speaks for thousands of unrelated authors,
  so allowing it once would allow all of them, in every document, for ever. Trust belongs
  to a folder the reader chose (trusted folders, S7); a hostname a document named is not a choice the
  reader made. **Load all** is therefore local-only — one click standing in for many is
  reasonable for files already on the disk, not for requests to hosts nobody has looked
  at.
- **The request carries as little as it can.** A fresh ephemeral `URLSession` per window,
  created only when a reader first grants something: no cookies, no cache, no credentials,
  no referrer. The `User-Agent` is `Belvedere/<version>` — naming ourselves honestly,
  rather than volunteering a browser's identity we do not have.
- **`http` and `https` only, host required, and a redirect is held to the same rule.** A
  302 is a second URL the reader never saw; without that check it could hand the fetch to
  `file:` and turn a remote grant into a local read. Chains stop at three, and the
  transfer at ten seconds and 16 MB — the same ceiling a local grant gets.
- **The size cap is enforced on the stream, not on the finished body.**
  `Content-Length` is a claim made by the server that would be lying, so it is checked
  first only because refusing early is cheaper when it is honest; the running total is
  what actually stops the transfer. A host that declares nothing and sends forever is cut
  off at the ceiling, and nothing bigger is ever held in memory.
- **Quick Look does not compile the fetcher at all.** It has no window to ask in, so a
  fetch there could only happen without consent. `ForkPostureTests` pins both halves: the
  extension's source list must not name the file, and the app's one and only URL session
  must be this one.

Verified on screen against a local server: one click produced exactly one request; a
redirect to `file:///etc/passwd` was refused without reading it; a redirect chain stopped
after three; a response claiming `Content-Type: image/png` that was not one came back
`load failed: not an image`; a dead host came back `load failed: no answer from the host`;
and both oversize shapes — a declared 100 MB and an endless chunked body with no length at
all — came back `load failed: too large`, the second with the connection dropped mid-send
and the app's memory flat.

One case is worth knowing about because it looks like a bug and is not: a server that
*understates* `Content-Length` and then sends more gets truncated by CFNetwork at the
length it promised. The reader sees a broken image rather than a refusal, because the
bytes that arrived really were what the server said it was sending. Nothing is disclosed
and nothing is over-read; the server simply lied to itself.

**What this does to the posture claim.** The About box says Belvedere *never connects on
its own*, and that is still exactly true — "on its own" is the load-bearing half. The
claim that had to change is the internal one: it is no longer "there is no code here that
connects", it is "nothing connects without a click, one image at a time". The line
"Remote content stays blocked until you allow it." was aspirational when written, because
there was no way to allow it. It is now literal.

**Bugs shipped past a green test suite before this worked**, all of the same kind: every
test asserted that dangerous things were *absent*, so zero placeholders satisfied all of
them. The morph path ran on morphdom's detached tree, where images never load and no error
fires; and the page sent `img.getAttribute('src')`, a relative reference the host cannot
resolve, so every click answered "unavailable".

**One reported cause was wrong, and is worth correcting rather than leaving in the
history.** The claim that `start()` was never hooked, so the feature did nothing on the
path that opens a document, does not survive checking: `populateFromTemplate` routes
through `MdPreview.update`, which defers, so the initial render was always covered. A hook
added there was redundant, and a later mutation test proved it — removing it changed
nothing. Two of the reports of "still broken" during that work were caused by a stale
binary being installed from a second DerivedData directory left behind by the folder
rename, not by the code. `DeferredImageRenderingTests` now
asserts the feature is *present* — placeholders appear, every blocked reference offers
Load while an in-folder failure does not, they
survive a morph update, a click asks the host exactly once with a non-relative URL, and a
refusal is shown in place.

**This item stands alone.** No trust, no persistence, no configuration, nothing to manage.
A user who never touches trusted folders (S7) still gets working documents from this. That independence is
the reason it is worth building first.

**Quick Look gets none of it.** There is no chrome to put the affordance in and nothing to
persist a decision to, and a Load button in a panel that vanishes on the next space press
would train people to click grants without reading them. See "Quick Look is a different
surface" below.

**The name is Belvedere (legacy F8), and the bundle identifier moved with it.** `MDView` was
always provisional: a quick pick to stop the Dock collision with upstream. Belvedere is a
lookout built for the view, which is what this is, and it survived a collision check that
Mirador did not.

**The identifier changed too** — `com.altmansoftwaredesign.markdown-preview` →
`com.altmansoftwaredesign.belvedere`, across the app, the Quick Look extension, both
`.dev` variants, the keychain/app group, and the six exported UTIs for Markdown file
types. That is deliberate and was done now precisely because it is the last free moment:
1.0.3 was built but never distributed, so the only installs were the author's own two
machines.

Changing an identifier is not cosmetic, and the consequences are worth remembering rather
than rediscovering:

- **macOS treats it as a different app.** An existing MDView install does not upgrade to
  Belvedere; both can sit in `/Applications` at once.
- **Preferences reset.** The defaults domain is keyed to the identifier, so theme, layout
  and editor choices return to defaults.
- **Quick Look re-registers under the new identifier**, and the old extension stays
  registered until the old app is deleted — the same failure mode as the profile crash
  that removed the QL entry earlier.

The rename touched 22 files. The parts that are easy to miss, and were all covered:
`PRODUCT_NAME` for both configurations, four bundle identifiers, the app group in both
entitlements files, the exported and declared UTIs in both `Info.plist` files, the display
name in `Localizable.strings` and `MainMenu.strings` for both locales, `MainMenu.xib`
itself, every fork build script that names the built app, and the identifier assertion in
`ForkPostureTests`. Both `.strings` files kept their exact line counts, which is the check
that matters after the earlier incident where a regex joined entries by dropping
newlines.

**Manual-test `.md` files (legacy F5) didn't say what "pass" looks like. Done, both ways.**
Every fixture written for this fork explained the threat to a *developer*; none told a
person looking at the rendered page how to tell a pass from a failure. Opening
`inline-html.md` and eyeballing it gave no way to confirm the credential-harvesting
section was blocked — `SanitizerNegativeTests` could tell, a reader could not.

The open design question was where the criteria live, since `samples/*.md` is upstream's
file and annotating it costs recurring merge conflicts. **Resolved as both:**

- **In situ, in our own fixtures** (`tests/fixtures/**`), as `EXPECT` / `FAIL IF` notes
  read while looking at the rendered page. These files are ours, so annotating them is
  free.
- **`docs/MANUAL-TEST-CHECKLIST.md`** for `samples/*.md`, which stays unannotated and
  merges cleanly, plus the things no single document can carry: build and Quick Look
  re-registration steps, the per-surface matrix, artifact verification, the second-Mac
  check, and a known-limitations list.

Two notes on the shape, because both were mistakes waiting to happen:

- **An empty section is usually the pass.** Sanitisation removes elements without leaving
  a gap, so most of `inline-html.md` should look blank. Said plainly, or a tester reads a
  correct result as a broken render.
- **One section inverts it.** `rm -rf /` must be *visible*: it was authored as hidden, and
  the sanitiser strips the `style` attribute that hid it. Invisible is the failure.

Writing these also caught three fixtures whose stated expectations had gone stale, each
describing behaviour two or three releases old: `path-traversal.md` still said containment
did not exist, `post.md` still said the remote image "must keep working" before the CSP
blocked it, and the Mermaid-in-Quick-Look example still described a fixed bug as an
accepted limitation. Documentation that tells a tester the wrong expectation is worse than
none — it converts a real regression into an expected result.

**The Application menu (legacy F7) still said "Markdown Preview." Done.** The M2b rename only
touched `Localizable.strings`, which covers everything looked up through `L()` — the
Settings pane, dialogs, tooltips. It does not cover `MainMenu.xib`'s own menu items
("Quit", "About", "Hide", the app menu's title and submenu), which macOS resolves
straight from the nib rather than through `L()`. Three places actually needed fixing,
not one: `en.lproj/MainMenu.strings` and `zh-Hans.lproj/MainMenu.strings` (runtime
overrides for each locale) and `Base.lproj/MainMenu.xib` itself (the base text those
overrides sit on top of, and what a future locale with no override would fall back to).
All three renamed; 6 occurrences each in the base XIB and the English overrides, 12 in
the Chinese overrides (title text is compound there, e.g. `退出 Belvedere`).

`MainMenu.xib` also carries `customModule="belvedere"` on the AppDelegate and
document-controller objects — stale, but not a functional risk: confirmed by checking
what `ibtool` actually compiles the nib with, `--module Belvedere__Dev_`, sanitized from the
live `PRODUCT_NAME` and independent of whatever the XIB's own attribute says. Left
alone as out of scope for a user-visible-text fix; Interface Builder's own editor would
show the stale name if anyone opened this file there, which is the only cost.

Two menu items shared the same file, were found along the way, and — on request — removed
outright rather than left inert. **"Check for Updates…"** was already dead at runtime
(`AppDelegate` removed it from the menu at launch, a stub from M3's Sparkle removal); now
the menu item, its nib outlet, and the removal code that existed only to hide it are all
gone — the outlet had nothing left to preserve for upstream-diff-compatibility once its
only consumer was deleted. **"Send Anonymous Crash Reports"** was live and misleading —
wired to `toggleCrashReporting(_:)`, visibly shown, toggling a `CrashReporter.isEnabled`
setter that is a no-op, so the checkbox could never actually turn on; the `@IBAction`,
its `validateMenuItem` case, and the menu item are all gone too. `CrashReporter` itself
is untouched — `SettingsModel` still reads/writes `CrashReporter.isEnabled` at three call
sites, per the stub-don't-excise rule, since that state tracking outlived its own menu
item once already (M3 removed the Privacy pane's crash-reporting toggle and left this
menu item as the last surviving control). Removing both left exactly one separator
between "About Belvedere" and "Services" — the stock macOS application-menu shape before
either item was ever inserted.

**B1 — Mermaid in Quick Look. Root cause found and fixed in this fork.** Fenced
`mermaid` blocks rendered as raw text in a grey box in Quick Look while syntax
highlighting and the copy button worked. Reproduced on a **stock Homebrew install of
upstream**, so it is upstream's bug — but the cause is now known and fixed here.

**The cause.** `addingCopyButtonClearance` spliced its CSS in at the *last* `</head>` in
the document:

```swift
// Vendor scripts can contain `</head>` as data. The document's real
// closing tag is the final occurrence in MarkdownHTML's output.
guard let headEnd = html.range(of: "</head>", options: .backwards) else { return html }
```

The comment anticipates the exact hazard and then gets it backwards. The real `</head>`
is near the top of the document; inlined vendor bundles sit in `<body>`, *after* it. So
with a diagram on the page the last `</head>` is the one inside Mermaid's bundled copy of
DOMPurify, in the middle of this single-quoted string:

```js
Ie = '<html xmlns="..."><head></head><body>' + Ie + "</body></html>"
```

A single-quoted JavaScript string cannot span newlines. The multi-line CSS ended the
literal mid-line, and the parser ran to the end of a 3.18 MB file hunting for a closing
quote — `SyntaxError: Unexpected EOF`, the entire bundle dead before its first statement.

**Two failures from one splice.** The diagrams never rendered, *and* the clearance CSS
never reached the document, so whenever a diagram was present the floating copy button
had no clearance at all. The second one had gone unnoticed.

**Why it looked Mermaid-specific.** `purify.min.js` is inlined in `<head>` and contains
`</head>` as data too — but *before* the real tag. With no diagram on the page the last
occurrence really is the document's own and everything behaves, which is why the bug only
ever appeared alongside a diagram. Neither the first nor the last occurrence is reliably
the document's: vendor bundles carry that string on both sides of it.

**Why it took so long to see.** The preview loads with `baseURL: nil`, giving the page an
opaque origin, and WebKit mutes script errors from opaque origins to a bare
`"Script error."` with no message, line, or stack. The real `SyntaxError` was invisible
for the whole investigation. Pointing a diagnostic build at a real origin surfaced it
immediately — worth remembering the next time this page fails silently.

**The fix.** Anchor to the *opening* `<head>` instead, which is unambiguous — it is the
first one in the document, ahead of any script. That places the rule before the main
stylesheet rather than after it, so the selector is `html body`, whose specificity wins
regardless of cascade position. The logic moved to `belvedere-quick-look/CopyButtonClearance.swift`
(a new file, so no upstream-merge rent) and is covered by
`CopyButtonClearanceTests`, whose central assertion is that **no `<script>` content is
modified**. Mutation-tested: restoring the `.backwards` lookup fails that test.

Hypotheses ruled out along the way, each by direct measurement inside the live Quick Look
webview — recorded because every one of them is plausible enough to be re-tried:

- **Bundle size / a 3 MB inline-script limit.** Bracketed with padded copies of the real
  bundle: a **3,185,423**-character script of real code compiles and runs, while the
  failing block is **3,181,544**. Larger works, smaller fails; size is not the variable.
- **Strict mode.** The bundle opens with its own `"use strict"`. Inlined first in a
  script, directive intact, it runs fine.
- **`IntersectionObserver` gating, async render, or Quick Look tearing the extension down
  before the render completes** — the prior leading hypothesis in this document. The
  script never executed at all; nothing was ever racing.
- **Document position.** Moving the emission to the end of `<body>` was tried as a fix and
  verified *not* to work — the reorder is not in the tree.
- **The CSP**, cleared earlier by an A/B build with `QuickLookContentPolicy` disabled.
- **A local reproduction in the SPM harness**, which is not possible:
  `bundledVendorScriptTag` reads from `Bundle.main`, which in an SPM test has no vendor
  resources, so the harness produced a page with no Mermaid in it and reported zero CSP
  violations. That looked like evidence and was not.

[#338](https://github.com/pluk-inc/markdown-preview/issues/338) was filed before the
cause was known and describes only the symptom. The cause and the fix went upstream as
[PR #343](https://github.com/pluk-inc/markdown-preview/pull/343) — cut fresh from
`upstream/main`, carrying the same change as here plus its tests, and marked `Fixes #338`.
No separate comment was added to the issue: the PR body carries the analysis, and posting
it twice is noise. If #343 is merged, this fork's copy becomes redundant and drops out on
the next `git merge upstream/main`.

**M4 — the `md-asset:` containment fix is carried locally, on purpose, and must be
dropped again.** The fix went upstream as PR #337 and was deliberately *not* on this
fork's `main` for a while: the reasoning was that the build was for one person who mostly
opens documents he wrote himself.

M5 changes that. Once colleagues have the DMG, the threat model is theirs, not the
author's — they will open whatever arrives in `~/Downloads`. That is the trigger recorded
here for revisiting the decision, and it has now fired, so the fix is cherry-picked onto
`main` rather than waiting on a maintainer who has not yet reviewed it.

**How to remove it when upstream merges #337.** The cherry-pick and upstream's merge will
be the same change arriving twice. If upstream merges it verbatim, `git merge
upstream/main` resolves silently — both sides made the same edit. If the maintainer
modified it, revert the cherry-pick *before* merging so the merge is clean and their
version is what lands:

```bash
git revert 466bb61      # the cherry-pick on this fork
git merge upstream/main # now trivially clean
```

Either way the end state must be upstream's version, not ours. `AssetContainmentTests`
guards the outcome: if a merge ever lands that drops containment, its three rejection
tests fail rather than the loss going unnoticed.

**What the cherry-pick cost.** It applied cleanly (git auto-merged the two files this
fork had already diverged on) but broke `AssetContainmentTests`, which existed to
document the *unfixed* behaviour — two `_knownGap` tests asserting that
`md-asset:///etc/passwd` resolves, plus a skipped placeholder for the containment check.
That file was written to fail the day the gap closed, and it did exactly that. The gap
tests are now inverted into containment assertions, the skip is gone, and a positive case
(an asset genuinely inside the folder still resolves) and the sibling-prefix case were
added. Mutation-checked: disabling `isContained` fails all three rejection tests.

**B1 is now upstream's, and their version differs from ours.** PR #343 merged as
`eddc0d0` and shipped in 0.0.53, so the first `git merge upstream/main` brought their copy
back as an add/add conflict on `CopyButtonClearance.swift`, its tests, and the call site.
Resolved by taking theirs wholesale, per the rule that the end state must be upstream's
version rather than ours.

They did not merge it unchanged. Alongside prose edits they **dropped the horizontal
clearance entirely** — `applying(to:vertical:)` where ours took `horizontal:` too — because
of their own [#346](https://github.com/pluk-inc/markdown-preview/pull/346), "Remove
page-wide Quick Look copy-button gutter": padding the whole page narrowed every document to
make room for one floating button. Their test now asserts `padding-right` is *absent*,
which is the exact inverse of what ours asserted. Both were right about their own design;
theirs is the one that ships here now.

This is the first time the fork has taken a behaviour change back from upstream rather than
sending one, and it is the cheap outcome the contribution track exists to produce: the
Mermaid fix is no longer a diff this fork carries.

**S7 — trusted folders, security-scoped bookmarks, and the `/` read-only entitlement.**
Three things that were tracked separately and are one piece of work.

Both targets carry `com.apple.security.temporary-exception.files.absolute-path.read-only`
= `/`. There is no security-scoped bookmark machinery anywhere in the codebase — that
entitlement *is* the access strategy for the project navigator and relative-asset
resolution. Replacing it means bookmark persistence and an access lifecycle, which is why
it sat untouched: a week of plumbing with nothing to show a user.

**Trust is what makes it a feature rather than plumbing.** Bookmarks stalled on having no
moment to ask for access. Trusting a folder is exactly that moment — the user names a
folder, deliberately, and that is when the bookmark should be taken. One prompt, two
payoffs: the containment boundary widens where the user said it should, and the app
acquires real, OS-scoped access to that folder instead of relying on a blanket exception.
Done properly this is the route to dropping the `/` entitlement altogether, which is the
largest security win available here.

Trust also supplies something the app currently lacks. The #337 review asked to treat an
"authorized folder" as the boundary, but there is no authorization in the tree — no
`startAccessingSecurityScopedResource`, no `bookmarkData` — so the navigator root is a UI
value, not a capability. And trust tracks provenance rather than directory distance, which
is the distinction that matters: `~/dev/projects` is content the user wrote, `~/Downloads`
is where a file someone sent them lands.

**Guards, because tree trust is coarse by design.** Refuse `~`, `/`, `/Users` and volume
roots outright rather than warning. Resolve symlinks when recording and when checking, and
store the resolved path, so a trusted folder cannot become a redirect. Warn when a
candidate covers an unusually large tree. Never auto-trust, and never offer "trust the
parent". Prompt lazily — when a document actually reaches outside its folder, not when a
folder is opened — because a prompt on open becomes a toll gate people dismiss without
reading. **Quick Look never honours trust**, for the reasons under click-to-load (legacy F4).

**The management pane.** Claude Code stores this shape in `~/.claude.json`: a map keyed by
absolute path, one boolean per entry (`hasTrustDialogAccepted`), plain text and
inspectable. Worth copying. Its management story is not — the only control is `claude
project purge`, which revokes trust by also deleting transcripts, tasks and file history,
so there is no proportionate way to withdraw one folder. An app with a Settings window can
do better cheaply: Settings → Security, one list showing **resolved paths** rather than
nicknames (the path is the boundary, so the path is what you show), the date each was
added, per-row Remove and a Remove All behind a confirmation. Trust nothing by default.
Flag entries whose folder no longer exists rather than letting them silently match
nothing. Readable JSON in the app container, not an opaque blob. Revocation can take
effect on the next render.

**The seam worth remembering:** trust is about folders, and remote images are about hosts.
Click-to-load's placeholder is shared between them, but a trusted folder says nothing about
`example.com`. Remote content is click-to-load and stays that way: a per-host grant was
considered and rejected, because one hostname can stand for thousands of unrelated
authors (see click-to-load). Folders are a unit a reader can actually mean; hosts are not.

**Sequencing.** Click-to-load first (done), since it stands alone and needs no policy. Then this. Trust is
proposed upstream as the middle of three layers on #337; if they take it, it arrives
through them, and if they decline it becomes a fork feature.

## The About box states the fork's posture

`belvedere/App/AboutCopy.swift` holds the copy for both About surfaces — the
standard panel from the app menu and the in-app pane. Two lines there are not
decoration:

> Belvedere never connects on its own.
> Remote content stays blocked until you allow it.

Those are the two guarantees from *What upstream sends over the network*, split
deliberately. The first is about the app (stubbed reporters, excised updater);
the second is about document content (the content policies, plus click-to-load).
Neither says the sandbox forbids networking, because it does not and cannot —
`com.apple.security.network.client` has to stay on both targets.

**This makes the About box part of the grep set** that `AGENTS.md` describes.
The rule there names `README.md`, `samples/`, `tests/fixtures/` and `docs/`; a
behavioural claim now also lives in Swift source. `ForkPostureTests`
`testAboutBoxStillMakesTheNoNetworkClaim` fails if the claim is softened or
deleted, and `testTelemetryReportersRemainStubs` fails if the posture behind it
goes away, so the two cannot silently diverge.

The build number is deliberately not shown. `bin/build.sh` bumps
`CURRENT_PROJECT_VERSION` by exactly one whenever `MARKETING_VERSION` changes
and never on its own, so across every release it is a bijection with the version
— `1.0.0`→1 through `1.1.0`→8 — and told the reader nothing the version did not.
`CFBundleVersion` stays in the plist, since macOS wants it.

That holds for releases only: a build from a branch carries the version of the
release it started from, so About could not say which build you were running.
`bin/build.sh` therefore writes `BelvedereBuildStamp` into the built bundle's
Info.plist (never the source tree): `release` under `--release`, otherwise the
short commit, with `+` for a dirty tree. `AboutCopy.versionLabel` shows nothing
extra for `release`, `(dev <commit>)` for any other stamp, and `(dev build)` when
there is none — a build run from Xcode, which does not go through `bin/build.sh`.

## The Mermaid HUD regression (shipped in 1.0.4 and 1.0.5)

The sanitizer hardening added `button` to `FORBID_TAGS`. `MarkdownHTML+Mermaid`
emits the five HUD controls — zoom out, reset, zoom in, fill width, open in
window — as **article HTML**, so they go through `sanitize()` like any document
content. Forbidding the tag deleted all five. It shipped in two releases and was
caught by the upstream maintainer reviewing #369, not by us.

Three things let it through, and each has a fix in place:

1. **Every sanitizer test asserted what must be *absent*.** Nothing asserted the
   app's own UI must remain, so deleting that UI could not fail a test.
   `SanitizerKeepsAppControlsTests` now asserts the five buttons survive, and
   re-forbidding `button` fails it.
2. **The manual checklist exercised Mermaid for *rendering*, not for controls.**
   A diagram that draws correctly with no HUD reads as a pass at a glance.
3. **The threat model was wrong about the payoff.** A `<button>` with no `<form>`
   behind it and no script that can run is inert — clicking does nothing. It was
   never worth the app's own controls. `input` is the tag that matters, because a
   text or password field is what invites typing; that restriction stays, narrowed
   to allow only the task-list checkbox shape.

The second finding on #369 was that our explanation of `disabled` was wrong.
DOMPurify *preserves* the attribute; `enableTaskCheckboxes()` sets
`.disabled = false` afterwards, gated on `hasHostBridge` — which is why task
checkboxes stay inert in Quick Look. The claim came from reading the final DOM
without asking what else had touched it between sanitising and looking. That is
the same failure shape as the stale fixture expectations: trusting an
observation without establishing what produced it. (Since Markdown Preview
0.0.63, `enableTaskCheckboxes()` is gone: task checkboxes stay disabled in the
reading view on every surface, and ticking a task happens in Edit Mode.)

## Quick Look is a different surface

The two surfaces have drifted apart deliberately, and the divergence has now caused
confusion three times — the CSP split (legacy F2, M3b), the containment scope (M4), and the vendor
loading mode behind B1. Collected here so it is one lookup rather than three.

| | Quick Look | App window |
|---|---|---|
| Base URL | `nil` — opaque origin | `md-asset:` base href |
| Scheme handler | **none registered** | `md-asset:` handler |
| Vendor bundles | `.inline` — embedded in the page | `.lazy` — fetched after first paint |
| Local images | rewritten to `data:` / `cid:` | served over `md-asset:` |
| CSP `img-src` | `data: cid:` | `md-asset: data:` |
| CSP `script-src` | `'unsafe-inline'` | `'unsafe-inline' md-asset:` |
| Containment | document folder, always | document folder, or an opened folder containing it; trust proposed (S7) |
| Editing, tabs, PDF export | none | yes |

Identical in both: `default-src 'none'`, remote images blocked, and the same DOMPurify
pass — both surfaces share `hostBridgeScript`, which is why the form-control fix landed in
both at once.

**The rule that generates all of it: Quick Look is reached by pressing space on a file
Finder selected, not one the reader chose.** There is no chrome to put an affordance in,
nothing to persist a decision to, and no deliberate act to attach a grant to. So the
policy is self-contained: everything the page needs is embedded before it loads, and
nothing it asks for afterwards is honoured.

**Every grant-shaped feature is app-window-only, permanently.** Click-to-load (legacy F4) and
trust (S7) both need a button, a re-render and somewhere to remember a decision. A preview
panel has none of those, and a Load button in a panel that vanishes on the next space
press would be worse than no button — it trains the reflex to click grants without reading
them. This is not a limitation to close later; it is the design.

The distinction is the provenance of the *interaction*, not of the file. The same document
gets different rules depending on how it was opened, which is correct: pressing space is
not consent.

**The cost is real.** Quick Look is stricter and less capable, and the strictness is what
forces the vendor bundles inline. That inlining is what produced B1, where a 3 MB Mermaid
bundle in the page met a CSS splice in the wrong place. Strictness bought a whole class of
bug that the app window cannot have.

## Distribution

No Sparkle means no automatic updates. Builds are published to a public Homebrew tap:
`brew install --cask inquinity/tap/belvedere` (repo
[`inquinity/homebrew-tap`](https://github.com/inquinity/homebrew-tap)). The DMG that
`bin/build.sh --release` produces is uploaded as a GitHub Release on this repository,
on the release's own tag, and the tap's cask points at it; both repositories are public,
so no token is needed to install. Handing
the DMG out directly via the corporate share or Dropbox still works as a fallback. See
`docs/INTERNAL-INSTALL.md` for what recipients need to do — in particular, Quick Look
does not register until the app has been moved to `/Applications` and launched once.

### Staging a release with `--draft`

`just publish --go --draft` creates the GitHub Release as a draft and leaves the cask
alone, so nothing installs. That's the way to check a build on a second Mac first.
**Promote it by running `just publish --go` again, without `--draft`**, before anything
else lands on `main` (`HEAD` must still be the release commit): it publishes the draft,
then bumps the cask. The reverse is refused: `--draft` against a release that is already
published stops before touching it.

Both rules close gaps that would have broken installs. Without the first, the promote
run bumped the cask onto a release still in draft, whose assets aren't publicly
downloadable, so every `brew install` would 404. Without the second, `--draft` on a
published release replaced its DMG while the cask kept the old checksum. See
`docs/RELEASE-AUTOMATION.md`, decision 5.

### Installing on the maintainer's own machine

Run **the brew-managed copy**, same as everyone else — `brew install --cask
inquinity/tap/belvedere`, and after each `just publish --go`,
`brew update && brew upgrade --cask belvedere` (the command `bin/publish-release.sh`
prints when it finishes). `/Applications/Belvedere.app` then always reflects a
*published* release, which is the point of dogfooding: it is exactly what users have.

`just release` does **not** install anything, and it should not. Verifying an
unpublished build does not need an install — `open build.noindex/Belvedere.app`, or mount
`dist/Belvedere-<v>.dmg`, and test it in place.

The one case that needs `/Applications` is a **Quick Look** change: an extension only
registers from an app that has been moved there and launched. To test one against an
unpublished build, `just install` (which also re-runs `qlmanage -r`), then
`brew reinstall --cask belvedere` to return to the tracked copy. Running `just install`
/ `bin/install.sh` over a brew-managed `/Applications/Belvedere.app` for any other
reason just desyncs Homebrew and forces `--force` on the next `brew` operation.

### Stray app bundles, and `just clean`

Over time a maintainer machine collects several `Belvedere.app` copies, and Spotlight
shows all of them:

| Where | Keep? |
|---|---|
| `/Applications/Belvedere.app` | yes — the brew-managed install (the Caskroom entry is a symlink to it) |
| `build.noindex/Belvedere.app` | no — `bin/build.sh` scratch; it wipes `build.noindex/` at the start of every run. The `.noindex` name keeps Spotlight and Launch Services from listing it as another Belvedere (it was `build/` until 2026-10-05, and showed up five times in Spotlight) |
| `~/Library/Developer/Xcode/DerivedData/belvedere-*/…/Debug/Belvedere (Dev).app` | no — an Xcode debug build. `Belvedere (Dev)` is the Debug `PRODUCT_NAME` on purpose (`project.pbxproj`), so it never collides with the release app |
| `~/Library/Developer/Xcode/DerivedData/belvedere-*/…/Release/Belvedere.app` | no — an Xcode release build; nothing tidies DerivedData on its own |

`just clean` removes `build/` and this project's `DerivedData/belvedere-*`, leaving
`dist/` (the release DMGs) alone. After it runs, Spotlight settles back to the one
`/Applications` copy once it reindexes. A pre-rename `MDView.app` used to linger in
`build/` for the same reason — the `rm -rf "$OUTPUT_DIR"` in `bin/build.sh` is what
stops that now.

### `bin/build.sh` signs outside Xcode, so it expands the entitlements itself

`bin/build.sh` compiles with `CODE_SIGNING_ALLOWED=NO` and then runs `codesign`
itself. Xcode expands build settings such as `$(DEVELOPMENT_TEAM)` in an
`.entitlements` file when it signs; `codesign` does not. Through 1.2.4 the script
signed with the source files, so every release was entitled to an app group
literally named `$(DEVELOPMENT_TEAM).com.altmansoftwaredesign.belvedere` (macOS
turned it into a folder named `--DEVELOPMENT_TEAM-.…`). The code reads
`45GJWJVQN2.…` from `Info.plist`, so neither the app nor the Quick Look extension
was entitled to the group they share settings through. Xcode-signed builds,
Debug included, were always right, which is why it went unnoticed.

The script now signs with an expanded copy of each file. It refuses to build if
either file uses a build setting it does not expand, and after signing it checks
that each bundle's signed app group matches its `Info.plist` before notarizing.
`bin/build-release.sh` archives through Xcode and was never affected.

## License

Upstream is MIT and this fork remains MIT. `LICENSE` is unmodified and upstream's
copyright notice stays intact.

The app carries every notice it is obliged to, in `Contents/Resources`:

- **upstream's**, as `Markdown-Preview-LICENSE.txt`: a copy of `LICENSE`,
  because Mermaid's license already has the name `LICENSE` in the bundle;
- **each vendored JavaScript library's**, from beside the library in
  `belvedere/Vendor/`;
- **the linked Swift packages'**: swift-markdown's license and NOTICE, and
  swift-cmark's `COPYING`, which swift-markdown compiles in. They live in
  `belvedere/Licenses/`.

Until 2026-09-29 the upstream and package notices were missing. The About
box's "Forked from pluk-inc/markdown-preview" line was the only trace of
upstream in the app, and it was never the MIT notice. `ForkPostureTests`
now fails if a notice goes missing, if the copy drifts from `LICENSE`, or
if the app gains a Swift package or vendored library without its notice.
It cannot see packages that a package pulls in, because `Package.resolved`
is not committed. When the package list changes, check
`SourcePackages/checkouts` by hand.

Both About surfaces link to **Acknowledgements**: `Acknowledgements.md`, a
short Markdown page opened in the default Markdown app. It names each component
and the license it is used under, linked to that license in the component's own
repository, as in "Markdown Preview is used under the MIT License". Links are
pinned to the version that ships, not a default branch: DOMPurify's LICENSE on
`main` became Apache-only while the 3.4.2 that ships is Apache-or-MPL. Where a
version file exists, the script refuses a link that names any other version.

It deliberately does not reproduce the license texts. An earlier version pasted
all ten in, which made a long page nobody reads. The notices above still ship
in the app on their own, and that is what meets the MIT, BSD and Apache
requirement that the notice accompany every copy. A GitHub link alone would not:
the file there can change or move, and it does not travel with the copy. (VS
Code, Signal Desktop and IINA all reproduce the texts in their single notices
file; with the notices shipping as separate files, Belvedere can give the
reader the short version instead.)

It is generated by `bin/make-acknowledgements.sh`; rerun that whenever a
component is added, removed or relicensed. The script will not run while a
shipped notice is unaccounted for or a license is named without an https link,
and `ForkPostureTests` runs its `--check`, so a stale page fails the tests. It
is a file rather than an in-app window because the standard About panel opens
its links itself, through NSWorkspace, so a file is the one target both
surfaces can share.

Whether each notice is *required*, checked 2026-09-29 against the license
texts and swift.org:

- **Upstream (MIT) and swift-cmark (BSD-2 and MIT)**: required. Both attach
  their notice to binary copies, and neither has an exception.
- **swift-markdown (Apache 2.0 with the Runtime Library Exception)**: most
  likely not. swift.org says the exception exists so that apps built with
  Swift need not credit Swift; swift-markdown's own license carries the same
  exception. Shipped anyway: it costs nothing, and the exception is worded
  around compiling, not linking a library.
- **The Swift runtime itself** is not listed. That is the exception's whole
  purpose, and on macOS the runtime is part of the OS.

---

*Fork cut 2026-09-01 from upstream `f8c22d0`.*
