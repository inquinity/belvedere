# Markdown Preview — agent guide

> ## ⚠️ FORK STATUS — read before acting on anything below
>
> This is **[inquinity/belvedere](https://github.com/inquinity/belvedere)**,
> a fork of pluk-inc/markdown-preview. Read
> **[docs/FORK-NOTES.md](docs/FORK-NOTES.md)** first — it is the source of truth for how
> this repository differs from the document below.
>
> - **Releases go through `bin/build.sh --release`.** It builds, signs, notarizes
>   and packages a DMG into `dist/`, with no `CHANGELOG.md` requirement, and composes
>   with `--update` to bump the version first. Upstream's `release.sh`,
>   `rollback-release.sh` and the whole Amore pipeline drove *their* account and have
>   been removed. **Ignore the `release-process` skill and the Releasing section below** —
>   both describe upstream's pipeline, which does not exist here.
> - **`DEVELOPMENT_TEAM` is different here, on purpose.** The Signing section below says
>   never to change `5P3TSMNV42`. That is upstream's team and correct advice *in their
>   repo*. This fork builds as `com.altmansoftwaredesign.belvedere` under team
>   `45GJWJVQN2` — that change is deliberate, and reverting it to match the text below
>   would break signing here. The surrounding warning still applies: never let Xcode
>   silently rewrite it to some *other* team.
> - **`Version.xcconfig` is bumped by `bin/build.sh --update`**, not by
>   `scripts/release.sh`, which no longer exists, and not by hand in a "release PR".
>   The fork versions on its own `1.x` line, independent of upstream's `0.0.x`; on an
>   upstream merge, always keep ours.
> - **Sparkle is excised**, so the EdDSA key, the notary-profile pairing, `SUPublicEDKey`
>   and the `SUFeedURL` under "Release references" below are all moot here. The Sparkle
>   `mach-lookup` entitlements are gone too. The read-only filesystem exception is not
>   moot — see F3 in the fork notes.
> - **"Codex development workflow" below describes upstream's maintainer** — their
>   Codex model pin, their shell, their PR habits. None of it is a rule for this fork.
> - The fork carries **deliberately dead code** — an orphaned CLI installer and stubbed
>   telemetry reporters. This is load-bearing for cheap upstream merges. Do not remove it.
> - This fork has two remotes: `origin` (inquinity) and `upstream` (pluk-inc).
> - Sync with `git merge upstream/main`. **Never rebase `main`** — it is published.
> - **Upstream issues and PRs are worked on a `contrib/<topic>` branch cut from
>   `upstream/main` (or the open PR's existing branch), never on `main`** — see the branch
>   model in docs/FORK-NOTES.md. Everything behind a claim in the PR, issue or reply uses a
>   **Markdown Preview build of that branch**, not Belvedere: building, running, installing,
>   manual testing, screenshots. Belvedere carries the same fix plus the fork's hardening,
>   so a result seen there says nothing about what upstream will merge. Carry the fix into
>   `main` afterwards, with a `Fork:` merge.
> - **For Quick Look, check the preview's "Open with" button before trusting a result.**
>   With Belvedere installed, both extensions claim `.md`, and macOS picks one.
> - **Upstream's build sends crash reports to Sentry and checks for updates with
>   Sparkle.** For a local test install, blank `SentryDSN` and `SUFeedURL` and set
>   `SUEnableAutomaticChecks` to false, in a local commit that is never pushed.
> - **Fork-authored scripts live in `bin/`** (`build.sh`, `build-release.sh`,
>   `install.sh`, `bundle.sh`, `check-upstream.sh`, `show-private-changes.sh`,
>   `make-icon.swift`, `publish-release.sh`, `compose-release-notes.sh`, `ver`,
>   `build-num`). `scripts/` now holds
>   only upstream's tooling, so `git merge upstream/main` never touches `bin/`. Wherever
>   the text below says `scripts/<one of those>`, read `bin/`.
> - **The Project facts table below is upstream's and is wrong here.** The bundle id
>   is `com.altmansoftwaredesign.belvedere`, the product name is `Belvedere`, there is
>   no Sparkle auto-updater, and distribution is a Homebrew cask
>   (`inquinity/tap/belvedere`), not Amore. The scheme, Quick Look target and minimum
>   macOS are still correct.
> - **Fork tasks run through `just`** (`brew install just`; `just --list`). The recipes
>   in `justfile` wrap the `bin/` scripts — `just build`, `just release <seg>`,
>   `just publish --go`. Releasing is documented in `docs/RELEASE-AUTOMATION.md`.
> - **Review all incoming upstream changes for security** Use the `security-oss-app-reviewer` skill and focus on incoming changes.
>
>
> Everything after this block is upstream's documentation, preserved as-is.

A macOS app for previewing Markdown files. AppKit, sandboxed, ships with a Quick Look extension. Updates via Sparkle, distributed via Amore.

## Documentation that describes behaviour is part of the behaviour

**If a change makes a documented claim false, updating that claim is part of the
change — same commit, not a follow-up.** This applies to `README.md`, sample and
fixture files, and any comment that tells a reader what to expect on screen.

The reason is not tidiness. A stale claim asserts the *opposite* of what the
code does, and people trust it, so it is worse than saying nothing at all. It
produces two specific failures:

- A correct result gets reported as a bug, because the documentation says
  something else should happen.
- A real regression gets waved through as a known limitation, because the
  documentation says it never worked.

The second one is not hypothetical here. `README.md` said Mermaid diagrams
render in both the app and Quick Look previews. They had stopped rendering in
Quick Look, and the mismatch was read as documentation drift rather than as the
bug it was — which is part of why it survived several releases before anyone
chased it (#338, fixed in #343).

So when you change what the reader sees, grep for what says otherwise:

```bash
grep -rn "<the behaviour you changed>" README.md samples/ tests/fixtures/ docs/
```

## Writing for other people — commits, PRs, issue replies

This fork is **public**. Every commit message, PR description, and issue or PR
comment is readable by anyone — upstream maintainers and strangers included. A
fork commit whose message contains `#337` (or `pluk-inc#337`) gets auto-linked
into the upstream PR's timeline permanently; those entries cannot be deleted.
So in fork commits, point at upstream with a full URL or a non-linking form
(`GH-337`), not a bare `#337`.

**No fork-internal shorthand in anything that can travel.** Backlog IDs (`F4`,
`F9`, `M4`), `FORK-NOTES`, `INTERNAL-INSTALL`, roadmap codenames — they mean
nothing to upstream and nothing to us in six months. Write the actual subject:
"the trusted-folders pane", not "F9".

**Commit messages are for the person reading them in 6–12 months** with no
memory of today — often you. Say what changed, why it changed, and what breaks
if it's reverted. Don't say which backlog item it belongs to.

**Keep issue and PR replies short and focused.** Write like a busy human who
does not have time for War and Peace: lead with the answer or the decision, cut
the throat-clearing and the restated context, don't survey every option you
considered.

**Short is not an excuse to drop load-bearing detail.** The security caveat, the
exact repro condition, the reason a tradeoff went the way it did — those stay.
Brevity means no wasted words, not less information.

### Commit messages in this repository

Follow the global Conventional Commits rules, with these exceptions:

- Merges into `main` keep `Fork: …` / `Sync: …`. `git log --merges --grep='^Fork:'`
  is the record of what this fork changes (see docs/FORK-NOTES.md).
- Release commits are exactly `Release <v> build <n>`; `bin/publish-release.sh`
  refuses anything else.
- `contrib/*` commits follow upstream's style: a plain imperative subject, no
  type prefix. They are squashed into upstream under the PR title.

## A parameter that enforces a boundary must not default to nil

A function parameter that represents a security or correctness boundary — one
where "unset" is silently equivalent to "no boundary applies" — must never
have a default value. A default is exactly what lets a call site opt out of a
boundary its author never considered, and the compiler will not stop it.

This is not hypothetical. An asset-containment boundary was threaded through
several layers of the document window, editor, and split-view controller. One
layer's *first-entry* path — creating a fresh editor the first time a window
enters edit mode — called `.load(...)` without it, because the parameter
defaulted to `nil` and the code still compiled. Every other call site passed
it correctly; this one didn't, and nothing failed until a reviewer tested it
by hand. A second bug in the same review sat one level up: re-rendering the
same document after opening a new project folder went through the same
code path used for loading a genuinely *new* document, so it re-evaluated —
and immediately dropped — the folder root that had just been set.

Neither bug is about this one feature. Both are the same shape: state meant
to hold everywhere held almost everywhere, and the gap compiled cleanly. Where
a parameter's whole job is to be supplied deliberately, give it no default —
turn the silent gap into a build error at every call site that doesn't name
it. Where two code paths must apply a rule identically (loading a document vs.
refreshing its display), give them one shared implementation rather than two
copies that can drift, as `renderCurrentDocument` and `rerenderForBoundaryChange`
now do via a shared `displayCurrentDocument` — not two independent codings of
"apply the boundary."

## Trace what a new parameter or stored property actually reaches

Before considering a change that adds state — a new parameter threaded
through several layers, a new field on a struct — done, confirm something
downstream actually reads it and acts on it. `grep -rn '<name>('` for every
call site is a start, but reading is not enough: a field can be read and
immediately re-stored with nothing ever consuming the value, which looks
identical to load-bearing code and satisfies the type checker completely.

That happened here too: a `containmentRoot` field was added to `ExportSource`
(the app window's PDF/print snapshot) when the same name was threaded through
`display(...)` for the live render — added by analogy, not because export
code was confirmed to need it. Nothing ever read it for that purpose. A
reviewer caught it by tracing every use; before this, nothing else would have.

**Run `periphery scan` before calling a change like that done**, and compare
the result to `docs/dead-code-baseline.txt`. The config lives in
`.periphery.yml`, so the bare command reproduces the baseline. A finding
already in the baseline is known and reviewed; a **new** one is what the
check exists to catch — investigate it before merging, the same way you would
a failing test. A finding that disappears is welcome — delete its line.

Know its limits before trusting a clean run:

- **It would not have caught the `ExportSource` case above.** Periphery finds
  declarations nothing references, not ones that are read and then only
  redundantly re-stored. A field can pass Periphery cleanly and still be dead
  in every sense that matters — this check narrows the same failure shape, it
  does not close it. The "trace to an actual consumer" step above is still
  the real check; Periphery is the automated net under it.
- **It only scans the `md-preview` Xcode scheme.** A declaration used solely
  by `tests/swift-tests` — the symlinked SPM test package — reads as unused
  here even when it is genuinely load-bearing (see the baseline file's own
  note on `QuickLookFirstResponderPolicy.rationale`, kept there for exactly
  this reason). Check that package before deleting anything this flags.
- **AppKit's target-action dispatch is invisible to it.** `retain_objc_accessible`
  in `.periphery.yml` covers most of this, but a genuinely new `@objc`-only
  false positive is more likely than a genuinely new true one — read before
  deleting.
- **Its upstream repository is archived.** Homebrew currently still serves it
  (`brew install periphery`) but has flagged it deprecated; it may stop
  working against a future Swift toolchain with nobody to fix it. Treat this
  section as needing a replacement tool, not as a permanent fixture, if a
  `periphery scan` run ever starts failing outright rather than reporting
  findings.

## Project facts

| Thing             | Value                                                       |
| ----------------- | ----------------------------------------------------------- |
| Bundle id         | `doc.md-preview`                                            |
| Product name      | `Markdown Preview`                                          |
| Scheme            | `md-preview`                                                |
| Quick Look target | `quick-look` (embedded extension)                           |
| Min macOS         | 15.0                                                        |
| Sandboxed         | yes — uses Sparkle XPC services for updates                 |
| Auto-updater      | Sparkle 2.x (Swift package)                                 |
| Distribution      | Amore (managed); appcast at `release.md-preview.app` |

Version is managed centrally in `Version.xcconfig` (`MARKETING_VERSION`, `CURRENT_PROJECT_VERSION`). Both the app and the quick-look extension inherit from it.

## Codex development workflow

- `.codex/config.toml` pins `gpt-6-astra` with `medium` reasoning for trusted project sessions. Explicit session overrides can take precedence. This config controls the coding agent; the app's Open in LLM action delegates to external apps.
- Open PRs ready for review, never as drafts. Never use a `codex/` branch prefix.
- The maintainer uses Nushell and has `gh` authentication available. Match shell syntax to the actual execution shell.
- Complete work authorized by the user's request, making reasonable routine implementation choices. A request for a plan authorizes planning only.
- Apply skills within their stated scope. If an instruction blocks authorized work, identify the exact file and instruction rather than inferring an extra approval requirement.
- Keep verification proportional: config and documentation changes need validation and diff review; Swift changes need relevant tests and an app build; visible behavior changes need runtime verification.

## Documentation that describes behaviour is part of the behaviour

**If a change makes a documented claim false, updating that claim is part of the
change — same commit, not a follow-up.** This applies to `README.md`, sample and
fixture files, and any comment that tells a reader what to expect on screen.

The reason is not tidiness. A stale claim asserts the *opposite* of what the
code does, and people trust it, so it is worse than saying nothing at all. It
produces two specific failures:

- A correct result gets reported as a bug, because the documentation says
  something else should happen.
- A real regression gets waved through as a known limitation, because the
  documentation says it never worked.

The second one is not hypothetical here. `README.md` said Mermaid diagrams
render in both the app and Quick Look previews. They had stopped rendering in
Quick Look, and the mismatch was read as documentation drift rather than as the
bug it was — which is part of why it survived several releases before anyone
chased it (#338, fixed in #343).

So when you change what the reader sees, grep for what says otherwise:

```bash
grep -rn "<the behaviour you changed>" README.md samples/ tests/fixtures/ docs/
```

## Signing & secrets — do not touch without asking

- `DEVELOPMENT_TEAM = 5P3TSMNV42` (`project.pbxproj`, both targets) is the
  maintainer's Apple Developer Team ID, hardcoded in the shared Xcode project.
  Never change it, regenerate signing, or let Xcode "fix" it automatically —
  building locally without the team's certificates can make Xcode silently
  rewrite `DEVELOPMENT_TEAM` to your own personal team on save. Check
  `git diff` on `project.pbxproj` before committing anything and revert that
  hunk if it shows up.
- `CODE_SIGN_IDENTITY` / `CODE_SIGN_STYLE = Automatic` — same story, leave as-is.
- Secrets (currently `POSTHOG_PROJECT_TOKEN`) live in `Secrets.xcconfig`,
  gitignored — copy `Secrets.xcconfig.example` to `Secrets.xcconfig` locally.
  Never hardcode a real token into a tracked file, Info.plist, or a commit.
- The Sparkle/Amore signing material (EdDSA key, notary keychain profile) is
  documented in the `release-process` skill. Don't touch `SUPublicEDKey` in
  `Info.plist` or the entitlements' `mach-lookup` names without reading that
  skill first — they're paired with private material outside the repo (login
  Keychain / Amore), so an unmatched change breaks Sparkle updates silently.
- `md-preview.entitlements` / `quick-look.entitlements` — the sandbox
  `temporary-exception` entries (Sparkle XPC mach-lookup names, the read-only
  filesystem exception) are narrowly scoped, notarization-review-sensitive
  capabilities. Don't broaden or "clean up" them without understanding why
  they're there (see the inline comments in each file).
- A release PR must update **both** `MARKETING_VERSION` and
  `CURRENT_PROJECT_VERSION` in `Version.xcconfig`, together with the matching
  `CHANGELOG.md` entry. Edit the version file directly during PR preparation.
  `scripts/release.sh` builds and publishes; run it only when release execution
  is requested, not merely to create the PR.

## Releasing

See the `release-process` skill for branch/PR naming, exactly what `scripts/release.sh` and `scripts/rollback-release.sh` do, and the Amore config already wired for this project.

## Release references

- `Info.plist` currently sets `SUFeedURL` to `https://release.md-preview.app/v1/apps/doc.md-preview/appcast.xml`. Check the current plist and Amore configuration before releasing; do not assume an old hostname or mismatch still applies.
- The canonical GitHub repository is `pluk-inc/markdown-preview`. Older remotes may redirect from `pluk-inc/md-preview.app`; check `git remote -v` and `gh repo view` before publishing.

## Common Xcode tasks
```bash
xcodebuild -project md-preview.xcodeproj -scheme md-preview -configuration Debug build
xcodebuild -resolvePackageDependencies -project md-preview.xcodeproj
```
Sparkle helper tools (sign_update / generate_keys / generate_appcast) live at:
`~/Library/Developer/Xcode/DerivedData/md-preview-*/SourcePackages/artifacts/sparkle/Sparkle/bin/`
