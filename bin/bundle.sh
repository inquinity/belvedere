#!/usr/bin/env bash
set -euo pipefail

# Zip a locally built Belvedere.app for sneaker-net distribution.
#
# Uses ditto rather than zip: zip can drop extended attributes and mangle the
# code signature's resource fork data, which ditto preserves.

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
VERSION_CONFIG="$PROJECT_ROOT/Version.xcconfig"
APP_NAME="Belvedere"
SOURCE_APP="${SOURCE_APP:-$PROJECT_ROOT/build/$APP_NAME.app}"
OUTPUT_DIR="${OUTPUT_DIR:-$PROJECT_ROOT/dist}"

usage() {
    printf '%b\n' "${COLOR_YELLOW}Usage: bundle.sh [options]${COLOR_RESET}"
    printf '\n'
    printf '%s\n' 'Zip a locally built Belvedere.app for sneaker-net distribution.'
    printf '\n'
    printf '%b\n' "${COLOR_YELLOW}Options:${COLOR_RESET}"
    printf '%s\n' '  -h, --help    Show this help text.'
    printf '\n'
    printf '%b\n' "${COLOR_YELLOW}Environment:${COLOR_RESET}"
    printf '%s\n' '  SOURCE_APP    The built .app to bundle. Default: ./build/Belvedere.app'
    printf '%s\n' '  OUTPUT_DIR    Where the .zip lands. Default: ./dist'
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

read_xcconfig() {
    local key=$1
    awk -F' *= *' -v k="$key" '$1 == k { print $2; exit }' "$VERSION_CONFIG"
}

main() {
    parse_arguments "$@"

    [[ -d "$SOURCE_APP" ]] || die "no build at $SOURCE_APP -- run bin/build.sh first"
    [[ -f "$VERSION_CONFIG" ]] || die "missing $VERSION_CONFIG"

    local version
    version="$(read_xcconfig MARKETING_VERSION)"
    [[ -n "$version" ]] || die "could not read MARKETING_VERSION from $VERSION_CONFIG"

    local zip_path="$OUTPUT_DIR/$APP_NAME-$version.zip"

    print_colored "$COLOR_YELLOW" "Bundling $APP_NAME $version"

    mkdir -p "$OUTPUT_DIR"
    rm -f "$zip_path"

    print_colored "$COLOR_BRIGHTYELLOW" "* Archiving"
    ditto -c -k --keepParent "$SOURCE_APP" "$zip_path"

    print_colored "$COLOR_GREEN" "Done: $zip_path"
    return 0
}

main "$@"
