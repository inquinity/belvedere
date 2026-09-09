# Releasing Belvedere → the Homebrew tap

Both halves are implemented: `just release <seg>` cuts the release locally, and
`bin/publish-release.sh` (via `just publish`) pushes it out. This documents the flow and
why each decision was made. The `--go` publish has not yet been exercised end to end.

## The flow

```sh
# 1. Accumulate release notes as you work: add a bullet to
#    docs/release-notes/UNRELEASED.md in the same commit as any user-visible change.

# 2. Cut the release. seg is major | minor | revision:
just release minor
#    -> bumps Version.xcconfig, builds + notarizes dist/Belvedere-<v>.dmg,
#       renames UNRELEASED.md to <v>.md, commits "Release <v> build <n>",
#       tags v<v>, then dry-runs the publish for you to review.

# 3. Publish:
just publish --go
#    -> pushes main + the tag, creates the GitHub Release on inquinity/homebrew-tap
#       with the DMG attached, bumps the cask (version + sha256) and pushes it.

# 4. Verify:
brew update && brew upgrade --cask belvedere
```

`just release` refuses to run with a dirty working tree — commit or stash anything
unrelated first, including docs whose claims the release makes stale.

## What `bin/publish-release.sh` does under the hood

| Step | Detail |
|---|---|
| push source | `git push origin main`; `git push origin v<v>` (skipped if already on origin) |
| GitHub Release | `gh release create v<v> dist/Belvedere-<v>.dmg --repo inquinity/homebrew-tap --notes-file docs/release-notes/<v>.md` (`--draft` stages it without a cask bump) |
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

The fork keeps no changelog (`CHANGELOG.md` is upstream's and stays untouched so it
merges clean). `gh --generate-notes` is noisy for this commit style. So:

- **`docs/release-notes/UNRELEASED.md`** is a running list. When a change alters what a
  `brew`-installed user sees or does, the same commit adds a bullet here — this is the
  `README.md` / fixture rule from `AGENTS.md` ("documentation that describes behaviour
  is part of the behaviour") applied to release notes.
- `just release <seg>` renames `UNRELEASED.md` to **`docs/release-notes/<v>.md`** and
  commits a fresh stub as part of the release commit.
- `bin/publish-release.sh` passes `docs/release-notes/<v>.md` as `--notes-file` and
  refuses to publish if it is missing.

Notes live in **this repo**, not the tap repo — the tap will carry casks for more than
one app, so per-app release notes don't belong there.

### 5. `--draft` mode, and dry-run by default

`--draft` → `gh release create --draft` and skip the cask bump, so nothing installs.
Promote later once the build is checked on a second Mac (the QA step `FORK-NOTES.md`
still wants). The default run is a dry run that prints every command and mutates
nothing; `--go` makes it act.

## `bin/publish-release.sh` — preconditions and steps

```
preconditions (fail fast):
  gh auth ok + write access to inquinity/homebrew-tap
  clean tree on main; HEAD tagged v<v>; HEAD subject "Release <v> build <n>"
  Version.xcconfig MARKETING_VERSION == <v>
  dist/Belvedere-<v>.dmg exists; xcrun stapler validate passes
  tap repo checkout found (--tap-repo, or `brew --repository inquinity/homebrew-tap`) and clean
  docs/release-notes/<v>.md exists (renamed from UNRELEASED.md in the release commit)

steps (each idempotent — safe to re-run after a mid-way failure):
  1. git push origin main
  2. git push origin v<v>                       # refuse if already on origin, unless --force
  3. sha = shasum -a 256 dist/Belvedere-<v>.dmg
  4. gh release create v<v> dist/Belvedere-<v>.dmg --repo inquinity/homebrew-tap \
       --title "Belvedere <v>" --notes-file docs/release-notes/<v>.md [--draft]
     (release already exists? -> gh release upload --clobber)
  5. sed -i '' the version + sha256 lines in <tap>/Casks/belvedere.rb   (skip if already <v>)
  6. (tap) git commit -m "belvedere <v>" && git push                   (skip if --draft)
  7. print: brew update && brew upgrade --cask belvedere

flags: --go (default: dry run) · --draft · --tap-repo <path> · --force
```

## Rollback

`gh release delete v<v> --repo inquinity/homebrew-tap --yes`, `git push --delete origin
v<v>` (the tap-repo tag), revert the cask bump commit. Anyone who already installed is
unaffected; re-installers may hit CDN-cached bytes, so **prefer rolling forward with
`<v+1>`** over unpublishing. The source-repo tag and commit on `inquinity/belvedere`
stay as history.

## Out of scope

- CI-based notarization (needs secret provisioning the fork avoids).
- The second cask — `bin/publish-release.sh` is Belvedere-specific. Parameterize the
  cask token, bundle id, and source repo when the second app lands.

## Status of the decisions above

All six settled (2026-09-09) and shipped in `bin/publish-release.sh` +
`bin/build.sh`: separate `bin/publish-release.sh`; it validates a human release commit
rather than making one; `package_dmg` emits `Belvedere-<v>.dmg`; release notes are a
required per-version file accumulated in `UNRELEASED.md`, kept in this repo; default
run is a dry run needing `--go`. Not yet exercised end to end with `--go`.
