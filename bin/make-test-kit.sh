#!/usr/bin/env bash
set -euo pipefail

# Build a folder you can copy to another Mac to run the Swift tests there.
#
# The tests locate their sources and fixtures relative to the repository
# layout, so the kit keeps that layout: md-preview/, quick-look/,
# tests/swift-tests/ and tests/fixtures/, plus run-tests.sh and a README at the
# top. It is a copy of the working tree, not of a commit, and KIT-INFO.txt says
# which commit it started from and whether the tree had uncommitted changes.

# Define color codes for terminal output
COLOR_GREEN="\e[32m"         # Used for success messages and instructions
COLOR_RED="\e[31m"           # Used for error messages and warnings
COLOR_YELLOW="\e[33m"        # Used for help text, lists, and informational content
COLOR_BRIGHTYELLOW="\e[93m"  # Used for highlighting important actions and status
COLOR_RESET="\e[0m"          # Used to reset color formatting

# Function to print colored output
print_colored() {
    local color=$1
    local message=$2
    printf "${color}${message}${COLOR_RESET}\n"
}

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUTPUT_DIR="${OUTPUT_DIR:-$PROJECT_ROOT/dist}"
KIT_SOURCES=(md-preview quick-look tests/swift-tests tests/fixtures)

make_archive=false
dry_run=false

usage() {
    print_colored "$COLOR_YELLOW" "Usage: make-test-kit.sh [options]"
    printf '\n'
    printf '%s\n' 'Create dist/belvedere-test-kit-<commit>-<date>/ to copy to another Mac.'
    printf '\n'
    print_colored "$COLOR_YELLOW" "Options:"
    printf '%s\n' '  -h, --help      Show this help text.'
    printf '%s\n' '  -n, --dry-run   Show what would be copied; create nothing.'
    printf '%s\n' '      --tar       Also write a .tar.gz of the kit next to it.'
    printf '\n'
    print_colored "$COLOR_YELLOW" "Environment:"
    printf '%s\n' '  OUTPUT_DIR      Where the kit is created. Default: ./dist'
}

die() {
    print_colored "$COLOR_RED" "error: $*" >&2
    exit 1
}

parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help) usage; exit 0 ;;
            -n|--dry-run) dry_run=true ;;
            --tar) make_archive=true ;;
            *) die "unknown option: $1 (try --help)" ;;
        esac
        shift
    done
}

# "abc1234" or "abc1234+" when the working tree has uncommitted changes.
describe_commit() {
    local commit
    commit="$(git -C "$PROJECT_ROOT" rev-parse --short HEAD 2>/dev/null)" || commit="unknown"
    if [[ -n "$(git -C "$PROJECT_ROOT" status --porcelain 2>/dev/null)" ]]; then
        commit="$commit+"
    fi
    printf '%s' "$commit"
}

write_kit_info() {
    local kit_dir=$1
    {
        printf 'commit:  %s\n' "$(describe_commit)"
        printf 'branch:  %s\n' "$(git -C "$PROJECT_ROOT" branch --show-current 2>/dev/null || printf unknown)"
        printf 'made:    %s\n' "$(date -u '+%Y-%m-%d %H:%M UTC')"
    } > "$kit_dir/KIT-INFO.txt"
}

# Symlinks in the test package point back into md-preview/ and quick-look/ by
# relative path. A dangling one would not fail until swift test tried to build.
check_symlinks() {
    local kit_dir=$1 broken
    broken="$(find -L "$kit_dir/tests/swift-tests/Sources" -type l 2>/dev/null || true)"
    [[ -z "$broken" ]] || die "dangling symlinks in the kit:
$broken"
}

main() {
    parse_arguments "$@"
    command -v rsync >/dev/null 2>&1 || die "rsync is required"
    local commit kit_name kit_dir
    commit="$(describe_commit)"
    kit_name="belvedere-test-kit-${commit}-$(date '+%Y%m%d')"
    kit_dir="$OUTPUT_DIR/$kit_name"

    for source_path in "${KIT_SOURCES[@]}"; do
        [[ -e "$PROJECT_ROOT/$source_path" ]] || die "missing $source_path"
    done

    if [[ "$dry_run" == "true" ]]; then
        print_colored "$COLOR_BRIGHTYELLOW" "DRY RUN: would create $kit_dir from:"
        printf '  %s\n' "${KIT_SOURCES[@]}" bin/test-kit/run-tests.sh bin/test-kit/README.txt
        exit 0
    fi

    [[ ! -e "$kit_dir" ]] || die "$kit_dir already exists; remove it first"
    mkdir -p "$kit_dir"
    for source_path in "${KIT_SOURCES[@]}"; do
        mkdir -p "$kit_dir/$(dirname "$source_path")"
        rsync -a --exclude '.build/' --exclude '.DS_Store' --exclude 'results/' \
            "$PROJECT_ROOT/$source_path" "$kit_dir/$(dirname "$source_path")/"
    done
    cp "$PROJECT_ROOT/bin/test-kit/run-tests.sh" "$PROJECT_ROOT/bin/test-kit/README.txt" "$kit_dir/"
    chmod +x "$kit_dir/run-tests.sh"
    write_kit_info "$kit_dir"
    check_symlinks "$kit_dir"

    if [[ "$make_archive" == "true" ]]; then
        tar -C "$OUTPUT_DIR" -czf "$OUTPUT_DIR/$kit_name.tar.gz" "$kit_name"
        print_colored "$COLOR_GREEN" "Archive: $OUTPUT_DIR/$kit_name.tar.gz"
    fi
    print_colored "$COLOR_GREEN" "Kit: $kit_dir"
    print_colored "$COLOR_GREEN" "Copy that folder to the other Mac, open a terminal in it and run: ./run-tests.sh"
    print_colored "$COLOR_YELLOW" "Size: $(du -sh "$kit_dir" | cut -f1)"
}

main "$@"
