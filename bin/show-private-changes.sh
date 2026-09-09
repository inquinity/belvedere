#!/usr/bin/env bash
set -euo pipefail

# Shows everything this fork changes relative to pluk-inc/markdown-preview.
# This is the canonical answer to "what have we done to the base project?" --
# see docs/FORK-NOTES.md for why each change exists.
#
# Read-only: fetches upstream and prints a diff, never merges.

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

usage() {
    printf '%b\n' "${COLOR_YELLOW}Usage: show-private-changes.sh [options]${COLOR_RESET}"
    printf '\n'
    printf '%s\n' 'Display all local changes (HEAD) that are not in upstream/main.'
    printf '%s\n' 'These are the fork customizations that are NOT contributed upstream.'
    printf '\n'
    printf '%b\n' "${COLOR_YELLOW}Options:${COLOR_RESET}"
    printf '%s\n' '  -h, --help             Show this help text.'
    printf '%s\n' '  --stat                 Show summary statistics instead of full diff.'
    printf '%s\n' '  --commits              Show commit log instead of file diff.'
}

die() {
    print_colored "$COLOR_RED" "error: $*" >&2
    exit 1
}

show_stat=false
show_commits=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--help)
            usage
            exit 0
            ;;
        --stat)
            show_stat=true
            shift
            ;;
        --commits)
            show_commits=true
            shift
            ;;
        *)
            die "unknown option: $1"
            ;;
    esac
done

git rev-parse --is-inside-work-tree >/dev/null 2>&1 || die "must be run inside a Git work tree"
git remote get-url upstream >/dev/null 2>&1 || die "upstream remote is not configured"

print_colored "$COLOR_BRIGHTYELLOW" "Fetching upstream..."
git fetch upstream main >/dev/null 2>&1

print_colored "$COLOR_YELLOW" "Fork changes in HEAD (not in upstream/main):"
printf '\n'

if [[ "$show_commits" == "true" ]]; then
    # Two dots for the log: commits reachable from HEAD but not upstream/main.
    # Three dots here would give the symmetric difference and pull in upstream's
    # own commits, which is not what we want.
    print_colored "$COLOR_YELLOW" "Commits:"
    git log --oneline upstream/main..HEAD
elif [[ "$show_stat" == "true" ]]; then
    # Three dots for the diffs: compare against the merge base, so upstream work
    # we have not merged yet is not reported as if this fork had deleted it.
    print_colored "$COLOR_YELLOW" "Changed files summary:"
    git diff --stat upstream/main...HEAD
else
    git diff upstream/main...HEAD
fi
