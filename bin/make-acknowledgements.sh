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
# Rerun it whenever a component is added, removed, upgraded or relicensed. It
# refuses to run while a shipped notice is unaccounted for, a license is named
# without an https link, or a pinned link names a version other than the one
# that ships. ForkPostureTests runs its --check, so a stale page fails the
# tests.
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
#   "<component>|<license, as Markdown>|<notice paths, comma-separated>|<version source>"
# The page reads "**<component>** is used under the <license>."
#
# Link the license at the version that ships, not on a default branch: a
# default branch drifts. DOMPurify's did -- its LICENSE on main became
# Apache-only, while the 3.4.2 that ships is Apache-or-MPL. <version source>,
# when given, is a file whose first x.y.z is the version that ships (a VERSION
# file, or a bundle's banner); the script refuses to run unless the license
# links name that version, so an upgrade cannot leave the link behind.
# Markdown Preview is linked on main because this fork tracks its main, and
# CodeMirror because the bundled editor combines several of its packages.
# swift-markdown and swift-cmark have no version file here -- Package.resolved
# is not committed -- so recheck their tags by hand when the package updates.
ENTRIES=(
    "Markdown Preview|[MIT License](https://github.com/pluk-inc/markdown-preview/blob/main/LICENSE)|md-preview/Licenses/Markdown-Preview-LICENSE.txt|"
    "swift-markdown|[Apache License 2.0](https://github.com/swiftlang/swift-markdown/blob/0.8.0/LICENSE.txt), with its [NOTICE](https://github.com/swiftlang/swift-markdown/blob/0.8.0/NOTICE.txt)|md-preview/Licenses/swift-markdown-LICENSE.txt,md-preview/Licenses/swift-markdown-NOTICE.txt|"
    "swift-cmark|[BSD 2-Clause License](https://github.com/swiftlang/swift-cmark/blob/0.8.0/COPYING), with some files under the MIT License|md-preview/Licenses/swift-cmark-COPYING.txt|"
    "CodeMirror|[MIT License](https://code.haverbeke.berlin/codemirror/basic-setup/src/branch/main/LICENSE)|md-preview/Vendor/CodeMirror/CodeMirror-LICENSE.txt|"
    "DOMPurify|[Apache License 2.0 or Mozilla Public License 2.0](https://github.com/cure53/DOMPurify/blob/3.4.2/LICENSE)|md-preview/Vendor/DOMPurify/DOMPurify-LICENSE.txt|md-preview/Vendor/DOMPurify/purify.min.js"
    "highlight.js|[BSD 3-Clause License](https://github.com/highlightjs/highlight.js/blob/11.10.0/LICENSE), with its Terraform grammar under the [MIT License](https://github.com/taga3s/highlightjs-terraform/blob/v1.0.7/LICENSE)|md-preview/Vendor/Highlight/Highlight-LICENSE.txt|md-preview/Vendor/Highlight/Highlight-VERSION"
    "KaTeX|[MIT License](https://github.com/KaTeX/KaTeX/blob/v0.16.45/LICENSE)|md-preview/Vendor/KaTeX/KaTeX-LICENSE.txt|md-preview/Vendor/KaTeX/VERSION"
    "Mermaid|[MIT License](https://github.com/mermaid-js/mermaid/blob/mermaid@11.15.0/LICENSE)|md-preview/Vendor/Mermaid/LICENSE|md-preview/Vendor/Mermaid/Mermaid-VERSION"
    "morphdom|[MIT License](https://github.com/patrick-steele-idem/morphdom/blob/v2.7.8/LICENSE)|md-preview/Vendor/Morphdom/Morphdom-LICENSE.txt|md-preview/Vendor/Morphdom/Morphdom-VERSION"
)

mode="write"
scratch_file=""
# Fields of the entry split_entry last read.
entry_component=""
entry_license=""
entry_paths=""
entry_version_source=""

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

split_entry() {
    IFS='|' read -r entry_component entry_license entry_paths entry_version_source <<<"$1"
}

# One notice path per line. The final newline matters: `read` returns
# non-zero on an unterminated last line, and a loop over it would silently
# skip the last path -- which, for a one-notice entry, is the only one.
paths_of_entry() { printf '%s\n' "$entry_paths" | tr ',' '\n'; }

# Link targets in the license Markdown, one per line.
link_targets() { printf '%s\n' "$entry_license" | grep -oE '\]\([^)]*\)' | sed -E 's/^\]\((.*)\)$/\1/' || true; }

is_listed() {
    local wanted_path=$1 entry listed_paths
    for entry in "${ENTRIES[@]}"; do
        split_entry "$entry"
        # Captured first: piping straight into `grep -q` under pipefail can
        # report a match as a failure if grep exits before the writer is done.
        listed_paths="$(paths_of_entry)"
        grep -qxF "$wanted_path" <<<"$listed_paths" && return 0
    done
    return 1
}

# Every listed notice must exist, every notice on disk must be listed -- a new
# package notice or vendored library must not ship unacknowledged -- every
# link must be a complete https link, and a pinned link must name the version
# that ships.
validate_sources() {
    local entry notice_path candidate_path library_dir link_target targets
    local opened_links closed_links shipped_version
    for entry in "${ENTRIES[@]}"; do
        split_entry "$entry"
        while IFS= read -r notice_path; do
            [[ -f "$PROJECT_ROOT/$notice_path" ]] \
                || die "$notice_path is listed but does not exist."
        done < <(paths_of_entry)

        targets="$(link_targets)"
        # `|| true`: no "](" at all is reported by the check below, not by set -e.
        opened_links="$({ grep -o '](' <<<"$entry_license" || true; } | wc -l | tr -d ' ')"
        closed_links="$(grep -c . <<<"$targets" || true)"
        [[ "$opened_links" -gt 0 ]] \
            || die "$entry_component names its license without linking to it."
        [[ "$opened_links" -eq "$closed_links" ]] \
            || die "$entry_component has a link that is never closed."
        while IFS= read -r link_target; do
            [[ "$link_target" == https://* ]] \
                || die "$entry_component links to \"$link_target\"; use a full https URL."
        done <<<"$targets"

        if [[ -n "$entry_version_source" ]]; then
            [[ -f "$PROJECT_ROOT/$entry_version_source" ]] \
                || die "$entry_component: version source $entry_version_source does not exist."
            shipped_version="$(head -c 400 "$PROJECT_ROOT/$entry_version_source" \
                | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -n 1 || true)"
            [[ -n "$shipped_version" ]] \
                || die "$entry_component: no x.y.z version in $entry_version_source."
            [[ "$entry_license" == *"$shipped_version"* ]] \
                || die "$entry_component ships $shipped_version, but its license link names another version."
        fi
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
        for candidate_path in "$library_dir"*NOTICE*; do
            [[ -f "$candidate_path" ]] || continue
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
        split_entry "$entry"
        printf -- '- **%s** is used under the %s.\n' "$entry_component" "$entry_license"
    done
    printf '\nThe full text of each license, as it ships with this version of Belvedere,\n'
    # shellcheck disable=SC2016  # the backticks are Markdown code, not a substitution
    printf 'is also inside the app, in `Belvedere.app/Contents/Resources`; Mermaid'"'"'s is\n'
    # shellcheck disable=SC2016
    printf 'the file named `LICENSE`.\n'
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
