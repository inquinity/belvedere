#!/usr/bin/env bash
set -euo pipefail

# Build md-preview/Acknowledgements.txt, the one file the About box's
# Acknowledgements link opens.
#
# It is every third-party notice the app carries, verbatim, one after another:
# upstream's MIT notice and the Swift packages' notices (md-preview/Licenses/),
# then the vendored JavaScript libraries' licenses (md-preview/Vendor/). Those
# files stay the sources and still ship on their own; this collects them where
# a reader can find them.
#
# Rerun it whenever a notice changes or a package or vendored library is added
# or updated. It refuses to run while a notice exists that SECTIONS below does
# not list, and ForkPostureTests fails if the committed output is missing any
# notice's text.
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
OUTPUT_PATH="md-preview/Acknowledgements.txt"

# One entry per section, in reading order: "<heading>|<path from the repo root>".
SECTIONS=(
    "Markdown Preview (https://github.com/pluk-inc/markdown-preview)|md-preview/Licenses/Markdown-Preview-LICENSE.txt"
    "swift-markdown: LICENSE|md-preview/Licenses/swift-markdown-LICENSE.txt"
    "swift-markdown: NOTICE|md-preview/Licenses/swift-markdown-NOTICE.txt"
    "swift-cmark|md-preview/Licenses/swift-cmark-COPYING.txt"
    "CodeMirror|md-preview/Vendor/CodeMirror/CodeMirror-LICENSE.txt"
    "DOMPurify|md-preview/Vendor/DOMPurify/DOMPurify-LICENSE.txt"
    "highlight.js|md-preview/Vendor/Highlight/Highlight-LICENSE.txt"
    "KaTeX|md-preview/Vendor/KaTeX/KaTeX-LICENSE.txt"
    "Mermaid|md-preview/Vendor/Mermaid/LICENSE"
    "morphdom|md-preview/Vendor/Morphdom/Morphdom-LICENSE.txt"
)

mode="write"
scratch_file=""

usage() {
    printf '%b\n' "${COLOR_YELLOW}Usage: make-acknowledgements.sh [options]${COLOR_RESET}"
    printf '\n'
    printf '%s\n' "Collect every third-party notice into $OUTPUT_PATH."
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

heading_of() { printf '%s' "${1%%|*}"; }
path_of() { printf '%s' "${1#*|}"; }

is_listed() {
    local wanted_path=$1 entry
    for entry in "${SECTIONS[@]}"; do
        [[ "$(path_of "$entry")" == "$wanted_path" ]] && return 0
    done
    return 1
}

# Every listed file must exist, and every notice on disk must be listed: a new
# package notice or vendored library must not ship without appearing here.
validate_sources() {
    local entry candidate_path library_dir
    for entry in "${SECTIONS[@]}"; do
        [[ -f "$PROJECT_ROOT/$(path_of "$entry")" ]] \
            || die "$(path_of "$entry") is listed but does not exist."
    done
    for candidate_path in "$PROJECT_ROOT"/md-preview/Licenses/*; do
        [[ -f "$candidate_path" ]] || continue
        is_listed "${candidate_path#"$PROJECT_ROOT"/}" \
            || die "${candidate_path#"$PROJECT_ROOT"/} is not listed in SECTIONS."
    done
    for library_dir in "$PROJECT_ROOT"/md-preview/Vendor/*/; do
        for candidate_path in "$library_dir"*LICENSE*; do
            [[ -f "$candidate_path" ]] || die "${library_dir#"$PROJECT_ROOT"/} has no license file."
            is_listed "${candidate_path#"$PROJECT_ROOT"/}" \
                || die "${candidate_path#"$PROJECT_ROOT"/} is not listed in SECTIONS."
        done
    done
}

render() {
    local rule="================================================================================"
    local entry
    printf 'Belvedere - Acknowledgements\n'
    printf '============================\n\n'
    printf 'Belvedere is a fork of Markdown Preview and includes the open-source\n'
    printf 'software below. Each license and notice is reproduced in full.\n\n'
    for entry in "${SECTIONS[@]}"; do
        printf '  - %s\n' "$(heading_of "$entry")"
    done
    for entry in "${SECTIONS[@]}"; do
        printf '\n\n%s\n%s\n%s\n\n' "$rule" "$(heading_of "$entry")" "$rule"
        cat "$PROJECT_ROOT/$(path_of "$entry")"
    done
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
print_colored "$COLOR_GREEN" "Wrote $OUTPUT_PATH (${#SECTIONS[@]} notices)."
