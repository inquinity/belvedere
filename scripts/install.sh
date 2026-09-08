#!/usr/bin/env bash
set -euo pipefail

# Install a locally built Belvedere.app into /Applications and launch it once.
#
# Launching matters: macOS only registers a Quick Look extension for an app
# that lives in a standard location and has been run at least once -- see
# docs/INTERNAL-INSTALL.md. Without it, pressing space on a .md file shows
# plain text instead of a rendered preview.

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
APP_NAME="Belvedere"
SOURCE_APP="${SOURCE_APP:-$PROJECT_ROOT/build/$APP_NAME.app}"
INSTALL_DIR="${INSTALL_DIR:-/Applications}"

usage() {
    printf '%b\n' "${COLOR_YELLOW}Usage: install.sh [options]${COLOR_RESET}"
    printf '\n'
    printf '%s\n' 'Copy a locally built Belvedere.app into /Applications and launch it once.'
    printf '\n'
    printf '%b\n' "${COLOR_YELLOW}Options:${COLOR_RESET}"
    printf '%s\n' '  -h, --help    Show this help text.'
    printf '\n'
    printf '%b\n' "${COLOR_YELLOW}Environment:${COLOR_RESET}"
    printf '%s\n' '  SOURCE_APP    The built .app to install. Default: ./build/Belvedere.app'
    printf '%s\n' '  INSTALL_DIR   Where to install it. Default: /Applications'
}

die() {
    print_colored "$COLOR_RED" "error: $*" >&2
    exit 1
}

parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help) usage; exit 0 ;;
            *) die "unknown option: $1" ;;
        esac
    done
}

main() {
    parse_arguments "$@"

    [[ -d "$SOURCE_APP" ]] || die "no build at $SOURCE_APP -- run scripts/build.sh first"

    local target_app="$INSTALL_DIR/$APP_NAME.app"

    print_colored "$COLOR_YELLOW" "Installing $APP_NAME to $INSTALL_DIR"

    if [[ -d "$target_app" ]]; then
        print_colored "$COLOR_BRIGHTYELLOW" "* Removing existing $target_app"
        rm -rf "$target_app"
    fi

    print_colored "$COLOR_BRIGHTYELLOW" "* Copying"
    mkdir -p "$INSTALL_DIR"
    cp -R "$SOURCE_APP" "$target_app"

    print_colored "$COLOR_BRIGHTYELLOW" "* Launching once to register Quick Look"
    open "$target_app"

    print_colored "$COLOR_GREEN" "Done: $target_app"
    return 0
}

main "$@"
