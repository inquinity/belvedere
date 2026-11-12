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
| `swift-concurrency` (`.claude/skills/swift-concurrency/`) | [AvdLee/swift-concurrency-agent-skill](https://github.com/AvdLee/swift-concurrency-agent-skill), folder `skills/swift-concurrency/` | release 2.3.0 (2026-08-12), files copied 2026-10-06 | 2026-10-06 |

**On every sync, and before a release**, compare the copy with the source: list the source
folder with `gh api "repos/AvdLee/swift-concurrency-agent-skill/git/trees/HEAD?recursive=1"`,
compare each file's `git hash-object` with the listed blob sha, fetch the ones that differ,
and **read the diff before importing it**: a skill is instructions an agent will follow, so
treat its changes as untrusted input, the same as an upstream change to this project. Copy
`SKILL.md` and `references/*.md`. The source also ships `agents/openai.yaml`, logos and plugin
manifests, which this repository does not use. Record the release and date here.

2026-10-06: moved from `.agents/skills/` (retired with `AGENTS.md`) to `.claude/skills/`, where
it is now a real folder, not a symlink. Updated from the 2026-09-01 copy to 2.3.0: new
`references/observation.md` (`@Observable` and actors), a `SendableMetatype` section in
`actors.md`, an Approachable Concurrency row and two diagnostics rows in `SKILL.md`, and the
index entries. The diff was read first and held only documentation. `skills-lock.json` still
records the old install hash; it is provenance only, because nothing here runs the skills
installer.

---

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

- **Media only through `md-asset` (GH-627).** Upstream serves only images, audio, video
  and PDFs, but with no folder boundary. Belvedere keeps its containment and single-open
  read and adds the media rule inside `readContainedFile`, judged on the opened file's own
  path, before the rest of the file is read. With `script-src md-asset:` in the content
  policy, this also stops a `.js` file in the document's folder loading as a script.
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

### Waiting for a decision

- **Library updates (GH-630):** DOMPurify 3.4.2 → 3.4.17, highlight.js 11.12, KaTeX
  0.16 → 0.19, swift-markdown 0.9. Each must be checked against its published package,
  which needs a network fetch. Sparkle and Sentry bumps do not apply.
- **Features under evaluation:** Pele in place of Mermaid (GH-539, GH-596); every
  `[!type]` callout (GH-629); live math in the editor (GH-555); table column resizing
  (GH-564, on top of GH-476 and GH-563); EPUB export (GH-517, on top of GH-476's export
  rewrite); selection word counts (GH-534); text alignment (GH-480); the navigator's
  + menu and filter (GH-566, which adds `com.apple.security.files.bookmarks.app-scope`);
  removing the spare reader (GH-471).

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
