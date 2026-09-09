# Release automation plan — `build.sh --release` → Homebrew tap

Status: **proposed**, not built. This documents the manual flow used for 1.1.0 and
the script that would replace steps 4–7 of it.

## Baseline — what is manual today

Everything after the DMG is hand-run:

| # | Step | Tool |
|---|---|---|
| 1 | Bump `Version.xcconfig`, build, sign, notarize, staple → `dist/Belvedere <v>.dmg` | `./scripts/build.sh --release --update <seg>` |
| 2 | Update docs where a claim goes stale (`FORK-NOTES.md` milestones, `README.md`) | manual |
| 3 | `git commit -m "Release <v> build <n>"`, `git tag -a v<v>` | manual |
| 4 | `git push origin main && git push origin v<v>` | manual |
| 5 | Copy the DMG to a spaceless `Belvedere-<v>.dmg` | manual |
| 6 | `gh release create v<v> <dmg> --repo inquinity/homebrew-tap` | manual |
| 7 | Rewrite `Casks/belvedere.rb` `version` + `sha256`, commit, push (tap repo) | manual |
| 8 | `brew update && brew upgrade --cask belvedere` to verify | manual |

Goal: steps 4–7 collapse into one re-runnable command. Steps 1–3 and 8 stay human.

## Key decisions

### 1. A separate `scripts/publish-release.sh`, not a `build.sh` flag

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
unchanged) drops step 5. Requires updating the `dist/Belvedere 1.1.0.dmg` references
in `FORK-NOTES.md`.

### 4. Release notes come from a required per-version file

The fork keeps no changelog. `gh --generate-notes` is noisy for this commit style.
`publish-release.sh` requires `docs/release-notes/<v>.md` (one paragraph — the summary
a `brew` user sees) and passes it as `--notes-file`; it refuses to publish if the file
is missing.

### 5. `--draft` mode, and dry-run by default

`--draft` → `gh release create --draft` and skip the cask bump, so nothing installs.
Promote later once the build is checked on a second Mac (the QA step `FORK-NOTES.md`
still wants). The default run is a dry run that prints every command and mutates
nothing; `--go` makes it act.

## `scripts/publish-release.sh` sketch

```
preconditions (fail fast):
  gh auth ok + write access to inquinity/homebrew-tap
  clean tree on main; HEAD tagged v<v>; HEAD subject "Release <v> build <n>"
  Version.xcconfig MARKETING_VERSION == <v>
  dist/Belvedere-<v>.dmg exists; xcrun stapler validate passes
  tap repo checkout found (--tap-repo, or `brew --repository inquinity/homebrew-tap`) and clean
  docs/release-notes/<v>.md exists

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
- The second cask — `publish-release.sh` is Belvedere-specific. Parameterize the cask
  token, bundle id, and source repo when the second app lands.
- `AGENTS.md` still says `Version.xcconfig` is bumped by `scripts/release.sh` in one
  place (line ~105) — stale; it is `build.sh --update`. Fix when touching that file.

## Open questions

1. Separate `publish-release.sh` vs. `build.sh --publish`? *(recommend: separate)*
2. Script validates a human commit/tag vs. makes them? *(recommend: validates)*
3. Rename `package_dmg` output to `Belvedere-<v>.dmg`? *(recommend: yes)*
4. Release notes: required per-version file vs. `--generate-notes` vs. interactive? *(recommend: required file)*
5. Notes files under `belvedere/docs/release-notes/` vs. the tap repo?
6. Default to a dry run that needs `--go`? *(recommend: yes)*
