#!/usr/bin/env bash
set -euo pipefail

# Build Belvedere locally for development and testing.
#
# Lighter-weight than bin/build-release.sh: no archive step -- compiles
# with signing disabled, then signs it ourselves -- with the Developer ID
# identity and notarization if those credentials are already in the keychain,
# or an ad-hoc signature otherwise so the app still runs on this machine.
#
# --release additionally packages a signed, notarized DMG into ./dist, the
# same artifact build-release.sh produces, but without its CHANGELOG.md
# requirement -- for a quick distributable build rather than an official,
# changelog-documented release.
#
# Source of truth: Version.xcconfig -> MARKETING_VERSION, CURRENT_PROJECT_VERSION

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
OUTPUT_DIR="${OUTPUT_DIR:-$PROJECT_ROOT/build}"
DIST_DIR="${DIST_DIR:-$PROJECT_ROOT/dist}"

SCHEME="md-preview"
APP_NAME="Belvedere"
APPEX_NAME="quick-look"
APP_ENTITLEMENTS="$PROJECT_ROOT/md-preview/md-preview.entitlements"
APPEX_ENTITLEMENTS="$PROJECT_ROOT/quick-look/quick-look.entitlements"
DEVELOPMENT_TEAM="${DEVELOPMENT_TEAM:-45GJWJVQN2}"
SIGNING_IDENTITY="${SIGNING_IDENTITY:-Developer ID Application: Altman Software Design, LLC ($DEVELOPMENT_TEAM)}"
NOTARY_PROFILE="${NOTARY_PROFILE:-altman-notary}"

update_segment=""
release_flag=false
work_dir=""

usage() {
    printf '%b\n' "${COLOR_YELLOW}Usage: build.sh [options]${COLOR_RESET}"
    printf '\n'
    printf '%s\n' 'Build Belvedere locally from Version.xcconfig.'
    printf '\n'
    printf '%b\n' "${COLOR_YELLOW}Options:${COLOR_RESET}"
    printf '%s\n' '  -h, --help              Show this help text.'
    printf '%s\n' '      --update SEGMENT    Bump the version before building.'
    printf '%s\n' '                          SEGMENT is major, minor, or revision.'
    printf '%s\n' '                          Also increments the build number.'
    printf '%s\n' '      --release           Also package a signed, notarized disk'
    printf '%s\n' '                          image into ./dist. Requires the signing'
    printf '%s\n' '                          identity and notary profile below --'
    printf '%s\n' '                          unlike a plain build, this does not fall'
    printf '%s\n' '                          back to an ad-hoc signature. No'
    printf '%s\n' '                          CHANGELOG.md entry is required, unlike'
    printf '%s\n' '                          bin/build-release.sh.'
    printf '\n'
    printf '%b\n' "${COLOR_YELLOW}Notarization:${COLOR_RESET}"
    printf '%s\n' '  Signs with the Developer ID identity and notarizes if both'
    printf '%s\n' '  that identity and the notary profile are already in the'
    printf '%s\n' '  keychain. Otherwise prints "Skipping notarization" and'
    printf '%s\n' '  ad-hoc signs, which only runs on this machine.'
    printf '\n'
    printf '%b\n' "${COLOR_YELLOW}Environment:${COLOR_RESET}"
    printf '%s\n' '  OUTPUT_DIR        Where the .app lands. Default: ./build'
    printf '%s\n' '  DIST_DIR          Where --release puts the .dmg. Default: ./dist'
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
            -h|--help) usage; exit 0 ;;
            --update)
                [[ $# -ge 2 ]] || die "missing value for $1"
                update_segment="$2"; shift 2 ;;
            --release) release_flag=true; shift ;;
            *) die "unknown option: $1" ;;
        esac
    done

    case "$update_segment" in
        ""|major|minor|revision) ;;
        *) die "--update must be major, minor, or revision (got: $update_segment)" ;;
    esac
}

read_xcconfig() {
    local key=$1
    awk -F' *= *' -v k="$key" '$1 == k { print $2; exit }' "$VERSION_CONFIG"
}

write_xcconfig() {
    local key=$1 value=$2
    # BSD sed: -i needs an explicit (empty) backup suffix.
    sed -i '' -E "s|^($key = ).*|\1$value|" "$VERSION_CONFIG"
}

# Bump one segment of MARKETING_VERSION (major.minor.revision), resetting the
# segments below it, and move CURRENT_PROJECT_VERSION forward with it -- an
# --update is a single "cut a new version" operation, not two independent ones.
bump_version() {
    local segment=$1
    local current_version major minor revision
    current_version="$(read_xcconfig MARKETING_VERSION)"
    [[ -n "$current_version" ]] || die "could not read MARKETING_VERSION from $VERSION_CONFIG"

    IFS='.' read -r major minor revision <<< "$current_version"
    [[ -n "$major" && -n "$minor" && -n "$revision" ]] \
        || die "MARKETING_VERSION is not in major.minor.revision form: $current_version"

    case "$segment" in
        major) major=$((major + 1)); minor=0; revision=0 ;;
        minor) minor=$((minor + 1)); revision=0 ;;
        revision) revision=$((revision + 1)) ;;
    esac

    local new_version="$major.$minor.$revision"
    local current_build new_build
    current_build="$(read_xcconfig CURRENT_PROJECT_VERSION)"
    [[ -n "$current_build" ]] || die "could not read CURRENT_PROJECT_VERSION from $VERSION_CONFIG"
    new_build=$((current_build + 1))

    write_xcconfig MARKETING_VERSION "$new_version"
    write_xcconfig CURRENT_PROJECT_VERSION "$new_build"

    print_colored "$COLOR_BRIGHTYELLOW" "Bumped version: $current_version ($current_build) -> $new_version ($new_build)"
}

require_command() {
    command -v "$1" >/dev/null 2>&1 || die "$1 is required but was not found"
}

# True if a real Developer ID signature can be produced and notarized without
# any extra setup here -- both the identity and a working notary profile are
# already in the keychain.
can_notarize() {
    security find-identity -v -p codesigning 2>/dev/null | grep -qF "$SIGNING_IDENTITY" \
        && xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" >/dev/null 2>&1
}

# codesign each bundle's own entitlements -- CODE_SIGNING_ALLOWED=NO during
# the build left both the app and the extension unsigned, so signing has to
# reattach them manually instead of inheriting what Xcode would normally set.
sign_component() {
    local target_path=$1 identity=$2 entitlements=$3
    shift 3
    codesign --force --sign "$identity" --entitlements "$entitlements" "$@" "$target_path"
}

# Wrap the built, Developer-ID-signed .app in a disk image for handing to
# someone else. Mirrors bin/build-release.sh's DMG steps -- starting from
# the app this script already built rather than re-archiving, since there is
# no separate release build to keep in sync.
#
# Reachable only under --release, whose validation already required a working
# signing identity and notary profile. So unlike the app build above, this
# does not fall back to an ad-hoc signature: a "release" DMG that cannot pass
# Gatekeeper on another Mac is not one worth producing silently.
package_dmg() {
    local app_path=$1 version=$2
    local staging_dir="$work_dir/dmg-staging"
    local dmg_path="$DIST_DIR/$APP_NAME $version.dmg"

    print_colored "$COLOR_BRIGHTYELLOW" "* Packaging a disk image"
    mkdir -p "$staging_dir" "$DIST_DIR"
    cp -R "$app_path" "$staging_dir/"
    ln -s /Applications "$staging_dir/Applications"
    rm -f "$dmg_path"
    hdiutil create \
        -volname "$APP_NAME" \
        -srcfolder "$staging_dir" \
        -ov -format UDZO \
        "$dmg_path"

    # hdiutil leaves the image unsigned, and `spctl -t open` then answers "no
    # usable signature" however well notarized the app inside it is.
    print_colored "$COLOR_BRIGHTYELLOW" "* Signing and notarizing the disk image"
    codesign --force --sign "$SIGNING_IDENTITY" --timestamp "$dmg_path"
    xcrun notarytool submit "$dmg_path" --keychain-profile "$NOTARY_PROFILE" --wait
    xcrun stapler staple "$dmg_path"

    print_colored "$COLOR_BRIGHTYELLOW" "* Verifying as Gatekeeper would"
    spctl -a -t open --context context:primary-signature -v "$dmg_path" \
        || die "Gatekeeper assessment failed -- do not distribute this DMG"

    print_colored "$COLOR_GREEN" "Done: $dmg_path"
    print_colored "$COLOR_GREEN" "Verify on a second Mac before handing it out."
}

main() {
    parse_arguments "$@"

    require_command xcodebuild
    require_command codesign
    [[ -f "$VERSION_CONFIG" ]] || die "missing $VERSION_CONFIG"
    [[ -f "$APP_ENTITLEMENTS" ]] || die "missing $APP_ENTITLEMENTS"
    [[ -f "$APPEX_ENTITLEMENTS" ]] || die "missing $APPEX_ENTITLEMENTS"

    if [[ "$release_flag" == "true" ]]; then
        require_command hdiutil
        security find-identity -v -p codesigning 2>/dev/null | grep -qF "$SIGNING_IDENTITY" \
            || die "signing identity not found in the keychain: $SIGNING_IDENTITY"
        xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" >/dev/null 2>&1 \
            || die "notary profile '$NOTARY_PROFILE' is missing or cannot authenticate.
       Create it with: xcrun notarytool store-credentials \"$NOTARY_PROFILE\" --team-id $DEVELOPMENT_TEAM
       Or drop --release for a local, ad-hoc-signed build instead."
    fi

    [[ -n "$update_segment" ]] && bump_version "$update_segment"

    local version build
    version="$(read_xcconfig MARKETING_VERSION)"
    build="$(read_xcconfig CURRENT_PROJECT_VERSION)"

    print_colored "$COLOR_YELLOW" "Building $APP_NAME $version ($build)"

    work_dir="$(mktemp -d)"
    local derived_data="$work_dir/DerivedData"
    local built_app="$derived_data/Build/Products/Release/$APP_NAME.app"
    local output_app="$OUTPUT_DIR/$APP_NAME.app"
    local appex_path="$output_app/Contents/PlugIns/$APPEX_NAME.appex"

    print_colored "$COLOR_BRIGHTYELLOW" "* Compiling"
    xcodebuild build \
        -project "$PROJECT_ROOT/md-preview.xcodeproj" \
        -scheme "$SCHEME" \
        -configuration Release \
        -destination 'platform=macOS' \
        -derivedDataPath "$derived_data" \
        CODE_SIGNING_ALLOWED=NO

    [[ -d "$built_app" ]] || die "build did not produce $built_app"

    mkdir -p "$OUTPUT_DIR"
    rm -rf "$output_app"
    cp -R "$built_app" "$output_app"
    [[ -d "$appex_path" ]] || die "build did not embed $appex_path"

    if can_notarize; then
        print_colored "$COLOR_BRIGHTYELLOW" "* Signing with Developer ID"
        sign_component "$appex_path" "$SIGNING_IDENTITY" "$APPEX_ENTITLEMENTS" --options runtime --timestamp
        sign_component "$output_app" "$SIGNING_IDENTITY" "$APP_ENTITLEMENTS" --options runtime --timestamp

        print_colored "$COLOR_BRIGHTYELLOW" "* Notarizing"
        local notarize_zip="$work_dir/app.zip"
        ditto -c -k --keepParent "$output_app" "$notarize_zip"
        xcrun notarytool submit "$notarize_zip" --keychain-profile "$NOTARY_PROFILE" --wait
        xcrun stapler staple "$output_app"
    else
        print_colored "$COLOR_RED" "Skipping notarization"
        print_colored "$COLOR_BRIGHTYELLOW" "* Self-signing (local, ad-hoc)"
        sign_component "$appex_path" - "$APPEX_ENTITLEMENTS"
        sign_component "$output_app" - "$APP_ENTITLEMENTS"
    fi

    print_colored "$COLOR_GREEN" "Done: $output_app"

    [[ "$release_flag" == "true" ]] && package_dmg "$output_app" "$version"

    return 0
}

main "$@"
