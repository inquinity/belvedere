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
| DOMPurify's KEEP_CONTENT lets form controls survive a forbidden `<form>` | PR | **changes requested** — [PR #369](https://github.com/pluk-inc/markdown-preview/pull/369). Reported publicly rather than by advisory: no exfiltration path, patch attached, and the analysis was already public in this fork's history. Both review findings were correct; see *The Mermaid HUD regression* below |
| Documentation that describes behaviour goes stale silently | Practice → PR | **submitted** — [PR #368](https://github.com/pluk-inc/markdown-preview/pull/368), open. Their own `README.md` Mermaid claim is the motivating example: it concealed #338 for several releases |
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
| **M2b** | Rebranding | Replace the app icon | ✅ done — Split Signal / Geometric B, regenerate with `swift bin/make-icon.swift --install-mdview` |
| **M5** | Distribution | Notarize (✅ `dist/Belvedere 1.1.0.dmg`), verify on a second Mac (✅ passed on an earlier build), distribute via the public Homebrew tap (✅ `inquinity/homebrew-tap`, from 1.1.0); corporate share / Dropbox stays as a fallback | ✅ done |

## Backlog

Unscheduled — not part of the milestone sequence above, and not blocking M5. `B1` (Mermaid in Quick Look) isn't listed here: it's an upstream bug — fixed in this fork, and tracked in the Upstream contribution track table above rather than duplicated.

| # | Item | Notes |
|---|---|---|
| **F1** | Homebrew tap ([`inquinity/homebrew-tap`](https://github.com/inquinity/homebrew-tap)) | ✅ done — **public**, not private: discoverability, not authentication, is the intended limit on who installs it. `brew install --cask inquinity/tap/belvedere`. DMGs are GitHub Releases on the tap repo itself, so no token is needed; source stays private in `inquinity/belvedere`. First published version: 1.1.0. |
| **F2** | CSP on the app preview page and editor (`PreviewContentPolicy`) | ✅ done and verified — math and editing confirmed working after the CSP landed. |
| **F3** | Trusted folders, security-scoped bookmarks, and dropping the `/` read-only entitlement | One item: trusting a folder is the moment to take a bookmark. Absorbs the former F9. Trust is proposed upstream on [#337](https://github.com/pluk-inc/markdown-preview/pull/337). See below. |
| **F4** | Click-to-load for deferred content | ✅ **local case done** — out-of-boundary images render as a placeholder with Load, verified end to end in the running app. Remote images are labelled but not loadable; see below. |
| **F5** | Manual-test `.md` files need pass/fail criteria a human can read off the screen | ✅ done — `EXPECT`/`FAIL IF` notes in every fixture, plus `docs/MANUAL-TEST-CHECKLIST.md` for upstream's `samples/`. See below |
| **F7** | Application menu still said "Markdown Preview" | ✅ done — see below. Its two adjacent findings ("Check for Updates…", "Send Anonymous Crash Reports") are also resolved — both removed from the menu on request, see below. |
| **F8** | Pick a final product name and icon | ✅ done — **Belvedere**, with the bundle identifier changed to match. Icon is Split Signal / Geometric B (concept 2). See below. |
| **F10** | ⌘R to reload the open file from disk | The menu item exists and is permanently disabled. Auto-reload already covers the common case; this is the manual override. See below. |
| **F11** | Two known F4 coverage gaps | Deliberately left: the `too large` label has no page-level test, and duplicate references to one blocked file are untested. See below. |
| ~~F9~~ | Trusted folders | Folded into F3 — trust and bookmarks are the same act seen twice. |

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

**F11 — the two F4 gaps left open on purpose.** An audit of the deferred-image behaviour
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

**F10 — ⌘R to reload the open file.** Requested as a missing feature; it is really a
half-present one.

`MainMenu.xib` already carries a **Revert to Saved** item bound to ⌘R and wired to
`revertDocumentToSaved:`. Checked in the running app, it is **permanently disabled**:
`MarkdownDocument` overrides `isDocumentEdited` to return `false` and `autosavesInPlace`
to `false`, so AppKit's own validation greys the item out. There is nothing to revert
*to*, as far as NSDocument is concerned. So the shortcut looks supported, does nothing,
and gives no clue why.

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

**M2b — the app icon. Done, with Split Signal / Geometric B.** The fork shipped upstream's icon, so two
identically named and identically iconed apps sat in the Dock — and upstream has an open
issue that their icon is too close to macOS Preview's.

`md-preview/AppIcon.icon` is an Icon Composer document: an `icon.json` manifest plus one
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

**F4 — click-to-load for deferred content.** Quick Look blocks remote images outright
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

**Shipped, with one half deliberately unfinished.** A local file outside the boundary now
renders as a placeholder naming it, with a Load button that asks the host, which verifies
the bytes really are a raster image before answering with a `data:` URL. Verified end to
end in the running app: a real PNG loads on click, and a text file renamed `.png` comes
back "not an image" with the dead action removed.

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

**Remote images are labelled but not loadable.** They get a placeholder saying so and no
button, because fetching one would send the reader's IP to whoever authored the document —
the disclosure the CSP exists to prevent. Offering a button that always fails would be
worse than offering none. Remote click-to-load needs its own decision about what a fetch
may carry, and has not been made.

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
asserts the feature is *present* — placeholders appear, only local ones offer Load, they
survive a morph update, a click asks the host exactly once with a non-relative URL, and a
refusal is shown in place.

**This item stands alone.** No trust, no persistence, no configuration, nothing to manage.
A user who never touches F3 still gets working documents from this. That independence is
the reason it is worth building first.

**Quick Look gets none of it.** There is no chrome to put the affordance in and nothing to
persist a decision to, and a Load button in a panel that vanishes on the next space press
would train people to click grants without reading them. See "Quick Look is a different
surface" below.

**F8 — the name is Belvedere, and the bundle identifier moved with it.** `MDView` was
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
the Chinese overrides (title text is compound there, e.g. `退出 Belvedere`).

`MainMenu.xib` also carries `customModule="Markdown_Preview"` on the AppDelegate and
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

**F3 — trusted folders, security-scoped bookmarks, and the `/` read-only entitlement.**
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
reading. **Quick Look never honours trust**, for the reasons under F4.

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
F4's placeholder is shared between them, but a trusted folder says nothing about
`example.com`. Remote content stays click-to-load only unless someone deliberately designs
a per-host decision, which is a different axis and not part of either item.

**Sequencing.** F4 first, since it stands alone and needs no policy. Then this. Trust is
proposed upstream as the middle of three layers on #337; if they take it, it arrives
through them, and if they decline it becomes a fork feature.

## The About box states the fork's posture

`md-preview/App/AboutCopy.swift` holds the copy for both About surfaces — the
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
observation without establishing what produced it.

## Quick Look is a different surface

The two surfaces have drifted apart deliberately, and the divergence has now caused
confusion three times — the CSP split (F2/M3b), the containment scope (M4), and the vendor
loading mode behind B1. Collected here so it is one lookup rather than three.

| | Quick Look | App window |
|---|---|---|
| Base URL | `nil` — opaque origin | `md-asset:` base href |
| Scheme handler | **none registered** | `md-asset:` handler |
| Vendor bundles | `.inline` — embedded in the page | `.lazy` — fetched after first paint |
| Local images | rewritten to `data:` / `cid:` | served over `md-asset:` |
| CSP `img-src` | `data: cid:` | `md-asset: data:` |
| CSP `script-src` | `'unsafe-inline'` | `'unsafe-inline' md-asset:` |
| Containment | document folder, always | document folder; trust proposed (F3) |
| Editing, tabs, PDF export | none | yes |

Identical in both: `default-src 'none'`, remote images blocked, and the same DOMPurify
pass — both surfaces share `hostBridgeScript`, which is why the form-control fix landed in
both at once.

**The rule that generates all of it: Quick Look is reached by pressing space on a file
Finder selected, not one the reader chose.** There is no chrome to put an affordance in,
nothing to persist a decision to, and no deliberate act to attach a grant to. So the
policy is self-contained: everything the page needs is embedded before it loads, and
nothing it asks for afterwards is honoured.

**Every grant-shaped feature is app-window-only, permanently.** Click-to-load (F4) and
trust (F3) both need a button, a re-render and somewhere to remember a decision. A preview
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
`bin/build.sh --release` produces is uploaded as a GitHub Release on the tap repo,
and the cask points at it; the tap is public so no token is needed to install. Handing
the DMG out directly via the corporate share or Dropbox still works as a fallback. See
`docs/INTERNAL-INSTALL.md` for what recipients need to do — in particular, Quick Look
does not register until the app has been moved to `/Applications` and launched once.

## License

Upstream is MIT and this fork remains MIT. `LICENSE` is unmodified and upstream's
copyright notice stays intact.

---

*Fork cut 2026-09-01 from upstream `f8c22d0`.*
