#!/usr/bin/env bash
set -euo pipefail

# Compose the release notes for a Belvedere version and print them to stdout.
#
# The notes are what changed for someone using Belvedere, and nothing else: a
# title, then "New in this release" from docs/release-notes/UNRELEASED.md,
# written by hand as work lands. The test for every line is whether a reader
# cares. Upstream's version numbers, what Belvedere declined, and what it
# carries on top of Markdown Preview are ours to track, in docs/FORK-NOTES.md
# and docs/Upstream-Changed.md, not a reader's to read.
#
# Read-only: it prints, and `just release` writes the result to <v>.md. Run
# `just notes` to preview the notes for the next release.
#
# Requires bash (not POSIX sh); written for the bash 3.2 that ships with macOS.

COLOR_GREEN="\e[32m"
COLOR_RED="\e[31m"
COLOR_YELLOW="\e[33m"
COLOR_RESET="\e[0m"

print_colored() {
    local color=$1
    local message=$2
    printf "${color}${message}${COLOR_RESET}\n" >&2
}

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
NOTES_DIR="$PROJECT_ROOT/docs/release-notes"

# The marker the empty stub carries. Seeing it at release time means nothing
# user-visible was recorded, which is a reason to stop, not to ship empty notes.
EMPTY_MARKER="_(nothing yet)_"

version=""
unreleased_file="$NOTES_DIR/UNRELEASED.md"
print_stub=false
check_only=false

usage() {
    printf '%b\n' "${COLOR_YELLOW}Usage: compose-release-notes.sh [--version V] [options]${COLOR_RESET}"
    printf '\n'
    printf '%s\n' 'Print the release notes for version V to stdout. Without --version the'
    printf '%s\n' 'heading reads "next release": Version.xcconfig is only bumped by the release.'
    printf '\n'
    printf '%b\n' "${COLOR_YELLOW}Options:${COLOR_RESET}"
    printf '%s\n' '  -h, --help             Show this help text.'
    printf '%s\n' '      --version V        The Belvedere version the notes are for.'
    printf '%s\n' '      --unreleased FILE  "New in this release". Default: docs/release-notes/UNRELEASED.md'
    printf '%s\n' '      --stub             Print the empty UNRELEASED.md stub instead, and exit.'
    printf '%s\n' '      --check            Validate only: silent on success, and the notes are'
    printf '%s\n' '                         not printed. Used by `just release` before it builds.'
}

die() {
    print_colored "$COLOR_RED" "compose-release-notes: $*"
    exit 1
}

# The stub `just release` leaves behind. Kept here, next to the check that
# recognizes it, so the two cannot drift apart.
print_unreleased_stub() {
    cat <<EOF
# Unreleased

<!--
Add a bullet below in the same commit as any change a Belvedere user would
notice or want -- the test for every line is whether a reader cares. Not what
Belvedere declined, not upstream's version numbers, not About-box or license
housekeeping. Changes that come from a Markdown Preview sync go under a
"### Upstream features included in release" heading. At release,
bin/compose-release-notes.sh builds <version>.md from this file; this comment
and the heading above are dropped. See docs/RELEASE-AUTOMATION.md.
-->

$EMPTY_MARKER
EOF
}

parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help) usage; exit 0 ;;
            --stub) print_stub=true; shift ;;
            --check) check_only=true; shift ;;
            --version|--unreleased)
                [[ $# -ge 2 && -n "$2" ]] || die "missing value for $1"
                case "$1" in
                    --version) version="$2" ;;
                    --unreleased) unreleased_file="$2" ;;
                esac
                shift 2 ;;
            *) die "unknown option: $1 (see --help)" ;;
        esac
    done
}

# Drop full-line HTML comments (single- or multi-line) and leading/trailing
# blank lines. Comments carry maintainer instructions that must not reach a
# published release page.
strip_comments_and_trim() {
    awk '
        in_comment { if (index($0, "-->")) in_comment = 0; next }
        /^[[:space:]]*<!--/ { if (!index($0, "-->")) in_comment = 1; next }
        { lines[++line_count] = $0 }
        END {
            first = 1
            while (first <= line_count && lines[first] ~ /^[[:space:]]*$/) first++
            last = line_count
            while (last >= first && lines[last] ~ /^[[:space:]]*$/) last--
            for (line_index = first; line_index <= last; line_index++) print lines[line_index]
        }
    '
}

# UNRELEASED.md minus its "# Unreleased" heading and the stub's comment.
unreleased_body() {
    sed '1{/^# /d;}' "$unreleased_file" | strip_comments_and_trim
}

main() {
    parse_arguments "$@"

    if [[ "$print_stub" == "true" ]]; then
        print_unreleased_stub
        exit 0
    fi

    [[ -f "$unreleased_file" ]] || die "missing $unreleased_file"

    # Version.xcconfig still holds the last release until `just release` bumps
    # it, so a preview without --version must not borrow that number.
    [[ -n "$version" ]] || version="— next release"

    local new_items
    new_items="$(unreleased_body)"
    [[ -n "$new_items" ]] || die "$unreleased_file has nothing in it"
    [[ "$new_items" != *"$EMPTY_MARKER"* ]] \
        || die "$unreleased_file still says $EMPTY_MARKER -- nothing user-visible to release"
    # An instruction paragraph outside a comment would be published verbatim;
    # 1.2.0's release page shipped one.
    [[ "$new_items" != *"Add a bullet"* ]] \
        || die "$unreleased_file has maintainer instructions outside an HTML comment"

    # Validation only: the notes go nowhere and success says nothing, so a
    # release does not print a half-composed preview just before composing
    # the real thing.
    if [[ "$check_only" == "true" ]]; then
        exec >/dev/null
    fi

    printf '# Belvedere %s\n\n' "$version"
    printf '## New in this release\n\n%s\n' "$new_items"

    [[ "$check_only" == "true" ]] && return 0

    print_colored "$COLOR_GREEN" "composed notes for $version"
}

main "$@"
