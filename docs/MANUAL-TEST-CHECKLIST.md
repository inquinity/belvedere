# Manual test checklist

What to look at before handing out a build, and how to tell a pass from a
failure. Written for whoever is doing the release check — which is usually one
person with a laptop, not a CI job.

Two things this exists to prevent:

- **A known limitation read as a regression.** Time gets spent re-diagnosing
  something already understood.
- **A regression read as a known limitation.** Worse, and it has already
  happened here: Mermaid did not render in Quick Look for several releases and
  was written off as expected behaviour. It was a bug, and it is fixed — a
  failure there now is a real regression.

Fixtures under `tests/fixtures/` carry their expectations **in the document
itself**, as `EXPECT` / `FAIL IF` notes you read while looking at the rendered
page. This file covers `samples/`, which is upstream's and deliberately left
unannotated so it merges cleanly.

## If you changed behaviour, re-read the expectations first

**Before running this checklist against a change, re-read the `EXPECT` notes in
every fixture the change could touch, and fix any that are now false.** Do it in
the same commit as the behaviour change, not afterwards.

This is not tidiness. A stale expectation asserts the *opposite* of what the
code now does, and a tester trusts it — so the failure mode is reporting a
correct result as a bug, or worse, reading a real regression as a known
limitation. That has happened five times in this repository:

- `path-traversal.md` said containment did not exist, three releases after it
  shipped.
- The Mermaid example described a fixed bug as an accepted Quick Look
  limitation — which is exactly how the bug survived several releases in the
  first place.
- `post.md` told a tester to expect a broken-image icon for a missing file
  after placeholders replaced them.
- `post.md` gave one expectation for both surfaces after they diverged, so
  Quick Look read as failing when it was correct.
- `inline-html.md` said to expect nothing where a placeholder now appears, and
  called task checkboxes unclickable after clicking them became a feature.

Every one was written accurately and went stale when something else changed.
The fixtures are only useful while they are true, so treat them as part of the
behaviour rather than as notes about it.

## Before you start

```bash
./bin/build.sh
SOURCE_APP=build.noindex/Belvedere.app ./bin/install.sh   # required for Quick Look to register
qlmanage -r && qlmanage -r cache
```

Quick Look will not pick up a new build until the app has been in
`/Applications` and launched once. If Quick Look looks stale, it is stale.

## 1. Security fixtures — read the notes in the files

| File | What it proves |
|---|---|
| `tests/fixtures/security/inline-html.md` | Sanitisation. **Most sections collapse to nothing, and that is the pass.** Judge the *control*, not the words: a stripped element leaves its text behind, so the credential section may show an inert "Sign in" with no button under it. A **text field you can click into**, or a button that behaves like one, means stop and do not ship. Also check the task list still toggles — clicking a checkbox writes back to the file. |
| `tests/fixtures/security/path-traversal.md` | Containment. Every image must be a placeholder naming the file, with a **Load** button — these sit outside the document's folder, so the reader is offered the choice. Clicking Load must report a failure, never show contents: any file contents on screen is a document reading files it has no right to. |
| `tests/fixtures/security/remote-beacon.md` | Tracking pixels. Nothing loads on open: every image is a placeholder naming the host, page still styled normally. In the app window each offers **Load** — that is the reader asking, and it is the only thing that reaches the network. Quick Look offers no button. **Load all** must not appear for these; it covers local files only. |
| `tests/fixtures/relative-assets/post.md` | The other half: containment must not break *legitimate* relative images. Two must render, two must not. |

Open each in **both** the app window and Quick Look. They resolve assets by
different mechanisms and have failed independently before.

### Why "it looks empty" is not the same as "it is safe"

DOMPurify defaults to `KEEP_CONTENT: true`: a forbidden element is removed and
its children are **kept and reparented**. That has bitten this project twice,
in opposite directions.

- **A real hole read as safe.** `FORBID_TAGS` listed `form`, so `<form>`
  disappeared — while the `<input>` and `<button>` inside it survived on their
  own and drew a working credential prompt. The automated test asserted
  `forms == 0`, which was true, and passed for as long as the bug existed. The
  fix forbids the controls; the test now counts them.
- **A pass read as a failure.** With the controls forbidden, the button's label
  survives as ordinary text. "Sign in" on screen with nothing behind it is the
  system working.

So the question to ask of this fixture is never "is the section empty" but
**"is there anything here I can type into or click".**

### Proving no request left the machine

A blocked placeholder is consistent with the request being refused *and* with the
host simply not resolving. To confirm the block itself, watch the network while
opening `remote-beacon.md` — and do not click **Load**, which is a request you
made and should appear:

```bash
sudo tcpdump -n -i any 'tcp port 80 or tcp port 443' | grep -i example
```

Nothing should appear. This is the check that actually distinguishes "blocked"
from "failed to connect", and it is worth doing when the CSP changes.

### Checking click-to-load for remote images

The other half needs a host that answers, which `example.invalid` never does.
Serve one locally instead, so the whole check stays on the machine:

```bash
mkdir -p /tmp/mdshots && cd /tmp/mdshots && python3 -m http.server 8731 --bind 127.0.0.1
```

Point a document at `http://127.0.0.1:8731/<an image you put there>` and open it
in the app window. Expected, and each line is a separate claim:

- On open: a placeholder, and **no request in the server log**.
- One click on **Load**: the image appears, and the log shows **exactly one**
  GET. Click a second remote placeholder and it asks again — grants are never
  remembered, not even for the same host.
- A URL on a host that does not resolve: `load failed: no answer from the host`,
  and the button is removed.
- A response that is not really an image: `load failed: not an image`. Serving
  it as `Content-Type: image/png` must not change that — the bytes are what is
  checked.
- A redirect to a `file:` URL must be refused without reading the file, and a
  redirect chain must stop after three hops. Both need a server that redirects;
  `docs/FORK-NOTES.md` (*Click-to-load for deferred content*) records what was verified and how.
- An oversized response — one that declares 100 MB, and one that declares no
  length and never stops — must both come back `load failed: too large`, the
  second with the server reporting a broken pipe. Watch the app's memory in
  Activity Monitor while it runs: it must stay flat.
- In **Quick Look**, the same document shows the same placeholders with **no**
  Load button at all.

## 2. Upstream samples

| File | Expected | Notes |
|---|---|---|
| `samples/full.md` | Everything renders | The broad smoke test |
| `samples/codeblocks.md` | Syntax highlighting, working copy buttons, **Mermaid diagram renders** **and shows all five HUD controls** (zoom out, reset, zoom in, fill width, open in window) | Mermaid in Quick Look was broken until 1.0.3. It must render now, in **both** surfaces. **Count the HUD buttons, don't just check the diagram drew:** the controls are emitted as article HTML and pass through the sanitiser, so a sanitiser change can delete them while the diagram still renders perfectly. That shipped in 1.0.4 and 1.0.5 |
| `samples/mermaid-heavy.md` | Ten diagram types render | Only diagrams near the viewport render at first; the rest fill in as you scroll. **That is the design, not a failure** — rendering is gated on an `IntersectionObserver` |
| `samples/long-footnotes.md` | Footnote links jump both ways | |
| `samples/navigation.md` | In-document links work | |
| `samples/rtl-test.md` | Right-to-left text lays out correctly | |
| `samples/toml-frontmatter.md` | Frontmatter handled, not dumped as body text | |

## 3. Surfaces

Check each sample in the surface it matters for:

- **App window** — the main reader
- **Quick Look** — select the file in Finder, press space. The copy button
  must not overlap the document text (it had no clearance at all before 1.0.3)
- **Print / PDF export** — Mermaid and maths must appear in the output, not
  just on screen
- **Editor** — open, type, save

## 4. The About box

Two surfaces, and they must agree — the app menu's **About Belvedere** panel and
**Settings → About**. `AboutCopy` is shared between them so they cannot drift,
but the panel and the SwiftUI pane lay it out independently, so look at both.

| Check | Why |
|---|---|
| Version reads `Version 1.1.0`, once | The panel supplies the word "Version" itself. Passing an already-prefixed string renders **"Version Version 1.1.0"** — it did, during this work |
| No build number; a dev build says so | Deliberate. `bin/build.sh` moves `CURRENT_PROJECT_VERSION` in lockstep with `MARKETING_VERSION`, so for a release it carries no information the version does not. A release reads `Version 1.3.1`. Any other build reads `Version 1.3.1 (dev de8c399+)` — the commit, with `+` for uncommitted changes — and one run from Xcode reads `(dev build)`. Check this line to confirm you are testing the build you think you are |
| Tagline and security line both present | The security line is a **claim about behaviour**. If the app ever connects on its own, or stops blocking remote content by default, the line is false and must change with the code |
| The tagline breaks after "viewer," in the **menu panel** and runs on one line in **Settings → About** | Deliberate, not a bug. The panel is narrow enough to wrap mid-clause, so it uses its own localized string with the break in it (`taglineWrapped`); the pane is wide enough for the unbroken form |
| The security line breaks after "on its own." in **both** | Two different guarantees — the app, then document content. They should not run together |
| The repository link opens `github.com/inquinity/belvedere` | |
| **Acknowledgements**, below it — with a little space between the two links in the menu panel — opens `Acknowledgements.md` in the default Markdown app: one line each for Markdown Preview, swift-markdown, swift-cmark and the six JavaScript libraries, "*X* is used under the *license*", each license a link to that project's repository | A file rather than an in-app window, on purpose: the standard About panel opens its links itself, so a file is the one target both About surfaces can share. The license texts are not on the page by design; they ship in `Contents/Resources` |
| Open **Acknowledgements** (About ▸ Acknowledgements) and press ⌘E: an explanation appears and there is **no editor**. Repeat with File ▸ Open… on the same file in **another** Belvedere, such as `/Applications/Belvedere.app/Contents/Resources/Acknowledgements.md` while you run a build from `build/`: also refused. Then `codesign --verify --deep --strict` on both apps must still pass | The page lives inside a signed bundle, and a dev build and an installed Belvedere are the same developer, so one can modify the other. Since 1.3.1 any document inside an application bundle cannot be edited, so there is nothing to save; before that a read-only flag was the only guard. Testing only the running app's own copy missed this once |
| On that same page choose **Save As…** and pick your Desktop: the copy is written and the window follows it, and the copy *can* be edited. Choosing a location inside `Belvedere.app` in the panel is refused with the same explanation | Save As… to a copy is the supported way to change a bundled page |
| With any document, File ▸ Export (HTML) and choose a folder inside `Belvedere.app`: refused, nothing written | The export panel is one of the places the guard is applied |
| In Chinese (`zh-Hans`) both lines are translated | Missing keys fall back to English and give a half-translated box. **The zh-Hans strings for the tagline, security line and "Acknowledgements" (致谢) have not been checked by a native reader** |

## 5. Saving and leaving edit mode

From the Save-button work, offered upstream in [PR #379](https://github.com/pluk-inc/markdown-preview/pull/379) and closed there without merging, so it is ours alone.

| Check | Why |
|---|---|
| The default toolbar has an icon-only **Save** button after Edit — not beside Share, whose icon it mirrors — dimmed with nothing to save, lit after the first keystroke. Check the default set in *View → Customize Toolbar…* | Belvedere keeps Save in the default toolbar; Markdown Preview does not. That is a deliberate difference, not a merge mistake |
| Leaving edit mode (toolbar, ⌘E, Escape) with changes asks **Save / Revert… / Continue**; with no real change it asks nothing | Typing a character and deleting it leaves "Edited" showing, but there is nothing to decide, so no prompt |
| Escape on that prompt means **Continue**: back to preview, draft kept, file on disk untouched | Escape is itself one of the ways out; pressing it twice must neither lose nor write anything |
| After Continue, **⌘S** and File › Save… still write the draft | They used to be disabled there — the only way to write the draft was to close the window |
| Revert… and File › **Revert to Saved** (⌘R) confirm first; on that sheet Return does nothing and Escape cancels | Deliberate: Cancel takes Escape and Revert is marked destructive, so Return can never discard edits |
| **Save As…** opens a panel pre-filled with the current name and folder; the window follows the new file and the original is untouched | Offered with or without changes. An untitled document gets the same panel as Save |
| Menu states: Save and Revert to Saved **off** with nothing changed; Save As… **on** for any open document | Revert also stays off for an untitled document — there is nothing on disk to go back to |
| Settings › General › Editing › *Leave edit mode without asking to save* restores the silent exit | Off by default; takes effect on the next exit without reopening the window |

## 5b. Opening a folder

**File ▸ Open Folder…** has its own panel that can only choose folders, and no shortcut.
Go to File… (it was Search for Document) keeps ⇧⌘O. Open `tests/fixtures/relative-assets/post.md` first.

| Check | Why |
|---|---|
| File ▸ Open Folder… is in the File menu, right after Open…, with no shortcut, and Go ▸ Go to File… shows ⇧⌘O and File has no search item | Added with the fix for opening folders from inside the app. ⇧⌘F is kept free for a future search of text in the folder |
| Pick `tests/fixtures` and press **Open**: the sidebar roots on `fixtures` and the shared logo in `post.md` renders | The folder widens the document's boundary |
| With nothing selected in the panel, **Open** is enabled and chooses the folder being shown | The old Open… panel disabled it, so a reader could not choose the folder they were in |
| Selecting a folder in the panel and pressing **Open** chooses it and does not drill in | The reported fault in Open… |
| With every window closed, File ▸ Open Folder… still works and opens a window on the folder | It is the app's own command, not a window's |
| Go to File with no folder open shows **Open Folder…**, and the button opens this same panel | It used to open the Open… panel |

| Drop a folder on the Belvedere icon in the Dock: the folder opens, and the sidebar roots on it | `Info.plist` now declares folders as something it can open. Launch Services reads that when the app is first registered, so after a rebuild it may need `lsregister -f` on the app |
| Belvedere is not the default for folders, and Finder's right-click menu offers no Open With for one | It is ranked Alternate, so it must never take over folders. Checked 2026-10-01: Finder shows no Open With for a folder, which is acceptable |

Dropping a folder on a window is not covered yet.

## 5c. Editing a table

Open `tests/fixtures/editor/table-cells.md` and follow the numbered sections in it; each
carries its own **EXPECT** and **FAIL IF**. Do this on every macOS version you ship for,
and always on a new one.

| Check | Why |
|---|---|
| Section 1: clicking a formatted cell reveals its Markdown with the caret where you clicked | Nine automated tests of this failed on macOS 27 because the test harness had no window, not because of the editor. They pass now, but only a real window on macOS 27 proves the editor itself |
| Sections 2 to 4 and 6: drag-select, format, link and leave edit mode | The remaining automated table tests cover these with synthetic events |
| Section 5: Tab, Shift-Tab and Enter select the next cell's text | Found by hand on 2026-10-03: they only moved focus, and the shaded cell looked selected when it was not. Fixed for 1.4 |

Not covered by this fixture: row and column editing, pasting a table, and right-to-left or CJK cells.

## 5d. Content width

Use a long document, such as `docs/FORK-NOTES.md`, so there is something to scroll.

| Check | Why |
|---|---|
| A new window shows **Full Width**: widen it and the text follows; narrow it and the text follows back down | The saved default is Full Width. Before 1.4 a wide window was mostly margin |
| Scroll to the middle, then View ▸ Content Width ▸ **Quick Look Width**: the same text is still at the top of the window, and the text is now a centered column | Changing the width re-renders the page, which used to jump back to the top |
| The same, switching back to **Full Width** | |
| Open a second window: it is still Full Width. Only the first window changed | View ▸ Content Width is per window and is not saved |
| Quit and reopen: the window is Full Width again | Not saved |
| Settings › General › **Default content width** ▸ Quick Look Width: **no open window or tab changes**; open a new window and a new tab: both use Quick Look Width | The default reaches new windows and tabs only. Open ones keep the width they opened with |
| With the View menu open, the check mark is on the front window's width, and moves when you switch windows | The menu follows the front window, not the default |
| Press ⌘E in each width: the editor column matches, and changing the width while editing re-flows it and keeps your place | The editor follows the same width |
| Change **Font** in Settings while scrolled halfway: the position holds | Any setting that re-renders the page had the same jump |

Not covered here: the zh-Hans strings, which nobody has checked, and Quick Look itself, which does not change.

## 6. Release build

For a `--release` build, verify the artifact rather than trusting the log:

```bash
xcrun stapler validate "dist/Belvedere-<version>.dmg"
spctl -a -vvv -t open --context context:primary-signature "dist/Belvedere-<version>.dmg"
```

Both must pass. Then **check it on a second Mac** — one that has never run this
app and never had the developer certificate. That is the only test of what a
colleague actually experiences, and it has caught problems that every local
check missed.

## Known limitations — not regressions

- **Remote images do not load on their own.** Deliberate: it closes the
  tracking-pixel hole. Each shows as a placeholder naming its host, so README
  badges look like placeholders. In the app window, **Load** fetches that one
  image on a click; Quick Look names the image but offers no Load.
- **No automatic updates.** Sparkle is removed; new versions arrive through
  `brew upgrade --cask belvedere`.
- **The command line tools are gone.** The installer is orphaned and its
  Settings button was removed in 1.0.3.
