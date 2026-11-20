# Upstream changes, and what Belvedere did with them

Belvedere takes Markdown Preview's changes selectively. Until 0.0.63 every sync was a
`git merge upstream/main`; since 2026-11-12 changes are cherry-picked one at a time (see
`docs/FORK-NOTES.md`, "Syncing with upstream"). This file records what was taken with
changes, declined or found not to apply, and why, one section per round, newest first.
Each cherry-pick round names the last upstream commit it reviewed: start the next round
from there.
It is the place to look before a sync, so a decision made once is not quietly undone by
the next merge, and after one, to record what was decided.

It is not user-facing. Release notes say what changed for a reader
(`docs/release-notes/`); this says what we decided. Belvedere's standing differences —
no telemetry, no updater, the content policy, containment, click-to-load, the link
guard — and how each is carried through merges are in `docs/FORK-NOTES.md`, "How
changes are applied".

**On every sync**, add a section here listing:

- **Taken with changes** — what upstream did, what Belvedere does instead, and what
  keeps it that way (a posture test, a baseline entry, a note in a file header).
- **Declined** — what was left out, why, and how it is kept out on the next sync.
- **Kept ours** — files where Belvedere's version wins every time.
- **Taken unchanged** — for a cherry-pick round, list each pick; for an old merge, the
  releases it spans.
- **Not applicable** — upstream fixes for code Belvedere does not have.

Upstream PR numbers below refer to `pluk-inc/markdown-preview`.

## Review mark

Reviewed through upstream: `55a09b0` (2026-11-19)
Open pull requests last read: 2026-11-19

`bin/check-upstream.sh` and the monthly upstream watch read these two lines; keep their
wording. Move them forward when a round finishes reviewing: the commit to the newest
upstream commit read (taken, declined or found not to apply), the date to the day the
open pull requests were read. A pick taken out of order, ahead of the commits before
it, does not move the mark.

## Standing removals — keep them out on every sync

Files upstream carries that Belvedere deleted. A merge that finds upstream changed one
reports a modify/delete conflict; resolve it by keeping the deletion.

- `.github/FUNDING.yml` — it put a Sponsor button on this repository that sent money
  to upstream's maintainer. `docs/sponsors/` (their sponsors' logos) goes with it.
- `.agents/skills/amore-cli/` and its `.claude/skills/` link, and the `amore-cli` entry
  in `skills-lock.json` — documentation for Amore, upstream's distribution tool, which
  this fork does not use.
- `docs/markdown-logo.svg` — upstream's logo; nothing here references it.
- `belvedere/zh-Hans.lproj/` — the Chinese localization, removed in 2.0 because nobody here
  can maintain it. Upstream still updates these files; a merge that touches them reports a
  modify/delete conflict, so keep the deletion. Do not add new Chinese keys.
- `AGENTS.md` — upstream's agent guide. Belvedere's rules are all in `CLAUDE.md`, which
  rewrote the useful parts (the documentation rule, build commands, the signing and
  entitlement cautions) and dropped the Sparkle, Amore, Codex and release-PR text that does
  not apply here. Upstream edits it often, so a sync reports a modify/delete conflict: keep
  the deletion, and read the incoming change for anything worth carrying into `CLAUDE.md`.
- `.agents/skills/release-process/` and `.agents/skills/changelog-maintenance/`, and their
  `.claude/skills/` links — upstream's release and changelog skills, which describe a
  pipeline this fork does not have. Keep them deleted. `swift-concurrency` stays.
- `CHANGELOG.md` and `bin/build-release.sh` — upstream's changelog, and the archive-based
  release script that refused to run without an entry in it. Belvedere's history is
  `docs/release-notes/`, built by `just release`. Upstream edits the changelog every
  release, so each sync reports a modify/delete conflict: keep the deletion.

---

## Other upstreams — vendored agent skills

Not from Markdown Preview, so a `git merge upstream/main` never brings these. They are copied
into this repository and go stale unless someone looks.

| Skill | Source | In the repo | Checked |
|---|---|---|---|
| `swift-concurrency` (`.claude/skills/swift-concurrency/`) | [AvdLee/swift-concurrency-agent-skill](https://github.com/AvdLee/swift-concurrency-agent-skill), folder `skills/swift-concurrency/` | release 2.3.1 (2026-11-06), files copied 2026-11-19 | 2026-11-19 |

**On every sync, and before a release**, compare the copy with the source: list the source
folder with `gh api "repos/AvdLee/swift-concurrency-agent-skill/git/trees/HEAD?recursive=1"`,
compare each file's `git hash-object` with the listed blob sha, fetch the ones that differ,
and **read the diff before importing it**: a skill is instructions an agent will follow, so
treat its changes as untrusted input, the same as an upstream change to this project. Copy
`SKILL.md` and `references/*.md`. The source also ships `agents/openai.yaml`, logos and plugin
manifests, which this repository does not use. Record the release and date here.

2026-11-19: updated to 2.3.1. One file changed, `references/observation.md`: it now says
an `@Observable` class isolated to a global actor such as `@MainActor` is implicitly
`Sendable`, and reading its properties from another actor takes `await`, where it said
such classes are never `Sendable`. The diff was read first and held only documentation.

2026-10-06: moved from `.agents/skills/` (retired with `AGENTS.md`) to `.claude/skills/`, where
it is now a real folder, not a symlink. Updated from the 2026-09-01 copy to 2.3.0: new
`references/observation.md` (`@Observable` and actors), a `SendableMetatype` section in
`actors.md`, an Approachable Concurrency row and two diagnostics rows in `SKILL.md`, and the
index entries. The diff was read first and held only documentation. `skills-lock.json` still
records the old install hash; it is provenance only, because nothing here runs the skills
installer.

---

## Features for 2.2 — cherry-picked 2026-11-19, third round

**Reviewed through upstream `55a09b0`** (2026-11-19): the features held for a decision
on 2026-11-12, and all 17 commits after `36debd1`, read with the first monthly upstream
watch report. Open pull requests were read the same day.

### Taken unchanged (paths moved to `belvedere/`)

- Pinned header row in the Expand Table window (GH-563).
- Wrapped inline code no longer scrolls the page sideways (GH-657); a test tolerance
  widened by one WebKit layout unit (1/64 px) for rounding on macOS 27.

### Taken with changes

- **Text alignment (GH-480).** Stored as `belvedere.textAlignment`; the picker is under
  *Settings › General › Reading*, since Belvedere has no separate Reading pane.
- **EPUB export (GH-517).** Runs in Belvedere's hidden export page, so pictures are
  captured under the reader's folder boundary and content policy. The section check
  parses XML with external entities never loaded. EPUB finds the table control by the
  `data-md-app` marker. The test's stand-in image handler serves only inside the
  document's folder.
- **Selection word counts (GH-534).** Controls left out of a selection are found by the
  `data-md-app` marker. The reading view's task-checkbox callback beside it is not
  taken (see GH-470 below).
- **Column resizing (GH-564).** The scroller and column group it adds carry
  `data-md-app="table-scroll"` and `data-md-app="column-widths"`; every selector in
  Swift, JS and CSS uses those, not upstream's class and `data-mdp-resize` attribute,
  which a document could also write. Expand Table stays above the table's leading edge.
- **Live math in the editor (GH-555).** Upstream built it on Pele (declined), so the
  editor keeps Belvedere's Mermaid widget and fence handling and takes only the helpers
  maths needs: `fencedCodeNode`, `fenceInfoLanguage`, and `sourceTo`/`closed` returned by
  `fencedCodeDetails`. The editor loads KaTeX's stylesheet over `md-asset:`, so
  `PreviewContentPolicy` now allows `style-src 'unsafe-inline' md-asset:`; that
  handler serves only bundle files and, for user files, images with `nosniff`, which
  WebKit will not apply as a stylesheet. Pinned by `PreviewContentPolicyTests`.
- **Sentence after a display formula (GH-663).** Upstream's editor change hides `$$`
  while a formula's source is open; five of its own smoke assertions still expected
  them visible and were updated. The EPUB stylesheet hunk is kept.
- **Editor bundle libraries (GH-630, editor part).** Upstream's lockfile, renamed;
  installed with `npm ci --ignore-scripts`, all 95 packages pass `npm audit
  signatures`, and the build is byte-identical across runs. Every package in the bundle
  is Marijn Haverbeke's, under the existing CodeMirror notice.
- **Navigator + menu and filter (GH-566).** Write access to a folder lasts until
  Belvedere quits. Upstream saves it as a security-scoped bookmark, which needs
  `com.apple.security.files.bookmarks.app-scope` and leaves a lasting grant nobody can
  see or revoke; neither is taken. Lasting grants belong with the trusted-folders
  work. `ForkPostureTests.testFolderWriteGrantsAreNotSavedAsBookmarks` fails if either
  returns.
- **Navigator context menu (GH-659).** Applied by hand: Belvedere's navigator has
  diverged.
- **Copy as Plain Text (GH-637).** Merged upstream before the first round's mark but
  missed then; found by the monthly watch. The task-checkbox callback and test beside
  it are not taken.
- **Loading panel (GH-641), local files only.** The panel, the navigator spinner and
  the request IDs that drop a stale read. The download placeholder for Share as Link and
  release notes, and the `AppDelegate` and `ShareLinkOpener` changes, are not taken.
- **Plain-text source mode (GH-651).** Stored as `belvedere.editorSourceMode`; upstream's
  pre-macOS 26 formatting bar and tint fallback are not taken.
- Every pick: README, Chinese, Japanese, Persian, Polish and German strings not taken.
- **Known limit.** Copying, counts, Expand Table and EPUB find the code header and table
  controls by the `data-md-app` marker. The Mermaid zoom controls and the skipped
  `.mermaid`, `.mermaid-figure` and footnote back-link classes come from rendered HTML,
  which the sanitizer passes through, so a marker there would be stripped; a document
  that borrows those classes can keep its own text out of a copy or a book. That is the
  document hiding its own words, not reaching anything.

### Declined

- **Favorite folders (GH-646)** and the menu order that leans on it (GH-658): upstream
  re-roots the navigator without moving the folder boundary, so the tree and what a
  document may load would disagree. Revisit with trusted folders, where a favorite can
  be a deliberate, revocable boundary. Open GH-664 (reopen the last favorite) goes with it.
- **Editor context menu with photos from iPhone (GH-660):** a new input route
  (Continuity Camera images saved beside the file) not wanted for 2.2.
- **Removing the spare reader (GH-471):** Belvedere keeps it, behind its own setting.
- **Analytics (GH-655, GH-656):** the system language and exact macOS version added to
  upstream's daily-active event; Belvedere's reporter is a stub.
- German localization (GH-644, GH-649), Lokalise strings and its `AGENTS.md` section
  (GH-647), the sponsor credit (GH-645, `docs/sponsors/` is a standing removal), and
  upstream's release commits (GH-648, GH-654).

### Open upstream pull requests, read 2026-11-19

Decline if merged: the unsandboxed Quick Look takeover helper with its own URL scheme
that switches off other apps' extensions (GH-661); upstream's bundle-id move (GH-650)
and update feed for the old id (GH-652). Worth watching: image paste fixes (GH-614).

## Export rewrite — cherry-picked 2026-11-17, second round

Three picks, taken for the export rewrite that EPUB export (GH-517) and table column
resizing (GH-563, GH-564) build on. **The reviewed-through mark stays at `36debd1`**:
GH-653 is newer, but it is the only later commit read in this round.

### Taken with changes

- **Readable tables, an expanded table window and fitted exports (GH-476).** Export and
  printing are prepared from a hidden copy of the page (`DocumentExportSession`), with
  wide tables measured and fitted in WebKit (`ExportTableLayout`), and a table can open
  in a full-screen window (`TablePreviewWindow`). Changed for Belvedere:
  - The hidden copy's image handler takes the base folder **and the folder boundary**
    from the live page (`captureExportSession` reads `currentAssetBase` and
    `currentContainmentRoot`). Upstream set the base folder only, so a reader who had
    opened a wider folder would export under a different boundary from the one on
    screen. Printing no longer takes a separate asset folder.
  - The hidden page applies `PreviewContentPolicy` itself, loads with no base URL, asks
    `WebViewNavigationPolicy`, and allows only its own first load: no link, refresh,
    frame or new window after it. Upstream's page accepted any navigation.
  - `TablePreviewWindow.present` takes the boundary as a required parameter.
  - Table cells keep Belvedere's `overflow-wrap: break-word` (the fix for columns
    squeezed to one letter); upstream's `normal` would let one long string widen a
    column without limit.
  - The export file keeps the window's line-break setting, the app-bundle write guard
    and Belvedere's error domain. Upstream's README and Chinese strings were not taken.
  - Guarded by `ExportPageSecurityTests` and
    `ForkPostureTests.testExportCopyLoadsImagesUnderTheLivePageBoundary`.
- **Print from Finder (GH-653).** A print request from Finder, `open -p` or a script
  crashed the app; it now opens the print panel, always, without the sender's settings.
  Upstream waits on a first-paint flag from its launch work (GH-520, not taken), so
  Belvedere sets its own flag when the requested document reaches the page, and the
  hook that keeps a file chooser off the printing document only cancels a scheduled one.

### Taken unchanged

- **PNG export (GH-510).** Upstream's fix, in the export session that replaced the code
  Belvedere had fixed by hand in the first round.

### Not taken

- Upstream's later export changes for Pele (GH-539) and Share as Link (GH-571).

## Markdown Preview 0.0.64–0.0.72 — cherry-picked 2026-11-12, first round

**Reviewed through upstream `36debd1`** (2026-11-11, after 0.0.72). The next round
starts with `git log --no-merges 36debd1..upstream/main`. Open upstream pull requests
were read at the same time; see the end of this section.

This is the first round by cherry-pick. A trial merge of `upstream/main` had 90
conflicted paths, and would have brought in Share as Link, the update capsule and
three localizations, each to be cut out again on every later sync.

### Taken unchanged (paths moved to `belvedere/`)

- Image alt text kept (GH-497).
- Ordered-list markers from 100 on one line (GH-523), with the editor bundle rebuilt
  from `entry-cm.js` using the locked dependencies.
- Column held still while zooming in normal width (GH-545).
- macOS 27: sidebar row text plain when selected (GH-552).
- Search keeps its match when focus moves (GH-604).
- Escaped citations such as `\[18\]` left as text, and a bounds check on math
  placeholder tokens a document could spell (GH-633).
- Command-1 to Command-9 select tabs (GH-603).

### Taken with changes

- **Images only through `md-asset` (GH-627).** Upstream serves only images, audio, video
  and PDFs, but with no folder boundary. Belvedere keeps its containment and single-open
  read and adds a narrower rule inside `readContainedFile`, judged on the opened file's own
  path before the rest of the file is read: a file is served only with an `image/*` MIME
  type, from its extension or, for a file whose name does not say, from the lexical sniff
  click-to-load uses (`DeferredAssetLoader.imageMIMEType`; upstream asks ImageIO, whose
  TGA heuristic accepts text behind an 18-byte header). User files also go out with
  `X-Content-Type-Options: nosniff`. Audio, video and PDF are refused: the content policy
  cannot load them. Upstream's version would serve `.ts` (typed as a video stream) and
  `.icns` with no MIME type, as `application/octet-stream`, which WebKit runs as a script
  under `script-src md-asset:`. Quick Look does not use `md-asset`; its own inlining of
  local images (`InlineLocalAssets`) does not have this rule yet, upstream's neither.
- **PNG export (GH-510).** Upstream fixed it in `DocumentExportSession`, which Belvedere
  does not have; the same one-line move was made by hand in
  `MarkdownWebView+PDFExport.swift`. Upstream's pixel test needs that session; not ported.
- **File watcher descriptor (GH-623).** Belvedere already retried a deleted-then-rewritten
  file (`cf13211`). Only the descriptor fix was taken: each source's cancel handler now
  closes its own descriptor.
- **Formatting bar and tab bar on macOS 27 (GH-547).** Upstream's macOS 26 guard is
  dropped (Belvedere's minimum), and a test hunk that belongs to the native task
  checkboxes (GH-546, not taken) was left out.
- **Zoomed page first frame (GH-557).** Merged into Belvedere's render path, which also
  passes the line-break setting and the spare reader's preload flag.
- **Footnote numbers from 10 (GH-622).** The share viewer's stylesheet change dropped.
- **Quick Look heading links (GH-504).** Upstream's test drives the Quick Look controller,
  which `tests/swift-tests` does not build; not ported.
- Tests that came with these assumed upstream's tree: `md-preview/` paths, a
  `messageHandler` parameter on `WebViewLayoutHarness` (added), a nested `XCTUnwrap` the
  macOS 27.2 SDK's compiler rejects, and straight quotes where Belvedere's parser makes
  curly ones.
- **Library updates (GH-630), taken 2026-11-13.** Not picked: each library was fetched
  and checked on its own. DOMPurify 3.4.2 → 3.4.17, highlight.js 11.10 → 11.12, KaTeX
  0.16.45 → 0.19.1, swift-markdown and swift-cmark 0.8 → 0.9, each checked against its
  npm package (registry signatures, and build provenance where published), and DOMPurify
  and KaTeX also against their GitHub releases. The highlight.js script change (no theme
  CSS) is taken. Belvedere adds two things upstream does not have. First, it forbids
  `command` and `commandfor`, which DOMPurify began allowing after 3.4.2 and which let a
  button open a modal dialog without script. Second, it adds a license notice for the
  Babel helper now built into `purify.min.js`. Sparkle and Sentry bumps do not apply;
  the Pele bump is declined below.
- **Every `[!type]` callout (GH-629), taken 2026-11-14.** Picked as it was, except the
  fold chevron's mask is defined in the stylesheet (upstream builds it from a helper for
  diagram controls Belvedere does not have) and the share-server stylesheet is not taken.
  Belvedere adds a *Markdown flavor* setting: *Extended*, upstream's behaviour and the
  default, or *GitHub*, which keeps only GitHub's five alerts with the tag alone on its
  line and leaves everything else a quotation. The formatter, the page renderer, footnotes
  and the editor's spacing all follow it.

### Not applicable — fixes for code Belvedere does not have

- GPU-process DOM rendering on macOS 27 (GH-531): Belvedere never had the opt-out.
- Outline crash on `- #` (GH-628): the crash is in upstream's heading source lines,
  which Belvedere's outline does not read.
- File chooser at login-item launch (GH-624): Belvedere shows no chooser at launch.
- Editor list indent at a non-default zoom (GH-638): the registered length it fixes came
  with a later upstream change Belvedere does not have.

### Declined

- **Share as Link** (GH-567 to GH-619, `server/share-worker`, Universal Links): it
  uploads documents to upstream's service.
- **Update capsule and release notes after an update** (GH-613, GH-618, GH-642):
  Belvedere has no updater.
- **Custom app links with an Always Allow button** (GH-478): a document could open any
  app's URL scheme. Belvedere's sanitizer removes such links.
- **Task toggles in the reading view** (GH-470): reopens the page-to-file write path the
  read-only reading view (GH-456) closed.
- Japanese, Persian and Polish localizations and language switching (GH-474, GH-516,
  GH-543, GH-532, GH-472, GH-530); the coffee and Discord links (GH-601); upstream's dark
  icon (GH-607); upstream agent tooling (CodeRabbit, the `pull-requests`, `resolve` and
  `headless-ui-test` skills, whose `vdisplay.m` uses a private API).
- **Pele in place of Mermaid** (GH-539, GH-596, and the Pele bump in GH-630): declined
  for now. Pele was about four weeks old, Mermaid is what GitHub and most other tools
  render with, and Pele draws diagrams in its own style. Belvedere updates Mermaid
  instead. The checkpoints for revisiting are under UF2 in `docs/FORK-NOTES.md`.
  *On later rounds:* upstream changes to `MarkdownHTML+Mermaid.swift`, the diagram
  popup and the editor's diagram widget assume Pele; read them for fixes that also
  apply to Mermaid, and do not pick them as they are.

### Waiting for a decision

- **Editor bundle npm updates (GH-630):** `codemirror-lang-hcl` 0.2 and esbuild 0.28,
  with upstream's override that keeps HCL block types and labels coloured as before.
  Not taken with the other library updates; taken in the third round (2026-11-19).
- **Features under evaluation:** all decided in the third round (2026-11-19).

### Open upstream pull requests, read 2026-11-12

Worth watching: a loading panel for slow cloud files (GH-641), image paste fixes
(GH-614), relative Markdown links from Quick Look (GH-505). Declined if merged: Quick
Look links that launch the app through a private host API (GH-514), German localization
(GH-361).

---

## Markdown Preview 0.0.63 — synced 2026-09-29, ships in Belvedere 1.3.0

Merge `6ae7218` (on `sync/0.0.63`), into `main` as `b6717bf`.

### Taken with changes

- **Strict line breaks (#459) → "Line breaks".** Upstream added a *Strict line breaks*
  toggle to Settings › General › Reading. "Strict" reads as the opposite of what
  turning it on does — lines stop being kept and run together — so Belvedere shows a
  popup instead, called *Single new lines* since 2.0: *Break (like a comment)* (off) or *Reflow (like a
  README)* (on, **the default since 2.0**; it was *Keep as typed* before, as upstream still has it),
  with an ⓘ popover explaining both (`InfoPopoverButton`, a fork file). It is the
  same stored Bool, `belvedere.strictLineBreaks`, so Quick Look and the renderer
  are upstream's, unchanged. English strings only; upstream's two keys are removed
  from the `.strings` file.
  *On the next sync:* `GeneralSettingsView.swift` will conflict if upstream touches
  that row; keep the popup.
- **Open documents faster (#450) — without reopen snapshots.** Taken: the spare reader
  (a web view prepared after the first document paints) and the change that stops
  pages using user-installed fonts. **Removed entirely:** reopen snapshots.
  `DocumentSnapshotCache` wrote a PNG of each opened document's first screen to the
  app's Caches folder — up to 40, pruned only by count, never when the document
  closed or was deleted — and chose exactly the plain-text documents, the likeliest to
  be private. An off switch would still ship the code, and the code itself is the
  liability. Deleted: `DocumentSnapshotCache.swift` and its call sites in
  `ContentViewController`, `MainSplitViewController`, `DocumentWindowController` and
  `MarkdownDocument`, plus `MarkdownWebView.lastDisplayMayChangeAfterFirstPaint`.
  `ReaderRenderSettings.fingerprint`, which only snapshots read, is left in upstream's
  file and listed in `docs/dead-code-baseline.txt`.
  *Kept out by* `ForkPostureTests.testDocumentSnapshotsStayRemoved`. Expect conflicts
  on any sync that touches those files; resolve them without the snapshot code.
- **Read-only reading view (#456).** Taken as-is — it removes three ways a page could
  ask the app to write the file, which suits Belvedere. The merge conflicts in
  `MarkdownHTML+HostBridge.swift` and `MarkdownWebView.swift` were resolved keeping
  the fork's sanitizer set-up, blocked-image deferral and click-to-load messages. The
  fork's own docs that said task checkboxes are clickable in the reading view were
  corrected in the merge.

### Declined

- **What's New window (#453).** Never shown. It describes Markdown Preview's releases,
  is branded as that app, links to upstream's GitHub, and compares upstream's build
  numbers (66 and up) with Belvedere's (13 and up), so it would open for every
  Belvedere reader on every upstream bump. First the launch hook, the Help-menu item
  and the automatic presentation were removed and the files left unreferenced; on
  2026-10-01 the files, their strings and their tests were deleted too.
  *Kept out by* `ForkPostureTests.testWhatsNewIsNeverPresented`. If upstream edits
  `Features/WhatsNew/`, a merge reports a modify/delete conflict: keep the deletion.
- **`CLAUDE.md` is ours alone.** Upstream removed theirs; Belvedere's holds the fork's
  rules and, since 2.0, the whole agent guide, with upstream's `AGENTS.md` retired (see
  *Standing removals*). If a merge brings `CLAUDE.md` back or deletes it silently, check
  it after every sync and keep ours.

### Kept ours

`Version.xcconfig` (Belvedere's own version line), `README.md` (Belvedere's own; the
new setting is described there as *Line breaks*).

### Checked

Security review of the incoming diff found no new network access and no change to
the content policy, sanitizer, containment, link guard, entitlements or Quick Look's
policy. Ten editor and layout tests fail on this Mac exactly as they do on untouched
upstream.

---

## Markdown Preview 0.0.59 to 0.0.62 — synced 2026-09-25, ships in Belvedere 1.3.0

Merge `4649c0b`, into `main` as `fe0c48b`.

### Declined

- **Performance CI workflows (#406).** Upstream's `performance.yml` and
  `performance-report.yml` compare benchmarks and report on pull requests. Belvedere
  does not use that reporting, and the workflows would run on macOS runners for every
  push and post PR comments with write scope; removed in `05ac773`. The benchmark
  scripts and tests they call (`scripts/bench`, `tests/performance`) are kept,
  unchanged, so merges stay clean. *On the next sync:* delete the two workflows again
  if they come back.

### Kept ours

`Version.xcconfig`, `README.md`.

### Taken unchanged

Everything else, including Search for Document (#408), the new code blocks (#425),
floating Liquid Glass controls (#424), theme appearance locking (#421), Mermaid
11.15.0 (#441) and the editor, scrolling and theme fixes in between.
