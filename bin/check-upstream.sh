#!/usr/bin/env bash
set -euo pipefail

# Reports whether pluk-inc/markdown-preview has new commits since the last review.
# Read-only: fetches remote metadata and prints counts, never merges.
#
# Belvedere takes upstream changes by cherry-picking, so upstream's commits never
# become ancestors of HEAD and "HEAD..upstream/main" only grows. The count that
# matters starts at the review mark: the line "Reviewed through upstream: `<sha>`"
# near the top of docs/Upstream-Changed.md, moved forward after each sync round.

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

remote_name="${REMOTE:-upstream}"
remote_branch="${REMOTE_BRANCH:-}"
upstream_url="${UPSTREAM_URL:-https://github.com/pluk-inc/markdown-preview.git}"
review_record="${REVIEW_RECORD:-docs/Upstream-Changed.md}"

usage() {
    printf '%b\n' "${COLOR_YELLOW}Usage: check-upstream.sh [options]${COLOR_RESET}"
    printf '\n'
    printf '%s\n' 'Fetch upstream metadata and report how many upstream commits and tags'
    printf '%s\n' 'are newer than the review mark in docs/Upstream-Changed.md.'
    printf '%s\n' 'Commit details are intentionally not listed; for those, run:'
    printf '%s\n' '  git log --no-merges <mark>..upstream/main'
    printf '\n'
    printf '%b\n' "${COLOR_YELLOW}Options:${COLOR_RESET}"
    printf '%s\n' '  -h, --help             Show this help text.'
    printf '%s\n' '  -r, --remote NAME      Remote to inspect. Defaults to upstream.'
    printf '%s\n' '  -u, --url URL          Upstream repository URL.'
    printf '%s\n' '  -b, --branch NAME      Remote branch to inspect. Defaults to remote HEAD.'
}

die() {
    print_colored "$COLOR_RED" "error: $*" >&2
    exit 1
}

parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help)
                usage
                exit 0
                ;;
            -r|--remote)
                [[ $# -ge 2 ]] || die "missing value for $1"
                remote_name="$2"
                shift 2
                ;;
            -u|--url)
                [[ $# -ge 2 ]] || die "missing value for $1"
                upstream_url="$2"
                shift 2
                ;;
            -b|--branch)
                [[ $# -ge 2 ]] || die "missing value for $1"
                remote_branch="$2"
                shift 2
                ;;
            *)
                die "unknown option: $1"
                ;;
        esac
    done
}

ensure_upstream_remote() {
    if git remote get-url "$remote_name" >/dev/null 2>&1; then
        local existing_url
        existing_url=$(git remote get-url "$remote_name")
        if [[ "$existing_url" != "$upstream_url" ]]; then
            print_colored "$COLOR_BRIGHTYELLOW" "Updating remote '$remote_name' to: $upstream_url"
            git remote set-url "$remote_name" "$upstream_url"
        fi
    else
        print_colored "$COLOR_BRIGHTYELLOW" "Adding remote '$remote_name': $upstream_url"
        git remote add "$remote_name" "$upstream_url"
    fi
}

validate_git_context() {
    git rev-parse --is-inside-work-tree >/dev/null 2>&1 || die "must be run inside a Git work tree"
}

resolve_remote_branch() {
    local remote_head

    if [[ -z "$remote_branch" ]]; then
        remote_head="$(git symbolic-ref --quiet --short "refs/remotes/$remote_name/HEAD" 2>/dev/null || true)"
        if [[ -n "$remote_head" ]]; then
            remote_branch="${remote_head#"$remote_name/"}"
        else
            remote_branch="$(git remote show "$remote_name" | awk -F': ' '/HEAD branch/ {print $2}')"
        fi
    fi

    [[ -n "$remote_branch" ]] || die "could not determine default branch for '$remote_name'"
    git rev-parse --verify --quiet "$remote_name/$remote_branch" >/dev/null || die "remote branch '$remote_name/$remote_branch' was not found"
}

# Prints the commit recorded as "Reviewed through upstream: `<sha>`".
read_review_mark() {
    local mark_line
    local review_mark

    [[ -f "$review_record" ]] || die "review record not found: $review_record"
    mark_line="$(grep -m 1 -E '^Reviewed through upstream: `[0-9a-f]{7,40}`' "$review_record" || true)"
    [[ -n "$mark_line" ]] || die "no 'Reviewed through upstream: \`<sha>\`' line in $review_record"
    review_mark="${mark_line#*\`}"
    review_mark="${review_mark%%\`*}"
    git rev-parse --verify --quiet "${review_mark}^{commit}" >/dev/null \
        || die "review mark $review_mark is not a known commit; fetch upstream first"
    printf '%s\n' "$review_mark"
}

main() {
    local upstream_ref
    local review_mark
    local commits_since_review
    local latest_upstream_tag

    parse_arguments "$@"
    validate_git_context
    ensure_upstream_remote

    print_colored "$COLOR_BRIGHTYELLOW" "Fetching upstream metadata..."
    git fetch "$remote_name" --prune --tags >/dev/null

    resolve_remote_branch

    upstream_ref="$remote_name/$remote_branch"
    review_mark="$(read_review_mark)"
    commits_since_review="$(git rev-list --no-merges --count "$review_mark..$upstream_ref")"
    latest_upstream_tag="$(git describe --tags --abbrev=0 "$upstream_ref" 2>/dev/null || true)"

    print_colored "$COLOR_YELLOW" "Remote: $remote_name"
    print_colored "$COLOR_YELLOW" "Remote branch: $upstream_ref"
    print_colored "$COLOR_YELLOW" "Reviewed through: $review_mark"

    if [[ $commits_since_review -eq 0 ]]; then
        print_colored "$COLOR_GREEN" "No incoming changes"
    else
        print_colored "$COLOR_YELLOW" "Commits since review: $commits_since_review"
    fi

    # A tag is new when the reviewed commit does not already contain it.
    if [[ -n "$latest_upstream_tag" ]] \
        && ! git merge-base --is-ancestor "$latest_upstream_tag" "$review_mark"; then
        print_colored "$COLOR_GREEN" "New tagged version: yes ($latest_upstream_tag)"
    else
        print_colored "$COLOR_GREEN" "New tagged version: no"
    fi
}

main "$@"
