#!/usr/bin/env bash
set -euo pipefail

# Build, sign, notarize and staple a distributable DMG.
#
# Replaces upstream's scripts/release.sh, which drove the Amore CLI against
# pluk-inc's hosting account and signing identity. This fork has neither, and
# distributes by handing the DMG over directly -- see docs/INTERNAL-INSTALL.md.
#
# Source of truth:
#   Version.xcconfig  -> MARKETING_VERSION, CURRENT_PROJECT_VERSION
#   CHANGELOG.md      -> a "## [X.Y.Z]" entry must exist for the version

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
CHANGELOG="$PROJECT_ROOT/CHANGELOG.md"
OUTPUT_DIR="${OUTPUT_DIR:-$PROJECT_ROOT/dist}"

SCHEME="md-preview"
APP_NAME="Belvedere"
DEVELOPMENT_TEAM="${DEVELOPMENT_TEAM:-45GJWJVQN2}"
SIGNING_IDENTITY="${SIGNING_IDENTITY:-Developer ID Application: Altman Software Design, LLC ($DEVELOPMENT_TEAM)}"
NOTARY_PROFILE="${NOTARY_PROFILE:-altman-notary}"

version_override=""
build_override=""
dry_run=false
skip_notarize=false
work_dir=""

usage() {
    printf '%b\n' "${COLOR_YELLOW}Usage: build-release.sh [options]${COLOR_RESET}"
    printf '\n'
    printf '%s\n' 'Build a signed, notarized, stapled DMG from Version.xcconfig.'
    printf '\n'
    printf '%b\n' "${COLOR_YELLOW}Options:${COLOR_RESET}"
    printf '%s\n' '  -h, --help            Show this help text.'
    printf '%s\n' '  -n, --dry-run         Print the steps without building or uploading.'
    printf '%s\n' '      --version X.Y.Z   Set MARKETING_VERSION before building.'
    printf '%s\n' '      --build N         Set CURRENT_PROJECT_VERSION before building.'
    printf '%s\n' '      --skip-notarize   Build and sign only. The DMG will NOT open on'
    printf '%s\n' '                        another Mac; for local smoke-testing only.'
    printf '\n'
    printf '%b\n' "${COLOR_YELLOW}Environment:${COLOR_RESET}"
    printf '%s\n' '  OUTPUT_DIR        Where the DMG lands. Default: ./dist'
    printf '%s\n' '  SIGNING_IDENTITY  Developer ID Application identity.'
    printf '%s\n' '  NOTARY_PROFILE    notarytool keychain profile. Default: altman-notary'
}

die() {
    print_colored "$COLOR_RED" "error: $*" >&2
    exit 1
}

cleanup() {
    [[ -n "$work_dir" && -d "$work_dir" ]] && rm -rf "$work_dir"
    return 0
}
trap cleanup EXIT

parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help)      usage; exit 0 ;;
            -n|--dry-run)   dry_run=true; shift ;;
            --skip-notarize) skip_notarize=true; shift ;;
            --version)
                [[ $# -ge 2 ]] || die "missing value for $1"
                version_override="$2"; shift 2 ;;
            --build)
                [[ $# -ge 2 ]] || die "missing value for $1"
                build_override="$2"; shift 2 ;;
            *) die "unknown option: $1" ;;
        esac
    done
}

# Echo a command, and run it unless this is a dry run.
run() {
    printf '  %b$%b %s\n' "$COLOR_BRIGHTYELLOW" "$COLOR_RESET" "$*"
    [[ "$dry_run" == "true" ]] && return 0
    "$@"
}

read_xcconfig() {
    local key=$1
    awk -F' *= *' -v k="$key" '$1 == k { print $2; exit }' "$VERSION_CONFIG"
}

write_xcconfig() {
    local key=$1 value=$2
    if [[ "$dry_run" == "true" ]]; then
        printf '  %b$%b set %s = %s\n' "$COLOR_BRIGHTYELLOW" "$COLOR_RESET" "$key" "$value"
        return 0
    fi
    # BSD sed: -i needs an explicit (empty) backup suffix.
    sed -i '' -E "s|^($key = ).*|\1$value|" "$VERSION_CONFIG"
}

require_command() {
    command -v "$1" >/dev/null 2>&1 || die "$1 is required but was not found"
}

validate_environment() {
    require_command xcodebuild
    require_command codesign
    require_command hdiutil
    require_command ditto

    [[ -f "$VERSION_CONFIG" ]] || die "missing $VERSION_CONFIG"
    [[ -f "$CHANGELOG" ]] || die "missing $CHANGELOG"

    security find-identity -v -p codesigning 2>/dev/null | grep -qF "$SIGNING_IDENTITY" \
        || die "signing identity not found in the keychain: $SIGNING_IDENTITY"

    if [[ "$skip_notarize" == "false" ]]; then
        xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" >/dev/null 2>&1 \
            || die "notary profile '$NOTARY_PROFILE' is missing or cannot authenticate.
       Create it with: xcrun notarytool store-credentials \"$NOTARY_PROFILE\" --team-id $DEVELOPMENT_TEAM"
    fi
}

# Notarize one file and staple the ticket onto the given target. Stapling is
# what lets Gatekeeper verify offline, which matters on networks that cannot
# reach Apple's notary endpoints.
notarize_and_staple() {
    local upload_path=$1
    local staple_target=$2

    if [[ "$skip_notarize" == "true" ]]; then
        print_colored "$COLOR_RED" "  skipping notarization (--skip-notarize)"
        return 0
    fi

    run xcrun notarytool submit "$upload_path" \
        --keychain-profile "$NOTARY_PROFILE" --wait
    run xcrun stapler staple "$staple_target"
}

main() {
    parse_arguments "$@"
    validate_environment

    [[ -n "$version_override" ]] && write_xcconfig MARKETING_VERSION "$version_override"
    [[ -n "$build_override" ]] && write_xcconfig CURRENT_PROJECT_VERSION "$build_override"

    local version build
    version="${version_override:-$(read_xcconfig MARKETING_VERSION)}"
    build="${build_override:-$(read_xcconfig CURRENT_PROJECT_VERSION)}"
    [[ -n "$version" ]] || die "could not read MARKETING_VERSION from $VERSION_CONFIG"

    grep -q "^## \[$version\]" "$CHANGELOG" \
        || die "no CHANGELOG.md entry for [$version] -- add one before releasing"

    print_colored "$COLOR_YELLOW" "Building $APP_NAME $version ($build)"
    print_colored "$COLOR_YELLOW" "Identity: $SIGNING_IDENTITY"
    [[ "$dry_run" == "true" ]] && print_colored "$COLOR_BRIGHTYELLOW" "DRY RUN -- nothing will be built or uploaded"

    work_dir="$(mktemp -d)"
    local archive_path="$work_dir/$SCHEME.xcarchive"
    local export_dir="$work_dir/export"
    local staging_dir="$work_dir/staging"
    local app_path="$export_dir/$APP_NAME.app"
    local dmg_path="$OUTPUT_DIR/$APP_NAME $version.dmg"

    print_colored "$COLOR_BRIGHTYELLOW" "* Archiving"
    run xcodebuild archive \
        -project "$PROJECT_ROOT/md-preview.xcodeproj" \
        -scheme "$SCHEME" \
        -configuration Release \
        -destination 'platform=macOS' \
        -archivePath "$archive_path"

    print_colored "$COLOR_BRIGHTYELLOW" "* Exporting a Developer ID build"
    cat > "$work_dir/export-options.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key><string>developer-id</string>
    <key>teamID</key><string>$DEVELOPMENT_TEAM</string>
    <key>signingStyle</key><string>automatic</string>
</dict>
</plist>
PLIST
    run xcodebuild -exportArchive \
        -archivePath "$archive_path" \
        -exportPath "$export_dir" \
        -exportOptionsPlist "$work_dir/export-options.plist"

    # The app is notarized and stapled before packaging so the ticket travels
    # inside the bundle, then the DMG is signed and notarized in its own right.
    # Gatekeeper assesses what the reader downloaded, not only what is inside.
    print_colored "$COLOR_BRIGHTYELLOW" "* Notarizing the app"
    run ditto -c -k --keepParent "$app_path" "$work_dir/app.zip"
    notarize_and_staple "$work_dir/app.zip" "$app_path"

    print_colored "$COLOR_BRIGHTYELLOW" "* Building the disk image"
    run mkdir -p "$staging_dir" "$OUTPUT_DIR"
    run cp -R "$app_path" "$staging_dir/"
    run ln -s /Applications "$staging_dir/Applications"
    run rm -f "$dmg_path"
    run hdiutil create \
        -volname "$APP_NAME" \
        -srcfolder "$staging_dir" \
        -ov -format UDZO \
        "$dmg_path"

    # hdiutil leaves the image unsigned, and `spctl -t open` then answers "no
    # usable signature" however well notarized the app inside it is.
    print_colored "$COLOR_BRIGHTYELLOW" "* Signing and notarizing the disk image"
    run codesign --force --sign "$SIGNING_IDENTITY" --timestamp "$dmg_path"
    notarize_and_staple "$dmg_path" "$dmg_path"

    if [[ "$dry_run" == "false" && "$skip_notarize" == "false" ]]; then
        print_colored "$COLOR_BRIGHTYELLOW" "* Verifying as Gatekeeper would"
        spctl -a -t open --context context:primary-signature -v "$dmg_path" \
            || die "Gatekeeper assessment failed -- do not distribute this DMG"
    fi

    print_colored "$COLOR_GREEN" "Done: $dmg_path"
    [[ "$dry_run" == "false" ]] && print_colored "$COLOR_GREEN" "Verify on a second Mac before handing it out."
    return 0
}

main "$@"
