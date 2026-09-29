#!/usr/bin/env bash
set -euo pipefail

# Build md-preview/Acknowledgements.md, the page the About box's
# Acknowledgements link opens.
#
# It names each open-source component the app includes and the license it is
# used under, linked to that license in the component's own repository -- a
# short page someone can actually read. It does not reproduce the license
# texts. They ship in the app on their own, as md-preview/Licenses/* and each
# md-preview/Vendor/<library>/*LICENSE*, which is what meets the MIT, BSD and
# Apache requirement that the notice travel with every copy. A link to GitHub
# alone would not: the file there can change, or disappear, and does not
# travel with the copy.
#
# Rerun it whenever a component is added, removed, or relicensed. It refuses to
# run while a notice ships that ENTRIES below does not account for, and
# ForkPostureTests runs its --check, so a stale page fails the tests.
#
# Requires bash (not POSIX sh); written for the bash 3.2 that ships with macOS.

COLOR_GREEN="\e[32m"
COLOR_RED="\e[31m"
COLOR_YELLOW="\e[33m"
COLOR_RESET="\e[0m"

print_colored() {
    local color=$1
    local message=$2
    printf '%b%s%b\n' "$color" "$message" "$COLOR_RESET" >&2
}

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUTPUT_PATH="md-preview/Acknowledgements.md"

# One entry per component, in reading order:
#   "<component>|<license, as Markdown>|<notice paths from the repo root, comma-separated>"
# The page reads "**<component>** is used under the <license>." Link the
# license file in the component's own repository, on its default branch. The
# paths are the notices that ship in the app for it.
ENTRIES=(
    "Markdown Preview|[MIT License](https://github.com/pluk-inc/markdown-preview/blob/main/LICENSE)|md-preview/Licenses/Markdown-Preview-LICENSE.txt"
    "swift-markdown|[Apache License 2.0](https://github.com/swiftlang/swift-markdown/blob/main/LICENSE.txt), with its [NOTICE](https://github.com/swiftlang/swift-markdown/blob/main/NOTICE.txt)|md-preview/Licenses/swift-markdown-LICENSE.txt,md-preview/Licenses/swift-markdown-NOTICE.txt"
    "swift-cmark|[BSD 2-Clause License](https://github.com/swiftlang/swift-cmark/blob/gfm/COPYING), with some files under the MIT License|md-preview/Licenses/swift-cmark-COPYING.txt"
    "CodeMirror|[MIT License](https://github.com/codemirror/codemirror/blob/master/LICENSE)|md-preview/Vendor/CodeMirror/CodeMirror-LICENSE.txt"
    "DOMPurify|[Apache License 2.0 or Mozilla Public License 2.0](https://github.com/cure53/DOMPurify/blob/main/LICENSE)|md-preview/Vendor/DOMPurify/DOMPurify-LICENSE.txt"
    "highlight.js|[BSD 3-Clause License](https://github.com/highlightjs/highlight.js/blob/main/LICENSE)|md-preview/Vendor/Highlight/Highlight-LICENSE.txt"
    "KaTeX|[MIT License](https://github.com/KaTeX/KaTeX/blob/main/LICENSE)|md-preview/Vendor/KaTeX/KaTeX-LICENSE.txt"
    "Mermaid|[MIT License](https://github.com/mermaid-js/mermaid/blob/develop/LICENSE)|md-preview/Vendor/Mermaid/LICENSE"
    "morphdom|[MIT License](https://github.com/patrick-steele-idem/morphdom/blob/master/LICENSE)|md-preview/Vendor/Morphdom/Morphdom-LICENSE.txt"
)

mode="write"
scratch_file=""

usage() {
    printf '%b\n' "${COLOR_YELLOW}Usage: make-acknowledgements.sh [options]${COLOR_RESET}"
    printf '\n'
    printf '%s\n' "Write $OUTPUT_PATH: each component and the license it is used under."
    printf '\n'
    printf '%b\n' "${COLOR_YELLOW}Options:${COLOR_RESET}"
    printf '%s\n' '  -h, --help      Show this help text.'
    printf '%s\n' '  -n, --dry-run   Print the file to stdout instead of writing it.'
    printf '%s\n' '      --check     Write nothing; exit 1 if the committed file is out of date.'
}

die() {
    print_colored "$COLOR_RED" "Error: $1"
    exit 1
}

cleanup() {
    [[ -n "$scratch_file" ]] && rm -f "$scratch_file"
    return 0
}

component_of() { printf '%s' "${1%%|*}"; }
license_of() { local rest="${1#*|}"; printf '%s' "${rest%|*}"; }
paths_of() { printf '%s' "${1##*|}" | tr ',' '\n'; }

is_listed() {
    local wanted_path=$1 entry listed_paths
    for entry in "${ENTRIES[@]}"; do
        # Captured first: piping straight into `grep -q` under pipefail can
        # report a match as a failure if grep exits before the writer is done.
        listed_paths="$(paths_of "$entry")"
        grep -qxF "$wanted_path" <<<"$listed_paths" && return 0
    done
    return 1
}

# Every listed notice must exist, every notice on disk must be listed -- a new
# package notice or vendored library must not ship unacknowledged -- and every
# link must be an https URL, since a relative one would resolve differently in
# the app bundle than in this repository.
validate_sources() {
    local entry notice_path candidate_path library_dir link_target
    for entry in "${ENTRIES[@]}"; do
        while IFS= read -r notice_path; do
            [[ -f "$PROJECT_ROOT/$notice_path" ]] \
                || die "$notice_path is listed but does not exist."
        done < <(paths_of "$entry")
        [[ "$(license_of "$entry")" == *"]("* ]] \
            || die "$(component_of "$entry") names its license without linking to it."
        while IFS= read -r link_target; do
            [[ "$link_target" == https://* ]] \
                || die "$(component_of "$entry") links to \"$link_target\"; use a full https URL."
        done < <(license_of "$entry" | grep -oE '\]\([^)]*\)' | sed -E 's/^\]\((.*)\)$/\1/')
    done
    for candidate_path in "$PROJECT_ROOT"/md-preview/Licenses/*; do
        [[ -f "$candidate_path" ]] || continue
        is_listed "${candidate_path#"$PROJECT_ROOT"/}" \
            || die "${candidate_path#"$PROJECT_ROOT"/} is not listed in ENTRIES."
    done
    for library_dir in "$PROJECT_ROOT"/md-preview/Vendor/*/; do
        for candidate_path in "$library_dir"*LICENSE*; do
            [[ -f "$candidate_path" ]] || die "${library_dir#"$PROJECT_ROOT"/} has no license file."
            is_listed "${candidate_path#"$PROJECT_ROOT"/}" \
                || die "${candidate_path#"$PROJECT_ROOT"/} is not listed in ENTRIES."
        done
    done
}

render() {
    local entry
    printf '# Acknowledgements\n\n'
    printf 'Belvedere is a fork of Markdown Preview and includes the open-source\n'
    printf 'software below.\n\n'
    for entry in "${ENTRIES[@]}"; do
        printf -- '- **%s** is used under the %s.\n' "$(component_of "$entry")" "$(license_of "$entry")"
    done
    printf '\nThe full text of each license, as it ships with this version of Belvedere,\n'
    printf 'is also inside the app, in `Belvedere.app/Contents/Resources`.\n'
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--help) usage; exit 0 ;;
        -n|--dry-run) mode="print" ;;
        --check) mode="check" ;;
        *) print_colored "$COLOR_RED" "Unknown option: $1"; usage >&2; exit 2 ;;
    esac
    shift
done

validate_sources

if [[ "$mode" == print ]]; then
    render
    exit 0
fi

trap cleanup EXIT
scratch_file="$(mktemp "${TMPDIR:-/tmp}/acknowledgements.XXXXXX")"
render > "$scratch_file"

if [[ "$mode" == check ]]; then
    if cmp -s "$scratch_file" "$PROJECT_ROOT/$OUTPUT_PATH"; then
        print_colored "$COLOR_GREEN" "$OUTPUT_PATH is up to date."
        exit 0
    fi
    print_colored "$COLOR_RED" "$OUTPUT_PATH is out of date. Run bin/make-acknowledgements.sh."
    exit 1
fi

cp "$scratch_file" "$PROJECT_ROOT/$OUTPUT_PATH"
print_colored "$COLOR_GREEN" "Wrote $OUTPUT_PATH (${#ENTRIES[@]} components)."
