#!/usr/bin/env bash
set -euo pipefail

# Compose the release notes for a Belvedere version and print them to stdout.
#
# A release's notes say three things, and only one of them is written by hand
# per release:
#
#   "Based on Markdown Preview <x.y.z>"   generated -- the upstream release the
#                                         build is on, read from git
#   "New in this release"                 docs/release-notes/UNRELEASED.md,
#                                         accumulated as work lands
#   "Changes on top of ... <x.y.z>"       docs/release-notes/ON-TOP-OF-UPSTREAM.md,
#                                         maintained with the fork, plus a generated
#                                         list of upstream commits the build carries
#                                         past that release
#
# The upstream base is the newest upstream commit HEAD contains
# (git merge-base HEAD upstream/main). Its Version.xcconfig names the upstream
# release, and the commits between that release's tag and the base are the ones
# that are on upstream's main but in no upstream release yet.
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
delta_file="$NOTES_DIR/ON-TOP-OF-UPSTREAM.md"
upstream_ref="${UPSTREAM_REF:-upstream/main}"
print_stub=false

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
    printf '%s\n' '      --delta FILE       "Changes on top of". Default: docs/release-notes/ON-TOP-OF-UPSTREAM.md'
    printf '%s\n' '      --upstream-ref REF Upstream branch to measure against. Default: upstream/main'
    printf '%s\n' '      --stub             Print the empty UNRELEASED.md stub instead, and exit.'
    printf '\n'
    printf '%b\n' "${COLOR_YELLOW}Environment:${COLOR_RESET}"
    printf '%s\n' '  UPSTREAM_REF   Same as --upstream-ref.'
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
Add a bullet below in the same commit as any change that alters what a
\`brew\`-installed user sees or does. A change to what Belvedere carries on top of
Markdown Preview also updates ON-TOP-OF-UPSTREAM.md. At release,
bin/compose-release-notes.sh builds <version>.md from both files; this comment
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
            --version|--unreleased|--delta|--upstream-ref)
                [[ $# -ge 2 && -n "$2" ]] || die "missing value for $1"
                case "$1" in
                    --version) version="$2" ;;
                    --unreleased) unreleased_file="$2" ;;
                    --delta) delta_file="$2" ;;
                    --upstream-ref) upstream_ref="$2" ;;
                esac
                shift 2 ;;
            *) die "unknown option: $1 (see --help)" ;;
        esac
    done
}

# Read a key from an xcconfig on stdin, e.g. MARKETING_VERSION.
read_xcconfig_key() {
    local key=$1
    awk -F' *= *' -v k="$key" '$1 == k { print $2; exit }'
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

# Upstream commit subjects as release-note bullets. Upstream's own release
# commits and merge commits are skipped, and every "(#123)" is dropped: on the
# tap repo's release page a #123 would link to the tap's issue 123, not
# upstream's. A squash of a PR whose title already cites an issue carries two,
# as in "… (#292) (#370)".
upstream_change_bullets() {
    local release_tag=$1 base_commit=$2
    git -C "$PROJECT_ROOT" log --first-parent --no-merges --reverse --format=%s \
            "$release_tag..$base_commit" \
        | { grep -vE '^Release [0-9]' || true; } \
        | sed -E \
            -e 's/[[:space:]]*\(#[0-9]+\)//g' \
            -e 's/^[a-z]+(\([^)]*\))?!?:[[:space:]]*//' \
        | awk '{ printf "- %s%s\n", toupper(substr($0, 1, 1)), substr($0, 2) }'
}

main() {
    parse_arguments "$@"

    if [[ "$print_stub" == "true" ]]; then
        print_unreleased_stub
        exit 0
    fi

    command -v git >/dev/null 2>&1 || die "git is required"
    [[ -f "$unreleased_file" ]] || die "missing $unreleased_file"
    [[ -f "$delta_file" ]] || die "missing $delta_file"

    # Version.xcconfig still holds the last release until `just release` bumps
    # it, so a preview without --version must not borrow that number.
    [[ -n "$version" ]] || version="— next release"

    git -C "$PROJECT_ROOT" rev-parse -q --verify "$upstream_ref^{commit}" >/dev/null \
        || die "cannot resolve $upstream_ref -- run: git fetch upstream --tags"

    local base_commit upstream_version release_tag
    base_commit="$(git -C "$PROJECT_ROOT" merge-base HEAD "$upstream_ref")" \
        || die "HEAD shares no history with $upstream_ref"
    upstream_version="$(git -C "$PROJECT_ROOT" show "$base_commit:Version.xcconfig" \
        | read_xcconfig_key MARKETING_VERSION)"
    [[ -n "$upstream_version" ]] \
        || die "could not read the upstream version at ${base_commit:0:7}"

    release_tag="v$upstream_version"
    git -C "$PROJECT_ROOT" rev-parse -q --verify "refs/tags/$release_tag^{commit}" >/dev/null \
        || die "no tag $release_tag for upstream $upstream_version -- run: git fetch upstream --tags"
    git -C "$PROJECT_ROOT" merge-base --is-ancestor "$release_tag" "$base_commit" \
        || die "tag $release_tag is not an ancestor of the upstream base ${base_commit:0:7}"

    local new_items delta_items later_changes later_count
    new_items="$(unreleased_body)"
    [[ -n "$new_items" ]] || die "$unreleased_file has nothing in it"
    [[ "$new_items" != *"$EMPTY_MARKER"* ]] \
        || die "$unreleased_file still says $EMPTY_MARKER -- nothing user-visible to release"
    # An instruction paragraph outside a comment would be published verbatim;
    # 1.2.0's release page shipped one.
    [[ "$new_items" != *"Add a bullet"* ]] \
        || die "$unreleased_file has maintainer instructions outside an HTML comment"

    delta_items="$(strip_comments_and_trim < "$delta_file")"
    [[ -n "$delta_items" ]] || die "$delta_file has nothing in it"

    later_changes="$(upstream_change_bullets "$release_tag" "$base_commit")"
    later_count=0
    [[ -n "$later_changes" ]] && later_count="$(printf '%s\n' "$later_changes" | wc -l | tr -d ' ')"

    printf '# Belvedere %s\n\n' "$version"
    printf 'Based on **Markdown Preview %s**' "$upstream_version"
    case "$later_count" in
        0) printf '.\n' ;;
        1) printf ', plus one upstream change made after that release — listed at the end.\n' ;;
        *) printf ', plus %s upstream changes made after that release — listed at the end.\n' "$later_count" ;;
    esac
    printf '\n## New in this release\n\n%s\n' "$new_items"
    printf '\n## Changes on top of Markdown Preview %s\n\n%s\n' "$upstream_version" "$delta_items"
    if [[ "$later_count" -gt 0 ]]; then
        printf '\n**Upstream changes after %s included in this build**\n\n' "$upstream_version"
        printf '%s\n\n%s\n' "These are on Markdown Preview's \`main\` but not yet in one of its releases:" \
            "$later_changes"
    fi

    print_colored "$COLOR_GREEN" \
        "composed notes for $version on Markdown Preview $upstream_version (+$later_count later upstream commits)"
}

main "$@"
