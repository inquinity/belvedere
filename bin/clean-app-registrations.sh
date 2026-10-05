#!/usr/bin/env bash
set -euo pipefail

# Find the Belvedere builds macOS still knows about and clear the stray ones.
#
# Every build leaves an app that Launch Services registers and Spotlight
# indexes, and bin/build.sh builds into a temporary folder that is deleted
# afterwards without being unregistered. The result is the same app listed
# several times in Open With, Launchpad and Spotlight, and Quick Look
# extensions that compete for the same files.
#
# Nothing changes unless you pass --apply. The installed app is always kept.

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

LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

apply=false
delete_builds=false
keep_paths=("/Applications/Belvedere.app" "$HOME/Applications/Belvedere.app")

usage() {
    print_colored "$COLOR_YELLOW" "Usage: clean-app-registrations.sh [options]"
    printf '\n'
    printf '%s\n' 'List every Belvedere app and Quick Look extension that Launch Services'
    printf '%s\n' 'knows about, and unregister the ones that are not the installed app.'
    printf '\n'
    print_colored "$COLOR_YELLOW" "Options:"
    printf '%s\n' '  -h, --help         Show this help text.'
    printf '%s\n' '  -n, --dry-run      List what would change. This is the default.'
    printf '%s\n' '      --apply        Do it: unregister the strays.'
    printf '%s\n' '      --delete-builds  With --apply, also delete build output that is safe to'
    printf '%s\n' '                     rebuild: this repository'"'"'s build.noindex/ folder, its Xcode'
    printf '%s\n' '                     DerivedData, and leftover temp build folders. Never'
    printf '%s\n' '                     another session'"'"'s scratch folder.'
    printf '%s\n' '      --keep PATH    Also keep PATH. Repeat for several.'
    printf '\n'
    print_colored "$COLOR_YELLOW" "Always kept:"
    printf '  %s\n' "${keep_paths[@]}"
}

die() {
    print_colored "$COLOR_RED" "error: $*" >&2
    exit 1
}

parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help) usage; exit 0 ;;
            -n|--dry-run) apply=false ;;
            --apply) apply=true ;;
            --delete-builds) delete_builds=true ;;
            --keep)
                [[ $# -ge 2 ]] || die "--keep needs a path"
                keep_paths+=("$2"); shift ;;
            *) die "unknown option: $1 (try --help)" ;;
        esac
        shift
    done
    if [[ "$delete_builds" == "true" && "$apply" != "true" ]]; then
        die "--delete-builds only makes sense with --apply"
    fi
}

validate_environment() {
    [[ -x "$LSREGISTER" ]] || die "lsregister not found at $LSREGISTER"
}

# Every registered path that is a Belvedere or Markdown Preview app, or the
# Quick Look extension inside one. Nested helper apps (Sparkle's Updater.app)
# are left out because they end in a different name.
registered_paths() {
    "$LSREGISTER" -dump 2>/dev/null \
        | sed -n -E 's/^path:[[:space:]]+(.*) \(0x[0-9a-f]+\)$/\1/p' \
        | grep -E '/(Belvedere|Belvedere \(Dev\)|Markdown Preview)\.app$|/quick-look\.appex$' \
        | sort -u
}

is_kept() {
    local candidate=$1 kept
    for kept in "${keep_paths[@]}"; do
        # The installed app, or the extension inside it.
        [[ "$candidate" == "$kept" || "$candidate" == "$kept/"* ]] && return 0
    done
    return 1
}

# Folders this script may delete with --delete-builds. A path is only deleted
# when it is one of these, never because it merely looks like a build.
deletable_root_for() {
    local app_path=$1
    case "$app_path" in
        "$PROJECT_ROOT"/build/*) printf '%s' "$PROJECT_ROOT/build" ;;
        "$PROJECT_ROOT"/build.noindex/*) printf '%s' "$PROJECT_ROOT/build.noindex" ;;
        "$HOME"/Library/Developer/Xcode/DerivedData/md-preview-*/*)
            printf '%s' "${app_path%%/Build/*}" ;;
        /private/var/folders/*/T/tmp.*/DerivedData/*)
            printf '%s' "${app_path%%/DerivedData/*}" ;;
        *) return 1 ;;
    esac
}

describe_state() {
    if [[ -e "$1" ]]; then printf 'exists '; else printf 'gone   '; fi
}

main() {
    parse_arguments "$@"
    validate_environment

    local kept_count=0 stray_count=0 deleted_count=0 registered
    local delete_roots=()

    print_colored "$COLOR_BRIGHTYELLOW" "* Belvedere entries known to Launch Services"
    while IFS= read -r registered; do
        [[ -n "$registered" ]] || continue
        if is_kept "$registered"; then
            kept_count=$((kept_count + 1))
            printf '  keep   %s%s\n' "$(describe_state "$registered")" "$registered"
            continue
        fi
        stray_count=$((stray_count + 1))
        printf '  stray  %s%s\n' "$(describe_state "$registered")" "$registered"
        if [[ "$apply" == "true" ]]; then
            "$LSREGISTER" -u "$registered" >/dev/null 2>&1 || true
            # An extension still on disk is also registered with pluginkit.
            if [[ "$registered" == *.appex && -e "$registered" ]]; then
                pluginkit -r "$registered" >/dev/null 2>&1 || true
            fi
        fi
        if [[ "$delete_builds" == "true" && -e "$registered" ]]; then
            local root
            if root="$(deletable_root_for "$registered")" && [[ -n "$root" && -e "$root" ]]; then
                delete_roots+=("$root")
            fi
        fi
    done < <(registered_paths)

    if [[ "$delete_builds" == "true" ]]; then
        # One folder can hold several stray entries; delete each once.
        local deduplicated_roots
        deduplicated_roots="$(printf '%s\n' ${delete_roots[@]+"${delete_roots[@]}"} | sort -u)"
        local build_root
        while IFS= read -r build_root; do
            [[ -n "$build_root" ]] || continue
            print_colored "$COLOR_YELLOW" "  delete $build_root"
            rm -rf -- "$build_root"
            deleted_count=$((deleted_count + 1))
        done <<< "$deduplicated_roots"
    fi

    printf '\n'
    if [[ "$apply" == "true" ]]; then
        print_colored "$COLOR_GREEN" "Unregistered $stray_count stray entries; kept $kept_count; deleted $deleted_count build folders."
        print_colored "$COLOR_YELLOW" "Open With and Spotlight can take a moment to catch up."
    else
        print_colored "$COLOR_YELLOW" "Dry run: $stray_count stray entries and $kept_count kept. Nothing changed."
        print_colored "$COLOR_GREEN" "Run again with --apply to unregister the strays (add --delete-builds to remove rebuildable build output)."
    fi
}

main "$@"
