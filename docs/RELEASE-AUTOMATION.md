# Releasing Belvedere → GitHub Releases and the Homebrew tap

Both halves are implemented: `just release <seg>` cuts the release locally, and
`bin/publish-release.sh` (via `just publish`) pushes it out. This documents the flow and
why each decision was made. 1.2.0 through 1.2.4 went out through `just publish --go`,
onto the tap; 1.1.0 was created by hand before the script existed, and only its asset
was re-published through it. The first release after the move to
`inquinity/belvedere` (decision 6) is the first `--go` run against the new location.

## The flow

```sh
# 1. Accumulate release notes as you work: add a bullet to
#    docs/release-notes/UNRELEASED.md in the same commit as any change a reader
#    would care about.
#    Preview the composed notes at any time with: just notes

# 2. Cut the release. seg is major | minor | revision:
just release minor
#    -> checks the notes compose, bumps Version.xcconfig, builds + notarizes
#       dist/Belvedere-<v>.dmg, composes <v>.md and resets UNRELEASED.md to the stub,
#       commits "Release <v> build <n>", tags v<v>, then dry-runs the publish.

# 3. Publish:
just publish --go
#    -> pushes main + the tag, creates the GitHub Release for that tag on
#       inquinity/belvedere with the DMG attached, bumps the tap's cask
#       (version + sha256) and pushes it.

# 4. Verify:
brew update && brew upgrade --cask belvedere
```

`just release` refuses to run with a dirty working tree — commit or stash anything
unrelated first, including docs whose claims the release makes stale.

## What `bin/publish-release.sh` does under the hood

| Step | Detail |
|---|---|
| push source | `git push origin main`; `git push origin v<v>` (skipped if already on origin) |
| GitHub Release | `gh release create v<v> dist/Belvedere-<v>.dmg --repo inquinity/belvedere --verify-tag --notes-file docs/release-notes/<v>.md` (`--draft` stages it without a cask bump) |
| cask bump | rewrite the `version` + `sha256` lines in `<tap>/Casks/belvedere.rb`, commit `belvedere <v>`, push |

Each step is safe to re-run after a mid-way failure. Nothing happens without `--go`.

## Key decisions

### 1. A separate `bin/publish-release.sh`, not a `build.sh` flag

`build.sh`'s scope is "build locally". Publishing is a different concern and has to be
independently re-runnable when step 6 succeeds but step 7 fails. `build.sh --release`
keeps producing the DMG; `publish-release.sh` ships one that already exists.

Not GitHub Actions: the Developer ID identity and notary profile live in the local
login keychain by design (see `FORK-NOTES.md` — the fork stays off cloud infra). CI
notarization is a separate, larger project. Deferred.

### 2. The script validates a human release commit; it does not create one

Preconditions it enforces: clean tree, on `main`, `HEAD` tagged `v<v>`, `HEAD` subject
is `Release <v> build <n>`, `Version.xcconfig` marketing version equals `<v>`,
`dist/Belvedere-<v>.dmg` exists and `stapler validate`s. Then it does only the push,
the GitHub release, and the cask bump.

Release commits are permanent history on a published branch — a script silently
committing to `main` is what the High-risk gate in `CLAUDE.md` is about. You review,
commit, and tag; the script does the mechanical outward steps.

### 3. Emit `Belvedere-<v>.dmg` (no space) from `package_dmg` directly

One line in `build.sh` (`dmg_path="$DIST_DIR/$APP_NAME-$version.dmg"`, volume name
unchanged) means `bin/publish-release.sh` uploads the DMG verbatim. `FORK-NOTES.md`'s
`dist/Belvedere 1.1.0.dmg` mention is left as-is — that is the historical name of the
1.1.0 artifact, built before this change.

### 4. Release notes come from a required per-version file, accumulated as work lands

The fork keeps no changelog file: upstream's `CHANGELOG.md` was removed in 2.0, and the
per-version files in `docs/release-notes/` are the record. `gh --generate-notes` is noisy for this commit style. So:

- **`docs/release-notes/UNRELEASED.md`** is a running list. When a change is one a
  Belvedere user would notice or want, the same commit adds a bullet here — the
  `README.md` / fixture rule from `CLAUDE.md` ("documentation that describes behaviour
  is part of the behaviour") applied to release notes.
- **The test for every line is whether a reader cares.** The notes say what changed for
  someone using Belvedere. They do not carry upstream's version numbers, what
  Belvedere declined from upstream, what it carries on top of Markdown Preview, or
  About-box and license housekeeping: those are ours to track, in `docs/FORK-NOTES.md`
  and `docs/Upstream-Changed.md`. Changes that arrive with a Markdown Preview sync go
  under a *Upstream features included in release* heading, written for readers, with
  no PR numbers — on Belvedere's release page a bare `#123` would link to Belvedere's
  own `#123`. (Until 1.3.0 the notes also had a "Based on Markdown Preview x.y.z"
  line, a "Changes on top of" section from `ON-TOP-OF-UPSTREAM.md`, and a generated
  list of upstream commits; all three were dropped by that test.)
- `just release <seg>` runs **`bin/compose-release-notes.sh`**, which writes
  **`docs/release-notes/<v>.md`** as `# Belvedere <v>` and *New in this release* from
  `UNRELEASED.md`, and the release commit resets `UNRELEASED.md` to the stub.
- HTML comments are dropped, which is where maintainer instructions
  live. Composition fails — before the build, so no version is bumped — if
  `UNRELEASED.md` still holds the empty stub, or has instructions outside a comment.
  1.2.0's release page went out with its "# Unreleased" heading and instruction
  paragraph; that is the failure this closes.
- `bin/publish-release.sh` passes `docs/release-notes/<v>.md` as `--notes-file` and
  refuses to publish if it is missing.

Notes live in **this repo**, next to the releases they describe, not in the tap repo —
the tap carries casks for several apps, so per-app notes don't belong there.

### 5. `--draft` mode, and dry-run by default

`--draft` → `gh release create --draft` and skip the cask bump, so nothing installs.
Promote later once the build is checked on a second Mac (the QA step `FORK-NOTES.md`
still wants) by re-running without `--draft`: `just publish --go`. Finding the release
already there, it re-uploads the DMG, refreshes the notes, publishes the draft
(`gh release edit v<v> --draft=false`), then bumps the cask. The usual preconditions
apply, so promote before anything else lands on `main`: `HEAD` must still be the
release commit.

A run without `--draft` publishes any draft it finds rather than refusing. Leaving it
a draft is never right: the cask bump would point `brew` at assets that aren't publicly
downloadable, so every install 404s. The same path recovers the draft `gh release
create` leaves behind when its upload fails and its own cleanup fails too.

The reverse is refused: `--draft` against a release that is already published stops
before touching it. It cannot un-publish the release, and because it skips the cask
bump, re-uploading the DMG would leave the cask's sha256 describing the old file, so
every install would fail its checksum. Re-run without `--draft` to re-publish.

The default run is a dry run that prints every command and mutates nothing; `--go`
makes it act.

### 6. Releases live on `inquinity/belvedere`; the tap holds only the cask

1.1.0 through 1.2.4 were first published as releases on `inquinity/homebrew-tap`,
because the source repository was private then and a cask cannot download from a
private repository without a token. The source is public now, and the tap's own README
already states the rule — an app's releases go on its own repository where that is
public — which `yatu` and `qltextview` follow. Belvedere was the exception. Moved
2026-09-28, for three reasons:

- **The tag and the release are the same object.** `just publish` already pushes `v<v>`
  to this repository; the release now attaches to that tag (`--verify-tag`). On the tap,
  `gh release create` cut a second, unrelated `v<v>` tag from the tap's own `main`.
- **"Latest release" means Belvedere's.** The cask's `livecheck` (`strategy
  :github_latest` on the download URL) and the README badge both read the hosting repo's
  latest release. On a multi-app tap that is whichever app released last.
- **It is the shape an official Homebrew cask expects** — the vendor's own download
  location, with the homepage and the download in the same repository — should
  Belvedere ever be submitted.

All six earlier releases were copied here byte-for-byte from the tap's assets (each
checked against the tap's recorded sha256, so the cask's checksum did not change) with
notes from `docs/release-notes/` — identical to the tap's, except that 1.2.0's link to
1.2.1 now points here — and the cask's `url` was switched in one tap commit with no
version bump. `bin/publish-release.sh` refuses to run if the cask's `url` does not point here,
so a release can never go up in one place while `brew` fetches from another.

**Cleanup due on or after 2026-10-28:** the six tap copies were left in place so that
nothing mid-flight (a stale `brew` cache, an old link) breaks during the switch. Once a
release has gone out from here, delete them — this cannot be undone, so check first
that the cask resolves here (`brew fetch --cask --force belvedere`):

```sh
for v in 1.1.0 1.2.0 1.2.1 1.2.2 1.2.3 1.2.4; do
    gh release delete "v$v" --repo inquinity/homebrew-tap --cleanup-tag --yes
done
```

`--cleanup-tag` is right *there*: those tags exist only on the tap, and point at the
tap's own commits, not at Belvedere source. Never pass it for a release on this
repository — see Rollback.

## `bin/publish-release.sh` — preconditions and steps

```
preconditions (fail fast):
  gh auth ok + write access to inquinity/belvedere and inquinity/homebrew-tap
  clean tree on main; HEAD tagged v<v>; HEAD subject "Release <v> build <n>"
  Version.xcconfig MARKETING_VERSION == <v>
  dist/Belvedere-<v>.dmg exists; xcrun stapler validate passes
  tap repo checkout found (--tap-repo, or `brew --repository inquinity/homebrew-tap`) and clean
  the tap's committed Casks/belvedere.rb downloads from inquinity/belvedere releases
  docs/release-notes/<v>.md exists (composed by bin/compose-release-notes.sh in the release commit)

steps (each idempotent — safe to re-run after a mid-way failure):
  1. git push origin main
  2. git push origin v<v>                       # refuse if already on origin, unless --force
  3. sha = shasum -a 256 dist/Belvedere-<v>.dmg
  4. gh release create v<v> dist/Belvedere-<v>.dmg --repo inquinity/belvedere --verify-tag \
       --title "Belvedere <v>" --notes-file docs/release-notes/<v>.md [--draft]
     (release already exists? -> gh release upload --clobber, then gh release edit --notes-file;
      still a draft and no --draft? -> gh release edit --draft=false   # the promote step
      already published and --draft? -> refuse, before any upload)
  5. sed -i '' the version + sha256 lines in <tap>/Casks/belvedere.rb
     (skip if already <v> with this sha256; same <v> with a new sha256 re-points it)
  6. (tap) git commit -m "belvedere <v>" && git push                   (skip if --draft)
  7. print: brew update && brew upgrade --cask belvedere

flags: --go (default: dry run) · --draft · --tap-repo <path> · --force
```

## Rollback

Revert the cask bump commit in the tap and push it, **then** `gh release delete v<v>
--repo inquinity/belvedere --yes` — in the other order, the cask points at a deleted
asset in between and every `brew install` 404s. **Do not pass `--cleanup-tag`**: the
release sits on the source tag,
which stays as history along with the release commit on `main`. Anyone who already
installed is unaffected; re-installers may hit CDN-cached bytes, so **prefer rolling
forward with `<v+1>`** over unpublishing.

## Out of scope

- CI-based notarization (needs secret provisioning the fork avoids).
- The second cask — `bin/publish-release.sh` is Belvedere-specific. Parameterize the
  cask token, bundle id, and source repo when the second app lands.

## Status of the decisions above

Decisions 1–5 settled (2026-09-09) and shipped in `bin/publish-release.sh` +
`bin/build.sh`: separate `bin/publish-release.sh`; it validates a human release commit
rather than making one; `package_dmg` emits `Belvedere-<v>.dmg`; release notes are a
required per-version file accumulated in `UNRELEASED.md`, kept in this repo; default
run is a dry run needing `--go`. Exercised with `--go` for 1.2.0 through 1.2.4.
Decision 6 — releases on `inquinity/belvedere` — settled and applied 2026-09-28; its
first `--go` run is the next release.
