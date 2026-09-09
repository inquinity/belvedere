#!/usr/bin/env bash
set -euo pipefail

# Publish an already-built Belvedere release to the Homebrew tap.
#
# The human cuts the release:
#   bin/build.sh --release --update <major|minor|revision>   # builds dist/Belvedere-<v>.dmg
#   mv docs/release-notes/UNRELEASED.md docs/release-notes/<v>.md   # + a fresh stub
#   git commit -m "Release <v> build <n>"
#   git tag -a v<v> -m "Belvedere <v>"
#
# This script takes it from there and does only the outward steps:
#   1. push main and the tag to origin
#   2. create the GitHub Release on inquinity/homebrew-tap with the DMG attached
#   3. bump the cask (version + sha256) in the tap-repo checkout and push it
#
# It creates nothing in this repo -- no commits, no tags. It validates that the
# release commit and tag already exist, then performs steps that are each safe
# to re-run if a later one fails.
#
# Dry run by default: every mutating command is printed and nothing happens.
# Pass --go to actually publish.

COLOR_GREEN="\e[32m"
COLOR_RED="\e[31m"
COLOR_YELLOW="\e[33m"
COLOR_BRIGHTYELLOW="\e[93m"
COLOR_RESET="\e[0m"

print_colored() {
    local color=$1
    local message=$2
    printf "${color}${message}${COLOR_RESET}\n"
}

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERSION_CONFIG="$PROJECT_ROOT/Version.xcconfig"
DIST_DIR="${DIST_DIR:-$PROJECT_ROOT/dist}"
NOTES_DIR="$PROJECT_ROOT/docs/release-notes"

APP_NAME="Belvedere"
CASK_TOKEN="belvedere"
TAP_SLUG="inquinity/homebrew-tap"

go=false
draft=false
force=false
tap_repo="${TAP_REPO:-}"

usage() {
    printf '%b\n' "${COLOR_YELLOW}Usage: publish-release.sh [--go] [--draft] [--force] [--tap-repo PATH]${COLOR_RESET}"
    printf '\n'
    printf '%s\n' 'Publish the release described by HEAD -- a "Release <v> build <n>" commit'
    printf '%s\n' 'tagged v<v> -- to the Homebrew tap. Build the DMG first with:'
    printf '%s\n' '  bin/build.sh --release --update <major|minor|revision>'
    printf '\n'
    printf '%b\n' "${COLOR_YELLOW}Options:${COLOR_RESET}"
    printf '%s\n' '  -h, --help          Show this help text.'
    printf '%s\n' '  -n, --dry-run       Print what would happen and exit. This is the default.'
    printf '%s\n' '      --go            Actually publish. Without it, nothing is mutated.'
    printf '%s\n' '      --draft         Create the GitHub Release as a draft and skip the cask'
    printf '%s\n' '                      bump, so nothing installs until the release is promoted.'
    printf '%s\n' '      --force         Allow re-pushing a tag that is already on origin.'
    printf '%s\n' "      --tap-repo PATH Local checkout of $TAP_SLUG to bump and push."
    printf '%s\n' '                      Default: the Homebrew tap clone (brew --repository).'
    printf '\n'
    printf '%b\n' "${COLOR_YELLOW}Environment:${COLOR_RESET}"
    printf '%s\n' '  DIST_DIR   Where the .dmg is. Default: ./dist'
    printf '%s\n' '  TAP_REPO   Same as --tap-repo.'
}

die() {
    print_colored "$COLOR_RED" "error: $*" >&2
    exit 1
}

read_xcconfig() {
    local key=$1
    awk -F' *= *' -v k="$key" '$1 == k { print $2; exit }' "$VERSION_CONFIG"
}

require_command() {
    command -v "$1" >/dev/null 2>&1 || die "$1 is required but was not found"
}

# Print a mutating command, and run it only under --go.
run() {
    print_colored "$COLOR_BRIGHTYELLOW" "  \$ $*"
    [[ "$go" == "true" ]] && "$@"
    return 0
}

parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help) usage; exit 0 ;;
            -n|--dry-run) go=false; shift ;;
            --go) go=true; shift ;;
            --draft) draft=true; shift ;;
            --force) force=true; shift ;;
            --tap-repo)
                [[ $# -ge 2 ]] || die "missing value for $1"
                tap_repo="$2"; shift 2 ;;
            *) die "unknown option: $1" ;;
        esac
    done
}

# Locate a clean tap-repo checkout to bump the cask in.
resolve_tap_repo() {
    if [[ -z "$tap_repo" ]]; then
        command -v brew >/dev/null 2>&1 \
            || die "no --tap-repo given and brew is not installed to locate one"
        tap_repo="$(brew --repository "$TAP_SLUG" 2>/dev/null || true)"
        [[ -n "$tap_repo" && -d "$tap_repo" ]] \
            || die "tap $TAP_SLUG is not tapped; run 'brew tap $TAP_SLUG' or pass --tap-repo"
    fi
    tap_repo="$(cd "$tap_repo" && pwd)"
    [[ -f "$tap_repo/Casks/$CASK_TOKEN.rb" ]] \
        || die "no Casks/$CASK_TOKEN.rb under $tap_repo"
    git -C "$tap_repo" diff --quiet && git -C "$tap_repo" diff --cached --quiet \
        || die "tap repo has uncommitted changes: $tap_repo"
}

# Everything that must be true before any outward step. Read-only.
validate() {
    require_command git
    require_command gh
    require_command shasum

    [[ -f "$VERSION_CONFIG" ]] || die "missing $VERSION_CONFIG"
    version="$(read_xcconfig MARKETING_VERSION)"
    build="$(read_xcconfig CURRENT_PROJECT_VERSION)"
    [[ -n "$version" && -n "$build" ]] || die "could not read version from $VERSION_CONFIG"

    tag="v$version"
    dmg="$DIST_DIR/$APP_NAME-$version.dmg"
    notes="$NOTES_DIR/$version.md"

    [[ "$(git -C "$PROJECT_ROOT" rev-parse --abbrev-ref HEAD)" == "main" ]] \
        || die "not on main"
    git -C "$PROJECT_ROOT" diff --quiet && git -C "$PROJECT_ROOT" diff --cached --quiet \
        || die "working tree is dirty -- commit the release first"

    local subject expected="Release $version build $build"
    subject="$(git -C "$PROJECT_ROOT" log -1 --format=%s)"
    [[ "$subject" == "$expected" ]] \
        || die "HEAD is not the release commit (want \"$expected\", have \"$subject\")"

    git -C "$PROJECT_ROOT" rev-parse -q --verify "refs/tags/$tag" >/dev/null \
        || die "no local tag $tag -- run: git tag -a $tag -m \"$APP_NAME $version\""
    [[ "$(git -C "$PROJECT_ROOT" rev-parse "$tag^{commit}")" \
        == "$(git -C "$PROJECT_ROOT" rev-parse HEAD)" ]] \
        || die "tag $tag does not point at HEAD"

    [[ -f "$dmg" ]] || die "missing $dmg -- run: bin/build.sh --release"
    xcrun stapler validate "$dmg" >/dev/null 2>&1 \
        || die "$dmg is not stapled/notarized"
    [[ -f "$notes" ]] || die "missing release notes: $notes"

    gh auth status >/dev/null 2>&1 || die "gh is not authenticated (gh auth login)"
    gh repo view "$TAP_SLUG" >/dev/null 2>&1 \
        || die "cannot reach $TAP_SLUG with gh -- check access"

    resolve_tap_repo
}

push_source() {
    print_colored "$COLOR_BRIGHTYELLOW" "* Pushing main and $tag"
    run git -C "$PROJECT_ROOT" push origin main

    local remote_sha
    remote_sha="$(git -C "$PROJECT_ROOT" ls-remote --tags origin "refs/tags/$tag" | awk '{print $1}')"
    if [[ -n "$remote_sha" && "$force" != "true" ]]; then
        [[ "$remote_sha" == "$(git -C "$PROJECT_ROOT" rev-parse "$tag")" ]] \
            || die "$tag on origin points elsewhere; investigate, or re-run with --force"
        print_colored "$COLOR_YELLOW" "  $tag already on origin -- skipping tag push"
    else
        run git -C "$PROJECT_ROOT" push --force origin "refs/tags/$tag"
    fi
}

create_release() {
    local sha
    sha="$(shasum -a 256 "$dmg" | awk '{print $1}')"
    print_colored "$COLOR_GREEN" "  sha256($(basename "$dmg")) = $sha"

    if gh release view "$tag" --repo "$TAP_SLUG" >/dev/null 2>&1; then
        print_colored "$COLOR_YELLOW" "* Release $tag exists -- re-uploading the asset"
        run gh release upload "$tag" "$dmg" --repo "$TAP_SLUG" --clobber
    else
        print_colored "$COLOR_BRIGHTYELLOW" "* Creating GitHub Release $tag on $TAP_SLUG"
        local args=(release create "$tag" "$dmg"
            --repo "$TAP_SLUG"
            --title "$APP_NAME $version"
            --notes-file "$notes")
        [[ "$draft" == "true" ]] && args+=(--draft)
        run gh "${args[@]}"
    fi

    cask_sha="$sha"   # consumed by bump_cask
}

bump_cask() {
    if [[ "$draft" == "true" ]]; then
        print_colored "$COLOR_YELLOW" "* --draft: leaving the cask at its current version"
        return 0
    fi

    local cask_rel="Casks/$CASK_TOKEN.rb"

    # Decide from the tap repo's committed state, so a re-run after a successful
    # commit skips cleanly while a re-run after a failed commit still bumps.
    #
    # Both the version AND the checksum have to match to skip. Testing the
    # version alone was wrong: re-cutting an existing version -- a rebuilt
    # artifact under the same number -- left the cask pointing at the previous
    # DMG's sha256, so every `brew install --cask` failed with a checksum
    # mismatch while the release itself looked fine.
    local committed
    committed="$(git -C "$tap_repo" show "HEAD:$cask_rel" 2>/dev/null || true)"
    if grep -q "^  version \"$version\"\$" <<<"$committed" \
        && grep -q "^  sha256 \"$cask_sha\"\$" <<<"$committed"; then
        print_colored "$COLOR_YELLOW" "* Cask already at $version with this checksum -- not re-bumping"
    else
        local message="$CASK_TOKEN $version"
        if grep -q "^  version \"$version\"\$" <<<"$committed"; then
            message="$CASK_TOKEN $version (rebuilt artifact)"
            print_colored "$COLOR_BRIGHTYELLOW" \
                "* Cask is at $version already, but the checksum changed -- re-pointing it"
        else
            print_colored "$COLOR_BRIGHTYELLOW" "* Bumping $CASK_TOKEN cask to $version in $tap_repo"
        fi
        run sed -i '' -E \
            -e "s|^  version \".*\"\$|  version \"$version\"|" \
            -e "s|^  sha256 \".*\"\$|  sha256 \"$cask_sha\"|" \
            "$tap_repo/$cask_rel"
        run git -C "$tap_repo" add "$cask_rel"
        run git -C "$tap_repo" commit -m "$message"
    fi

    # Always attempt the push: a no-op when the tap is already in sync, and the
    # retry path when an earlier run committed but failed to push.
    run git -C "$tap_repo" push
}

main() {
    parse_arguments "$@"

    validate

    if [[ "$go" != "true" ]]; then
        print_colored "$COLOR_YELLOW" "DRY RUN -- no changes will be made. Re-run with --go to publish."
    fi
    print_colored "$COLOR_GREEN" "Release $version build $build  ($tag)"
    print_colored "$COLOR_GREEN" "  DMG:       $dmg"
    print_colored "$COLOR_GREEN" "  notes:     $notes"
    print_colored "$COLOR_GREEN" "  tap repo:  $tap_repo"
    [[ "$draft" == "true" ]] && print_colored "$COLOR_YELLOW" "  mode:      draft (no cask bump)"
    printf '\n'

    push_source
    create_release
    bump_cask

    printf '\n'
    if [[ "$go" == "true" ]]; then
        print_colored "$COLOR_GREEN" "Published. Verify with:"
        if [[ "$draft" == "true" ]]; then
            print_colored "$COLOR_GREEN" "  gh release view $tag --repo $TAP_SLUG --web"
        else
            print_colored "$COLOR_GREEN" "  brew update && brew upgrade --cask $CASK_TOKEN"
        fi
    else
        print_colored "$COLOR_YELLOW" "Dry run complete. Re-run with --go to perform the steps above."
    fi
}

main "$@"
