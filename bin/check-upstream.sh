#!/usr/bin/env bash
set -euo pipefail

# Reports whether pluk-inc/markdown-preview has moved ahead of this fork.
# Read-only: fetches remote metadata and prints counts, never merges.

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

usage() {
    printf '%b\n' "${COLOR_YELLOW}Usage: check-upstream.sh [options]${COLOR_RESET}"
    printf '\n'
    printf '%s\n' 'Fetch upstream metadata and report whether new commits or tags exist.'
    printf '%s\n' 'Commit details are intentionally not listed.'
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

main() {
    local upstream_ref
    local local_ref
    local commits_behind
    local commits_ahead
    local latest_local_tag
    local latest_upstream_tag

    parse_arguments "$@"
    validate_git_context
    ensure_upstream_remote

    print_colored "$COLOR_BRIGHTYELLOW" "Fetching upstream metadata..."
    git fetch "$remote_name" --prune --tags >/dev/null

    resolve_remote_branch

    upstream_ref="$remote_name/$remote_branch"
    local_ref="HEAD"
    commits_behind="$(git rev-list --count "$local_ref..$upstream_ref")"
    commits_ahead="$(git rev-list --count "$upstream_ref..$local_ref")"

    latest_local_tag="$(git describe --tags --abbrev=0 "$local_ref" 2>/dev/null || true)"
    latest_upstream_tag="$(git describe --tags --abbrev=0 "$upstream_ref" 2>/dev/null || true)"

    print_colored "$COLOR_YELLOW" "Remote: $remote_name"
    print_colored "$COLOR_YELLOW" "Remote branch: $upstream_ref"

    if [[ $commits_behind -eq 0 ]]; then
        print_colored "$COLOR_GREEN" "No incoming changes"
    else
        print_colored "$COLOR_YELLOW" "Commits available: $commits_behind"
    fi

    print_colored "$COLOR_YELLOW" "Local-only commits: $commits_ahead"

    if [[ -n "$latest_upstream_tag" && "$latest_upstream_tag" != "$latest_local_tag" ]]; then
        print_colored "$COLOR_GREEN" "New tagged version: yes ($latest_upstream_tag)"
    else
        print_colored "$COLOR_GREEN" "New tagged version: no"
    fi
}

main "$@"
