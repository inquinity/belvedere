# Belvedere — agent guide

A sandboxed macOS app for reading and editing Markdown, with a Quick Look extension.
AppKit and SwiftUI, a `WKWebView` reader, a CodeMirror editor. This is
**[inquinity/belvedere](https://github.com/inquinity/belvedere)**, a fork of
[pluk-inc/markdown-preview](https://github.com/pluk-inc/markdown-preview) ("upstream") that is
moving its own way. Documents come from other people, so it is security-centric: no telemetry, no
updater, no network except what the reader asks for.

Read these before acting on anything they cover:

- [docs/FORK-NOTES.md](docs/FORK-NOTES.md) — how this fork differs from upstream, and why. The
  source of truth for posture, branch model and per-item notes.
- [docs/ROADMAP.md](docs/ROADMAP.md) — what is planned, open and done.
- [docs/Upstream-Changed.md](docs/Upstream-Changed.md) — upstream changes Belvedere reshaped or
  declined, and the files kept deleted. Read it before a sync; add a section after one.
- [docs/RELEASE-AUTOMATION.md](docs/RELEASE-AUTOMATION.md) — releasing.
- [docs/MANUAL-TEST-CHECKLIST.md](docs/MANUAL-TEST-CHECKLIST.md) — hand tests.

## Project facts

| Thing | Value |
|---|---|
| Product / bundle id | `Belvedere` / `com.altmansoftwaredesign.belvedere` (`.quick-look`, `.dev`) |
| Xcode | `belvedere.xcodeproj`, scheme `belvedere`, Quick Look target `belvedere-quick-look` |
| Team | `45GJWJVQN2` |
| Minimum macOS | 15.0 |
| Updates | none; distributed as a Homebrew cask, `inquinity/tap/belvedere` |
| Version | `Version.xcconfig`, bumped by `bin/build.sh --update` (the fork's own line, independent of upstream's `0.0.x`) |

**Naming.** Paths and identifiers are lower-case (`belvedere`, `belvedere-quick-look`,
`belvedere://`, `belvedere.*` settings keys). The capitalised `Belvedere` is for names a person
reads: the app, About, menus, release notes.

## Common commands

Fork tasks run through `just` (`brew install just`; `just --list`).

```bash
just build                       # local build into build.noindex/, signed and notarized if credentials exist
just release <major|minor|revision>   # bump, build DMG, compose notes, commit, tag, dry-run publish
just publish --go                # publish the release at HEAD; a dry run without --go
xcodebuild -project belvedere.xcodeproj -scheme belvedere -configuration Debug build
(cd tests/swift-tests && swift test --disable-automatic-resolution)
periphery scan                   # compare with docs/dead-code-baseline.txt
```

Fork-authored scripts live in `bin/`; `scripts/` holds only upstream's tooling, so a sync never
touches `bin/`. **Never build, notarize or publish a release without an explicit go-ahead.** A
build a person will test must be handed over with its About-box build string and app path.

## How this fork works

- **Remotes and branches.** `origin` is inquinity, `upstream` is pluk-inc. Sync with
  `git merge upstream/main`. **Never rebase `main`**; it is published. Work on `feat/*`, `fix/*`
  and `chore/*` branches and merge with a `Fork: …` message.
- **Upstream issues and PRs** are worked on a `contrib/<topic>` branch cut from `upstream/main`,
  never on `main`. Everything behind a claim in the PR or reply (building, running, manual
  tests, screenshots) uses a **Markdown Preview build of that branch**, not Belvedere: Belvedere
  carries the same fix plus the fork's hardening, so a result there says nothing about what
  upstream will merge. Carry the fix into `main` afterwards. Open PRs ready for review, never as
  drafts. For a local test install of an upstream build, blank `SentryDSN` and `SUFeedURL` and
  set `SUEnableAutomaticChecks` to false in a local commit that is never pushed.
- **On a sync:** review all incoming changes for security with the `security-oss-app-reviewer`
  skill; keep our `Version.xcconfig` and `README.md`; keep the files listed under *Standing
  removals* in `docs/Upstream-Changed.md` deleted (a modify/delete conflict means keep the
  deletion), including `AGENTS.md` and `CHANGELOG.md`.
  Also check the vendored `swift-concurrency` skill against its own source (see
  *Other upstreams* in `docs/Upstream-Changed.md`) and read the diff before importing it.
- **Deliberately dead code**: the orphaned CLI installer and the stubbed telemetry reporters stay.
  Do not remove them.
- **Quick Look:** with Belvedere installed, both extensions claim `.md` and macOS picks one.
  Check the preview's "Open with" button before trusting a result.
- **Concurrent sessions.** Other agent sessions work in this repo. Check `git status` and
  `git log` before editing, and never conflict with in-flight work: wait, or coordinate.
- **Finishing a long task:** run `say "<project> <what the session did> is ready for your review"`.

## Signing and secrets

- `DEVELOPMENT_TEAM = 45GJWJVQN2` (in `project.pbxproj`, both targets) is this fork's team, set
  on purpose. Never let Xcode rewrite it to another team; check `git diff` of `project.pbxproj`
  before committing and revert that hunk if it appears. Leave `CODE_SIGN_STYLE` alone too.
- `belvedere.entitlements` and `belvedere-quick-look.entitlements` hold narrowly scoped sandbox
  exceptions (including the read-only filesystem exception; see the trusted-folders item in the
  roadmap). Do not broaden or tidy them without reading the inline comments.
- Secrets live in `Secrets.xcconfig` (gitignored; copy `Secrets.xcconfig.example`). Never put a
  real token in a tracked file, `Info.plist` or a commit.

## Documentation that describes behaviour is part of the behaviour

**If a change makes a documented claim false, updating that claim is part of the change — same
commit, not a follow-up.** This covers `README.md`, sample and fixture files, the manual-test
checklist, the release notes, and any comment that tells a reader what to expect on screen.

A stale claim asserts the *opposite* of what the code does, and people trust it. A correct result
gets reported as a bug, or a real regression gets waved through as a known limitation. The second
happened here: the README said Mermaid diagrams render in Quick Look after they had stopped, and
the mismatch was read as documentation drift, which is part of why the bug survived several
releases. When you change what the reader sees, grep for what says otherwise:

```bash
grep -rn "<the behaviour you changed>" README.md samples/ tests/fixtures/ docs/
```

A change a Belvedere user would notice also gets a bullet in `docs/release-notes/UNRELEASED.md`,
in the same commit: reader value only, never what was declined or internal housekeeping.

## Writing for other people — commits, PRs, issue replies

This fork is **public**. Every commit message, PR description, and issue or PR comment is
readable by anyone, upstream maintainers and strangers included. A fork commit whose message
contains `#337` (or `pluk-inc#337`) is auto-linked into the upstream PR's timeline permanently;
those entries cannot be deleted. Point at upstream with a full URL or a non-linking form
(`GH-337`), never a bare `#337`.

**No fork-internal shorthand in anything that can travel.** Item IDs (`F4`, `M4`), `FORK-NOTES`,
roadmap codenames mean nothing to upstream and nothing to us in six months. Write the actual
subject: "the trusted-folders pane", not "S7".

**Commit messages are for the person reading them in 6–12 months** with no memory of today, often
you. Say what changed, why, and what breaks if it is reverted.

**Keep issue and PR replies short and focused.** Lead with the answer or the decision; cut the
throat-clearing and the restated context. Short is not an excuse to drop load-bearing detail: the
security caveat, the exact repro condition, the reason a tradeoff went the way it did all stay.

Commit messages follow the global Conventional Commits rules, with these exceptions:

- Merges into `main` keep `Fork: …` / `Sync: …`; `git log --merges --grep='^Fork:'` is the record
  of what this fork changes.
- Release commits are exactly `Release <v> build <n>`; `bin/publish-release.sh` refuses anything
  else.
- `contrib/*` commits follow upstream's style: a plain imperative subject, no type prefix. They
  are squashed into upstream under the PR title.

## A parameter that enforces a boundary must not default to nil

A parameter that represents a security or correctness boundary, where "unset" silently means "no
boundary applies", must never have a default value. A default lets a call site opt out of a
boundary its author never considered, and the compiler will not stop it.

This happened: an asset-containment boundary was threaded through the document window, editor and
split-view controller, but one layer's first-entry path called `.load(...)` without it, because
the parameter defaulted to `nil`. Every other call site passed it; this one did not, and nothing
failed until a reviewer tried it by hand. A second bug sat one level up: re-rendering the same
document after opening a folder went through the code path for loading a *new* document, so it
re-evaluated, and dropped, the folder root just set.

Both are one shape: state meant to hold everywhere held almost everywhere, and the gap compiled.
Give a parameter whose job is to be supplied deliberately no default, so a call site that omits it
is a build error. Where two code paths must apply a rule identically (loading a document vs.
refreshing its display), give them one shared implementation, as `renderCurrentDocument` and
`rerenderForBoundaryChange` share `displayCurrentDocument`.

## Trace what new state actually reaches

Before calling a change that adds state (a parameter threaded through layers, a new field) done,
confirm something downstream reads it and acts on it. Reading the call sites is not enough: a
field can be read and only re-stored, which looks like load-bearing code and satisfies the type
checker. A `containmentRoot` field was once added to `ExportSource` by analogy with the live
render, and nothing ever used it; only a reviewer tracing every use found it.

**Run `periphery scan` and compare with `docs/dead-code-baseline.txt`** (config in
`.periphery.yml`). A finding already in the baseline is known and reviewed; a **new** one is what
the check is for, so investigate it like a failing test. Delete a baseline line when its finding
goes away. Its limits:

- It finds declarations nothing references, not fields that are read and then only re-stored. The
  trace above is the real check; Periphery is the net under it.
- It scans only the `belvedere` scheme. A declaration used only by `tests/swift-tests` (the
  symlinked SPM package) reads as unused. Check that package before deleting anything.
- `@objc` target-action dispatch is invisible to it; a new `@objc`-only finding is more likely a
  false positive than a true one. Read before deleting.
- Its repository is archived. If `periphery scan` starts failing outright rather than reporting
  findings, replace the tool.

## A fresh clone needs its own .git/info/exclude entries

`dist/`, `build/` and `build.noindex/` are in `main`'s `.gitignore`, but a `contrib/*` branch is
cut from `upstream/main`, which does not know them. There they are untracked and **not ignored**,
so a broad `git add -A` stages old release artifacts. Five notarized `Belvedere-*.dmg` files once
went into a PR to upstream this way, and the maintainer asked that they be excluded.
`.git/info/exclude` applies to every branch in the clone, and does not survive a fresh clone, so
add it again there before any `contrib/*` work, along with `git config rerere.enabled true`:

```bash
printf 'build/\nbuild.noindex/\ndist/\n' >> .git/info/exclude
```
