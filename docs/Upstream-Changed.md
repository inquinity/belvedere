# Upstream changes, and what Belvedere did with them

Every sync with Markdown Preview (`git merge upstream/main`) brings its changes into
Belvedere. Most arrive exactly as upstream wrote them. This file records the ones that
did not — taken with changes, or declined — and why, one section per sync, newest first.
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
- Everything else is **taken unchanged**; name the upstream releases it spans and let
  git hold the detail (`git log --no-merges <last sync>..upstream/main`).

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

---

## Markdown Preview 0.0.63 — synced 2026-09-29, ships in Belvedere 1.3.0

Merge `6ae7218` (on `sync/0.0.63`), into `main` as `b6717bf`.

### Taken with changes

- **Strict line breaks (#459) → "Line breaks".** Upstream added a *Strict line breaks*
  toggle to Settings › General › Reading. "Strict" reads as the opposite of what
  turning it on does — lines stop being kept and run together — so Belvedere shows a
  popup instead, called *Single new lines* since 1.4: *Break (like a comment)* (off) or *Reflow (like a
  README)* (on, **the default since 1.4**; it was *Keep as typed* before, as upstream still has it),
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
- **Deleting `CLAUDE.md`.** Upstream removed it; Belvedere keeps its one line,
  `@AGENTS.md`, which is what loads the fork's rules for Claude sessions. Git deletes
  it silently on a merge, so check for it after every sync.

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
