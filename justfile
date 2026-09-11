# Fork-owned build and release tasks.
#
# Upstream has no justfile, so this file is unambiguously ours and never
# conflicts on merge. The heavy lifting stays in bin/*.sh -- these recipes are
# just the one place those scripts are named and strung together.
#
# Requires `just` (brew install just). Every recipe also works by calling the
# underlying bin/ script directly.

set shell := ["bash", "-eu", "-o", "pipefail", "-c"]

# List the available tasks.
default:
    @just --list

# Local dev build. Passes flags through, e.g. `just build --update revision`.
build *args:
    bin/build.sh {{ args }}

# Signed, notarized DMG into ./dist; bumps the version (seg: major|minor|revision).
build-dmg seg:
    bin/build.sh --release --update {{ seg }}

# Upstream-style, CHANGELOG-gated release build. Rarely used in this fork.
build-release *args:
    bin/build-release.sh {{ args }}

# Install the built app so the Quick Look extension registers.
install *args:
    bin/install.sh {{ args }}

# Zip the built app into ./dist.
bundle *args:
    bin/bundle.sh {{ args }}

# Remove local build scratch: ./build and this project's Xcode DerivedData. Keeps ./dist.
clean:
    rm -rf build
    rm -rf "$HOME/Library/Developer/Xcode/DerivedData/md-preview-"*

# Has upstream moved? (read-only)
check-upstream:
    bin/check-upstream.sh

# Everything this fork changes vs upstream. Pass --stat / --commits.
private-changes *args:
    bin/show-private-changes.sh {{ args }}

# Regenerate the app icon. Pass --install-mdview and friends.
icon *args:
    swift bin/make-icon.swift {{ args }}

# Print "<marketing> build <build-number>".
version:
    @printf '%s build %s\n' "$(bin/ver)" "$(bin/build-num)"

# Publish the release at HEAD to the Homebrew tap. Dry run unless you pass --go.
publish *args:
    bin/publish-release.sh {{ args }}

# Preview the next release's notes as `just release` will compose them. Pass --version <v> for its heading.
notes *args:
    @bin/compose-release-notes.sh {{ args }}

# Cut a release: bump, build DMG, compose notes, commit, tag, dry-run publish (seg: major|minor|revision).
release seg: _require-clean _require-notes (build-dmg seg)
    #!/usr/bin/env bash
    set -euo pipefail
    v="$(bin/ver)"; n="$(bin/build-num)"
    notes="docs/release-notes/$v.md"
    bin/compose-release-notes.sh --version "$v" > "$notes.tmp"
    mv "$notes.tmp" "$notes"
    bin/compose-release-notes.sh --stub > docs/release-notes/UNRELEASED.md
    git add Version.xcconfig "$notes" docs/release-notes/UNRELEASED.md
    git commit -m "Release $v build $n"
    git tag -a "v$v" -m "Belvedere $v"
    printf '\nTagged v%s. Review the dry run below, then: just publish --go\n\n' "$v"
    bin/publish-release.sh

# (internal) fail before the long build if the notes cannot be composed
_require-notes:
    @bin/compose-release-notes.sh > /dev/null

# (internal) fail unless the working tree is clean
_require-clean:
    @git diff --quiet && git diff --cached --quiet \
        || { echo "working tree is dirty -- commit or stash first" >&2; exit 1; }
