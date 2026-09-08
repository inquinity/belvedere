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
| `origin` | `inquinity/markdown-preview` | This fork. Where our `main` lives. |
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
sudo lsof -i -a -p $(pgrep -f "MDView") -r 2
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
./scripts/check-upstream.sh          # read-only: has upstream moved?
git fetch upstream
git merge upstream/main              # merge, never rebase
```

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
./scripts/show-private-changes.sh --stat     # summary
./scripts/show-private-changes.sh            # full diff
./scripts/show-private-changes.sh --commits  # commit log
```

This is the authoritative answer, independent of branch structure. Both scripts are
ported from the maintainer's earlier fork of MDviewer.

## How changes are applied

Upstream churns `md-preview/App/AppDelegate.swift` (1,276 lines) and
`md-preview/Features/Settings/SettingsModel.swift` heavily. A naive removal would edit
both in six places and conflict on every sync. So each change picks the approach with
the smallest permanent conflict surface:

| Component | Approach | Why |
|---|---|---|
| Sentry | **Stub** — keep `CrashReporter.swift` and its `isEnabled` / `start()` signatures, drop `import Sentry`, empty the bodies | All four `AppDelegate` call sites and three `SettingsModel` call sites keep compiling untouched |
| PostHog | **Stub** — same for `UsageAnalyticsReporter`; `isEnabled` returns `false`, writes ignored | Same |
| CLI installer | **Orphan** — remove only the menu item registration and the entitlements; leave the now-unreachable installer code in place | Costs one line instead of four blocks in `AppDelegate` |
| Sparkle | **Excise** | `SPUStandardUpdaterController` / `SPUUpdater` are concrete types with KVO observers bound to them; faking them is more fragile than deleting. The plist keys and `mach-lookup` entitlements have to change regardless. |

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
| `md-asset:` scheme has no path containment (`MarkdownAssetResolution.swift:49`) | Advisory → PR | **accepted**; [GHSA-vgmc-h5g6-xh2q](https://github.com/pluk-inc/markdown-preview/security/advisories/GHSA-vgmc-h5g6-xh2q). Maintainer asked us to write the fix — [PR #337](https://github.com/pluk-inc/markdown-preview/pull/337) open, awaiting review |
| Preview document has no Content-Security-Policy | Issue → PR | **filed** — [#339](https://github.com/pluk-inc/markdown-preview/issues/339), with both working policies and an offer to PR |
| `ALLOWED_URI_REGEXP` permits `http`/`https` | Issue → PR, after the CSP lands | pending |
| App icon too similar to macOS Preview (upstream's own issue) | Artwork offer | **posted** — concept board added to [#276](https://github.com/pluk-inc/markdown-preview/issues/276) on 2026-09-04. Their issue, opened by a user and endorsed by the maintainer, who said he is considering a rename and a distinct identity. Awaiting a pick |
| Mermaid diagrams do not render in Quick Look, though `README.md` says they do | Issue → PR | ✅ **merged** — [PR #343](https://github.com/pluk-inc/markdown-preview/pull/343) landed as `eddc0d0` and shipped in upstream 0.0.53; [#338](https://github.com/pluk-inc/markdown-preview/issues/338) closed. Their version replaced ours on the next sync |

The `md-asset:` finding goes through GitHub's private vulnerability reporting (enabled
on upstream), **not** a public issue: it describes an unfixed weakness in a shipping app
with real users.

Nothing about removing telemetry, Sparkle, or the CLI installer is offered upstream.
Those are product decisions, not defects, and filing them would be noise.

## Roadmap

| # | Milestone | Contents | Status |
|---|---|---|---|
| **M0** | Repo setup | Remotes, `rerere`, tracking scripts, this document, FORK STATUS blocks | ✅ done |
| **M1** | Upstream contributions | Advisory + CSP issue/PR + URI allowlist issue/PR | **in progress** — advisory filed |
| **M2** | Identity & release | Team ID, four bundle IDs, app group, display names; replace the Amore release pipeline; rewrite `CLAUDE.md` / `AGENTS.md` | ✅ done |
| **M3** | Deprivileging | Stub Sentry + PostHog; excise Sparkle; orphan CLI installer; collapse Privacy pane; drop `network.client` and test Quick Look | ✅ done |
| **M3b** | *Conditional* | Quick Look CSP — the extension does need `network.client`, so the page blocks remote content instead | ✅ done |
| **M4** | Containment | `md-asset:` confinement — submitted upstream as [PR #337](https://github.com/pluk-inc/markdown-preview/pull/337) and **carried on this fork ahead of that merge** (cherry-pick of `cb6ae07`) | ✅ shipping here; still open upstream — see below |
| **M2b** | Rebranding | Replace the app icon | ✅ done — Split Signal, regenerate with `swift scripts/make-icon.swift --install-mdview` |
| **M5** | Distribution | Notarize (✅ `dist/MDView 1.0.0.dmg`), verify on a second Mac (✅ passed), ship via corporate share or Dropbox (pending — the user's own action, not tool-driven) | **in progress** — one step left |

## Backlog

Unscheduled — not part of the milestone sequence above, and not blocking M5. `B1` (Mermaid in Quick Look) isn't listed here: it's an upstream bug — fixed in this fork, and tracked in the Upstream contribution track table above rather than duplicated.

| # | Item | Notes |
|---|---|---|
| **F1** | Private Homebrew tap (`inquinity/homebrew-tap`) | Explicitly *not* part of M5 — M5 ships by corporate share / Dropbox. A tap is a separate, later distribution channel. |
| **F2** | CSP on the app preview page and editor (`PreviewContentPolicy`) | ✅ done and verified — math and editing confirmed working after the CSP landed. |
| **F3** | Security-scoped bookmarks; drop the `/` read-only entitlement | |
| **F4** | Click-to-load control for remote images in the app window, the way mail clients defer them | |
| **F5** | Manual-test `.md` files need pass/fail criteria a human can read off the screen | ✅ done — `EXPECT`/`FAIL IF` notes in every fixture, plus `docs/MANUAL-TEST-CHECKLIST.md` for upstream's `samples/`. See below |
| **F7** | Application menu still said "Markdown Preview" | ✅ done — see below. Its two adjacent findings ("Check for Updates…", "Send Anonymous Crash Reports") are also resolved — both removed from the menu on request, see below. |
| **F8** | Pick a final product name and icon | Icon selected: Split Signal (concept 2), now generated reproducibly and wired into `AppIcon.icon`. `MDView` remains the current private-variant name; any future rename still needs to land in `Localizable.strings` and `MainMenu.strings` (see F7). |
| **F9** | Trusted folders, and a pane to manage them | Proposed upstream on [#337](https://github.com/pluk-inc/markdown-preview/pull/337) as the middle of three access layers. Blocked on their answer — see below. |

### What is fork-only, and what is not

The **`MDView` name and the Split Signal icon are fork-only by intent**. They exist
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
bring back the Dock collision `MDView` exists to prevent. Concept 1 is already built as a
full production family in `artwork/app-icons/rendered-fold/`, so the switch is:

```bash
swift scripts/make-icon.swift --install-rendered-fold
```

plus a rebuild. That flag was added for exactly this contingency — the installer
previously hardcoded Split Signal, so the escape route this decision depends on did not
actually exist. Round-tripped both ways and back to byte-identical. Drawing the art in code rather than exporting it once is much of the
reason this is a one-command change instead of a design round.

Watch for the same on the name: the maintainer floated renaming the app. `MDView` was
picked to avoid *their current* name, so a rename upstream could either dissolve the
problem or create a new collision.

This is the opposite of how the security work is treated. Containment (#337), the Quick
Look Mermaid fix (#343) and the CSP (#339) are upstream's defects and go back to them;
identity is a product decision. `contrib/*` branches are cut from `upstream/main`, so
nothing under `artwork/` or `docs/icon-concepts/` can reach one by accident — but the rule
is written down rather than left to that.

### Deferred, with reasons

**F2 — CSP on the app preview page and editor. Implemented as
`md-preview/Rendering/PreviewContentPolicy.swift`.** With
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

**M2b — the app icon. Done, with Split Signal.** The fork shipped upstream's icon, so two
identically named and identically iconed apps sat in the Dock — and upstream has an open
issue that their icon is too close to macOS Preview's.

`md-preview/AppIcon.icon` is an Icon Composer document: an `icon.json` manifest plus one
PNG layer in `Assets/`. The selected Split Signal layer is drawn on transparency so
Icon Composer supplies the forest-green background gradient and native treatment. Its
grooved source pane and clean rendered pane express the source-to-preview transition
without reusing the crowded eye, lens, or Markdown down-arrow motifs.

`swift scripts/make-icon.swift --install-mdview` regenerates the installed layer. The
same deterministic AppKit-path generator also produces the public Rendered Fold set,
conventional 16–1024 px iconsets, compiled ICNS files, and flattened previews under
`artwork/app-icons/`.

`docs/app-icon.png` and the README screenshots are upstream marketing assets and are left
alone.

The product is also renamed: **MDView**, so it no longer collides with an upstream
install in the Dock, in Finder, or in the list of running apps. `PRODUCT_NAME` carries it
(`MDView (Dev)` for Debug), and the display name in `Localizable.strings` follows — values
only, since the keys are the identifiers `L()` looks up.

**The bundle identifier deliberately still says `markdown-preview`**
(`com.altmansoftwaredesign.markdown-preview`). Renaming it again would mean a new app
group, discarded preferences and another LaunchServices re-registration, all for a string
no user sees. The mismatch is intentional; do not "tidy" it.

**F4 — click-to-load remote images in the app window.** Quick Look blocks remote images
outright (M3b), and that is the right default for a surface reached by pressing space on
a file you may not have chosen. The app window is a deliberate act, so the eventual
answer there is the one mail clients settled on: don't load remote content, show a bar
offering to. Deferred because it needs UI, a per-document decision, and somewhere to
remember it — it is a feature, not a security prerequisite. F2 (a blanket CSP for that
page) is the cruder version that could land first.

**M4 — `md-asset:` containment: written, submitted upstream, deliberately not carried here
yet.** The fix exists as [PR #337](https://github.com/pluk-inc/markdown-preview/pull/337)
against upstream, not on this fork's `main`. So the shipped MDView build still resolves
`md-asset:` paths without a containment check, and a document could name any file the
user can read.

**This is a considered decision, not an oversight.** The maintainer accepted the advisory
and asked us to write the fix; the tidiest outcome is inheriting it through a normal
`git merge upstream/main` with zero fork-local diff, rather than carrying a patch that
later has to be reconciled with whatever shape upstream merges. The risk of waiting was
judged acceptable because this build is used to read documents its own user authored —
the exposure needs untrusted Markdown, and there isn't any.

Two things that would change the calculus, and should prompt cherry-picking the commit
onto `main` instead of waiting:

- The build gets handed to people who will open Markdown they did not write — the
  original M5 "ship to colleagues" case, or anything wider.
- Upstream goes quiet for long enough that "waiting" stops being a plan.

Note that the exfiltration half is already closed here regardless: `PreviewContentPolicy`
and `QuickLookContentPolicy` stop a document sending anything anywhere, so a read cannot
be turned into a leak by the document that caused it. What remains unfixed on this fork
is the read itself.

**F5 — manual-test `.md` files didn't say what "pass" looks like. Done, both ways.**
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

**F7 — the Application menu still said "Markdown Preview." Done.** The M2b rename only
touched `Localizable.strings`, which covers everything looked up through `L()` — the
Settings pane, dialogs, tooltips. It does not cover `MainMenu.xib`'s own menu items
("Quit", "About", "Hide", the app menu's title and submenu), which macOS resolves
straight from the nib rather than through `L()`. Three places actually needed fixing,
not one: `en.lproj/MainMenu.strings` and `zh-Hans.lproj/MainMenu.strings` (runtime
overrides for each locale) and `Base.lproj/MainMenu.xib` itself (the base text those
overrides sit on top of, and what a future locale with no override would fall back to).
All three renamed; 6 occurrences each in the base XIB and the English overrides, 12 in
the Chinese overrides (title text is compound there, e.g. `退出 MDView`).

`MainMenu.xib` also carries `customModule="Markdown_Preview"` on the AppDelegate and
document-controller objects — stale, but not a functional risk: confirmed by checking
what `ibtool` actually compiles the nib with, `--module MDView__Dev_`, sanitized from the
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
between "About MDView" and "Services" — the stock macOS application-menu shape before
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
regardless of cascade position. The logic moved to `quick-look/CopyButtonClearance.swift`
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

**F9 — trusted folders, and somewhere to manage them.** Proposed to upstream on #337 as
the second of three layers: click-to-load always available, trusted folders for a durable
opt-out of friction, and an explicitly opened folder as a session-scoped root. Trust is the
part that needs storage and UI, and it is the part with a management story.

The concept answers something the app currently lacks. The maintainer's review asked to use
an "authorized folder" as the containment boundary, but there is no authorization anywhere
in the tree — no `startAccessingSecurityScopedResource`, no `bookmarkData` — so the
navigator root is a UI value, not a capability. Trust supplies the missing deliberate act,
and it tracks provenance rather than directory distance, which is the distinction that
actually matters: `~/dev/projects` is content the user wrote, `~/Downloads` is where a file
someone sent them lands.

**Guards, because tree trust is coarse by design.** Refuse `~`, `/`, `/Users` and volume
roots outright rather than warning. Resolve symlinks when recording and when checking, and
store the resolved path, so a trusted folder cannot become a redirect. Warn when a
candidate covers an unusually large tree. Never auto-trust and never offer "trust the
parent". Prompt lazily — when a document actually reaches outside its folder, not when a
folder is opened — because a prompt on open becomes a toll gate people dismiss without
reading. **Quick Look does not honour trust at all:** it is the drive-by surface, with no
window to show scope in and nowhere sane to prompt, so it stays document-folder-only.

**The management pane is the part this entry is really about.** Claude Code stores exactly
this shape in `~/.claude.json` — a map keyed by absolute path, one boolean per entry
(`hasTrustDialogAccepted`), plain text and inspectable. Worth copying. What is not worth
copying is its management story: the only control is `claude project purge`, which revokes
trust by also deleting transcripts, tasks and file history. There is no proportionate way
to withdraw trust from one folder.

An app with a Settings window can do better cheaply. Settings → Security, one list showing
**resolved paths** rather than nicknames (the path is the boundary, so the path is what you
show), the date each was added, per-row Remove and a Remove All behind a confirmation.
Trust nothing by default. Flag entries whose folder no longer exists rather than letting
them silently match nothing. Storage as readable JSON in the app container, not an opaque
blob. Revocation can take effect on the next render; it does not need to be live.

**Not started, and deliberately so.** If upstream takes the proposal, this arrives through
them and the fork carries nothing. If they decline, it becomes a fork feature and the entry
stands on its own. Either way the interesting long-term pairing is with F3: the moment a
user trusts a folder is exactly when a security-scoped bookmark should be taken, which is
the route to eventually dropping the blanket `/` read-only exception.

**F3 — the `/` read-only entitlement.** Both targets carry
`com.apple.security.temporary-exception.files.absolute-path.read-only` = `/`. There is no
security-scoped bookmark machinery anywhere in the codebase — the entitlement *is* the
access strategy for the project navigator and relative-asset resolution. Replacing it
means implementing bookmark persistence and an access lifecycle, which is a week of work
on someone else's architecture. Once M4 (or upstream's fix) confines the `md-asset:`
scheme, the WebView-reachable surface is closed and only the app's own code holds broad
read, which is a much smaller concern for a read-only entitlement.

## Distribution

No Sparkle means no automatic updates: new builds are handed out manually via the
corporate share or Dropbox. See `docs/INTERNAL-INSTALL.md` for what recipients need to do
— in particular, Quick Look does not register until the app has been moved to
`/Applications` and launched once.

## License

Upstream is MIT and this fork remains MIT. `LICENSE` is unmodified and upstream's
copyright notice stays intact.

---

*Fork cut 2026-09-01 from upstream `f8c22d0`.*
