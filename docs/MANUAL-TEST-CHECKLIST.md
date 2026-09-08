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
./scripts/build.sh
SOURCE_APP=build/Belvedere.app ./scripts/install.sh   # required for Quick Look to register
qlmanage -r && qlmanage -r cache
```

Quick Look will not pick up a new build until the app has been in
`/Applications` and launched once. If Quick Look looks stale, it is stale.

## 1. Security fixtures — read the notes in the files

| File | What it proves |
|---|---|
| `tests/fixtures/security/inline-html.md` | Sanitisation. **Most sections collapse to nothing, and that is the pass.** Judge the *control*, not the words: a stripped element leaves its text behind, so the credential section may show an inert "Sign in" with no button under it. A **text field you can click into**, or a button that behaves like one, means stop and do not ship. Also check the task list still toggles — clicking a checkbox writes back to the file. |
| `tests/fixtures/security/path-traversal.md` | Containment. Every image must be a broken-image placeholder. Any file contents on screen is a document reading files it has no right to. |
| `tests/fixtures/security/remote-beacon.md` | Tracking pixels. Every image broken, page still styled normally. |
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

Broken images are consistent with the request being blocked *and* with the host
simply not resolving. To confirm the block itself, watch the network while
opening `remote-beacon.md`:

```bash
sudo tcpdump -n -i any 'tcp port 80 or tcp port 443' | grep -i example
```

Nothing should appear. This is the check that actually distinguishes "blocked"
from "failed to connect", and it is worth doing when the CSP changes.

## 2. Upstream samples

| File | Expected | Notes |
|---|---|---|
| `samples/full.md` | Everything renders | The broad smoke test |
| `samples/codeblocks.md` | Syntax highlighting, working copy buttons, **Mermaid diagram renders** | Mermaid in Quick Look was broken until 1.0.3. It must render now, in **both** surfaces |
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

## 4. Release build

For a `--release` build, verify the artifact rather than trusting the log:

```bash
xcrun stapler validate "dist/Belvedere <version>.dmg"
spctl -a -vvv -t open --context context:primary-signature "dist/Belvedere <version>.dmg"
```

Both must pass. Then **check it on a second Mac** — one that has never run this
app and never had the developer certificate. That is the only test of what a
colleague actually experiences, and it has caught problems that every local
check missed.

## Known limitations — not regressions

- **Remote images do not load, anywhere.** Deliberate: it closes the
  tracking-pixel hole. README badges appear broken. Deferred improvement is
  F4, a click-to-load control like a mail client's.
- **No automatic updates.** Sparkle is removed; new builds are handed out by
  hand.
- **The command line tools are gone.** The installer is orphaned and its
  Settings button was removed in 1.0.3.
