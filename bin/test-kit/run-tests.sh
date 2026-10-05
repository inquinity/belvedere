#!/usr/bin/env bash
set -euo pipefail

# Run Belvedere's Swift tests from a test kit and write a summary that is safe
# to paste into GitHub: no home directory, user name or computer name.
#
# This lives in bin/test-kit/ and is copied to the root of a kit by
# bin/make-test-kit.sh; it expects tests/swift-tests next to it.
#
# By default it runs only the three editor suites whose table tests fail on
# the development Mac, so a run on another macOS version is quick and answers
# one question: do they fail there too?

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

KIT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PACKAGE_PATH="$KIT_ROOT/tests/swift-tests"
RESULTS_DIR="$KIT_ROOT/results"
DEFAULT_FILTER='EditorFormattingTests|EditorScrollAnchorTests|EditorPreviewLayoutTests'

test_filter="$DEFAULT_FILTER"
publish_gist=false
swift_extra_args=()

usage() {
    print_colored "$COLOR_YELLOW" "Usage: run-tests.sh [options]"
    printf '\n'
    printf '%s\n' 'Run the Swift tests in this kit and write results/summary.md.'
    printf '\n'
    print_colored "$COLOR_YELLOW" "Options:"
    printf '%s\n' '  -h, --help           Show this help text.'
    printf '%s\n' '      --all            Run every test, not just the editor suites.'
    printf '%s\n' '      --filter REGEX   Run only tests matching REGEX (swift test --filter).'
    printf '%s\n' '      --gist           After the run, publish the summary as a secret'
    printf '%s\n' '                       GitHub gist with the gh tool, if it is signed in.'
    printf '%s\n' '      --swift-arg ARG  Pass ARG to swift test. Repeat for several.'
    printf '\n'
    print_colored "$COLOR_YELLOW" "Output (in results/ beside this script):"
    printf '%s\n' '  summary.md   Machine, versions, counts and failures. Safe to paste.'
    printf '%s\n' '  failures.md  Only the failure lines, redacted. Included in the gist.'
    printf '%s\n' '  full.log     Everything swift test printed. Not redacted: keep it local.'
    printf '\n'
    printf '%s\n' 'The first run downloads one Swift package (swift-markdown) from GitHub.'
}

die() {
    print_colored "$COLOR_RED" "error: $*" >&2
    exit 1
}

require_command() {
    command -v "$1" >/dev/null 2>&1 || die "$1 is required but was not found in PATH"
}

# Remove what identifies the person or the machine. The full log is not run
# through this, which is why it stays out of the gist and the summary.
redact() {
    local computer_name
    computer_name="$(scutil --get ComputerName 2>/dev/null || true)"
    local host_name
    host_name="$(hostname 2>/dev/null || true)"
    sed -E -e 's|/Users/[^/ ]+|/Users/USER|g' -e 's|/private/var/folders/[^ ]+|<tmp>|g' \
        | if [[ -n "$computer_name" ]]; then sed -e "s|$computer_name|<computer>|g"; else cat; fi \
        | if [[ -n "$host_name" ]]; then sed -e "s|$host_name|<host>|g"; else cat; fi
}

describe_machine() {
    printf 'macOS:        %s (build %s)\n' "$(sw_vers -productVersion)" "$(sw_vers -buildVersion)"
    printf 'Architecture: %s\n' "$(uname -m)"
    printf 'Swift:        %s\n' "$(swift --version 2>&1 | head -1)"
    printf 'Xcode:        %s\n' "$(xcodebuild -version 2>/dev/null | tr '\n' ' ' || printf 'not found')"
    printf 'Safari:       %s\n' "$(defaults read /Applications/Safari.app/Contents/Info CFBundleShortVersionString 2>/dev/null || printf 'unknown')"
}

describe_kit() {
    if [[ -f "$KIT_ROOT/KIT-INFO.txt" ]]; then
        cat "$KIT_ROOT/KIT-INFO.txt"
    else
        printf 'No KIT-INFO.txt: not a kit made by bin/make-test-kit.sh.\n'
    fi
}

parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help) usage; exit 0 ;;
            --all) test_filter="" ;;
            --filter)
                [[ $# -ge 2 ]] || die "--filter needs a pattern"
                test_filter="$2"; shift ;;
            --gist) publish_gist=true ;;
            --swift-arg)
                [[ $# -ge 2 ]] || die "--swift-arg needs a value"
                swift_extra_args+=("$2"); shift ;;
            *) die "unknown option: $1 (try --help)" ;;
        esac
        shift
    done
}

validate_environment() {
    require_command swift
    require_command sw_vers
    [[ -f "$PACKAGE_PATH/Package.swift" ]] \
        || die "tests/swift-tests/Package.swift not found next to this script. Run it from inside the kit folder."
    [[ -d "$KIT_ROOT/belvedere" ]] || die "belvedere/ is missing from the kit"
}

run_tests() {
    local swift_args=(test --package-path "$PACKAGE_PATH")
    if [[ -n "$test_filter" ]]; then
        swift_args+=(--filter "$test_filter")
    fi
    # `${array[@]+...}` keeps an empty array from failing under `set -u` on the
    # old bash that macOS ships.
    swift_args+=(${swift_extra_args[@]+"${swift_extra_args[@]}"})

    print_colored "$COLOR_BRIGHTYELLOW" "* swift ${swift_args[*]}"
    print_colored "$COLOR_YELLOW" "  Building can take several minutes the first time."
    # Keep going to the summary whether or not the tests pass.
    set +e
    swift "${swift_args[@]}" 2>&1 | tee "$RESULTS_DIR/full.log"
    test_status=${PIPESTATUS[0]}
    set -e
}

write_failures() {
    {
        printf '# Failures\n\n```\n'
        grep -E "error:|Test Case .* failed|error: fatalError|Compiling .* failed" "$RESULTS_DIR/full.log" \
            | sed -E 's|^.*/Tests/MarkdownHelpersTests/||' \
            | redact | cut -c1-260 | head -200 || true
        printf '```\n'
    } > "$RESULTS_DIR/failures.md"
}

write_summary() {
    local executed_line failed_names
    executed_line="$(grep -E "Executed [0-9]+ tests?" "$RESULTS_DIR/full.log" | tail -1 | sed -E 's/^[[:space:]]+//' || true)"
    failed_names="$(grep -E "Test Case .* failed" "$RESULTS_DIR/full.log" \
        | sed -E "s/.*Test Case '-\[(.*)\]' failed.*/\1/" | sort -u || true)"

    {
        printf '# Belvedere test run\n\n'
        printf '## Machine\n\n```\n'
        describe_machine | redact
        printf '```\n\n## Kit\n\n```\n'
        describe_kit | redact
        printf '```\n\n## Result\n\n'
        printf 'Filter: `%s`\n\n' "${test_filter:-(all tests)}"
        if [[ -z "$executed_line" ]]; then
            printf '**No tests ran** (the build failed or swift test stopped). Exit status %s. See failures.md.\n' "$test_status"
        elif [[ "$test_status" -eq 0 ]]; then
            printf '**PASSED.** %s\n' "$executed_line"
        else
            printf '**FAILED.** %s\n\n' "$executed_line"
            printf 'Failing tests:\n\n```\n%s\n```\n' "$failed_names"
        fi
    } > "$RESULTS_DIR/summary.md"
}

publish_summary() {
    require_command gh
    gh auth status >/dev/null 2>&1 || die "gh is not signed in (gh auth login), so the gist was not created"
    print_colored "$COLOR_BRIGHTYELLOW" "* Creating a secret gist from summary.md and failures.md"
    gh gist create --desc "Belvedere test run on macOS $(sw_vers -productVersion)" \
        "$RESULTS_DIR/summary.md" "$RESULTS_DIR/failures.md"
}

main() {
    parse_arguments "$@"
    validate_environment
    mkdir -p "$RESULTS_DIR"
    test_status=0
    run_tests
    write_failures
    write_summary

    printf '\n'
    print_colored "$COLOR_GREEN" "Summary: $RESULTS_DIR/summary.md"
    print_colored "$COLOR_GREEN" "Paste that file, and failures.md, into a GitHub issue or gist."
    print_colored "$COLOR_YELLOW" "full.log is not redacted; keep it local."
    if [[ "$publish_gist" == "true" ]]; then
        publish_summary
    fi
    exit "$test_status"
}

main "$@"
