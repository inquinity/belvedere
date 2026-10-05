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
# build.noindex, not build: Spotlight and Launch Services skip folders whose names
# end in .noindex, so a dev build never shows up as another Belvedere in
# Spotlight, Open With or Launchpad.
OUTPUT_DIR="${OUTPUT_DIR:-$PROJECT_ROOT/build.noindex}"
DIST_DIR="${DIST_DIR:-$PROJECT_ROOT/dist}"

SCHEME="belvedere"
APP_NAME="Belvedere"
APPEX_NAME="belvedere-quick-look"
APP_ENTITLEMENTS="$PROJECT_ROOT/belvedere/belvedere.entitlements"
APPEX_ENTITLEMENTS="$PROJECT_ROOT/belvedere-quick-look/belvedere-quick-look.entitlements"
DEVELOPMENT_TEAM="${DEVELOPMENT_TEAM:-45GJWJVQN2}"
SIGNING_IDENTITY="${SIGNING_IDENTITY:-Developer ID Application: Altman Software Design, LLC ($DEVELOPMENT_TEAM)}"
NOTARY_PROFILE="${NOTARY_PROFILE:-altman-notary}"

update_segment=""
release_flag=false
build_stamp=""
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

# Xcode expands build settings such as $(DEVELOPMENT_TEAM) in an .entitlements
# file when it signs; codesign does not. Signing with the source files shipped
# the app group as the literal "$(DEVELOPMENT_TEAM).com.altmansoftwaredesign
# .belvedere" (every release through 1.2.4), so neither the app nor its Quick
# Look extension was entitled to the group their code uses. Sign with an
# expanded copy instead, and refuse any build setting this does not expand.
render_entitlements() {
    local source_path=$1 rendered_path=$2
    sed "s/\$(DEVELOPMENT_TEAM)/$DEVELOPMENT_TEAM/g" "$source_path" > "$rendered_path"
    # shellcheck disable=SC2016  # a literal "$(" is exactly what to look for
    if grep -n '\$(' "$rendered_path" >&2; then
        die "unexpanded build setting in $source_path (shown above); expand it in render_entitlements"
    fi
}

# Check the signed result, not the file passed in: the app group a bundle is
# signed for must be the one its code reads from Info.plist, or the settings
# the app and Quick Look share silently stop reaching each other.
verify_app_group() {
    local bundle_path=$1
    local bundle_name expected_group signed_group signed_entitlements
    bundle_name="$(basename "$bundle_path")"
    signed_entitlements="$work_dir/signed-$bundle_name.plist"
    expected_group="$(/usr/libexec/PlistBuddy -c 'Print :MarkdownPreviewAppGroupIdentifier' \
        "$bundle_path/Contents/Info.plist")" \
        || die "$bundle_name has no MarkdownPreviewAppGroupIdentifier in its Info.plist"
    codesign -d --entitlements - --xml "$bundle_path" > "$signed_entitlements" 2>/dev/null \
        || die "could not read the signed entitlements of $bundle_name"
    signed_group="$(/usr/libexec/PlistBuddy -c 'Print :com.apple.security.application-groups:0' \
        "$signed_entitlements")" \
        || die "$bundle_name is not signed for any app group"
    [[ "$signed_group" == "$expected_group" ]] \
        || die "$bundle_name is signed for app group '$signed_group' but its code uses '$expected_group'; do not distribute this build"
}

# Acknowledgements.md opens from inside the bundle, usually in Belvedere
# itself, which may save any file it is asked to open. Saving it would modify
# the signed bundle and break its seal. Read-only makes that save fail: the
# app's in-place write fallback is refused. It is a narrow guard for the one
# document the app links to; treating the whole bundle as read-only is still
# to do (FORK-NOTES backlog). Permissions are not part of the code seal, so
# this is safe before or after signing.
protect_bundled_documents() {
    local app_path=$1
    local document="$app_path/Contents/Resources/Acknowledgements.md"
    [[ -f "$document" ]] || die "missing $document"
    chmod a-w "$document"
}

# Record what this build is, so About can tell a dev build from the release
# it started from: they share a version number. "release" under --release,
# otherwise the short commit, with a trailing + when the tree has uncommitted
# changes. Written into the built bundle's Info.plist, so it must run before
# signing, and never touches the source tree.
stamp_build() {
    local app_path=$1 stamp
    if [[ "$release_flag" == "true" ]]; then
        stamp="release"
    else
        stamp="$(git -C "$PROJECT_ROOT" rev-parse --short HEAD 2>/dev/null)" || stamp="unknown"
        [[ -n "$(git -C "$PROJECT_ROOT" status --porcelain 2>/dev/null)" ]] && stamp="$stamp+"
    fi
    /usr/libexec/PlistBuddy -c "Add :BelvedereBuildStamp string $stamp" \
        "$app_path/Contents/Info.plist" \
        || die "could not stamp $app_path/Contents/Info.plist"
    build_stamp=$stamp
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
    # No space in the filename: bin/publish-release.sh uploads this verbatim as
    # the release asset, and the cask URL is cleaner without a %20.
    local dmg_path="$DIST_DIR/$APP_NAME-$version.dmg"

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
    # It is substituted into the entitlements with sed, so hold it to the
    # shape of a real team ID.
    [[ "$DEVELOPMENT_TEAM" =~ ^[A-Z0-9]{10}$ ]] \
        || die "DEVELOPMENT_TEAM must be a 10-character team ID, got '$DEVELOPMENT_TEAM'"

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
    local app_entitlements="$work_dir/belvedere.entitlements"
    local appex_entitlements="$work_dir/belvedere-quick-look.entitlements"

    # Before compiling, so a setting it cannot expand fails in seconds.
    render_entitlements "$APP_ENTITLEMENTS" "$app_entitlements"
    render_entitlements "$APPEX_ENTITLEMENTS" "$appex_entitlements"

    print_colored "$COLOR_BRIGHTYELLOW" "* Compiling"
    xcodebuild build \
        -project "$PROJECT_ROOT/belvedere.xcodeproj" \
        -scheme "$SCHEME" \
        -configuration Release \
        -destination 'platform=macOS' \
        -derivedDataPath "$derived_data" \
        CODE_SIGNING_ALLOWED=NO

    [[ -d "$built_app" ]] || die "build did not produce $built_app"

    # Start from an empty output dir so renamed or stale bundles never pile up
    # here (e.g. an old MDView.app from before the rename to Belvedere).
    [[ -n "$OUTPUT_DIR" && "$OUTPUT_DIR" != "/" ]] || die "unsafe OUTPUT_DIR: '$OUTPUT_DIR'"
    rm -rf "$OUTPUT_DIR"
    mkdir -p "$OUTPUT_DIR"
    cp -R "$built_app" "$output_app"
    [[ -d "$appex_path" ]] || die "build did not embed $appex_path"
    protect_bundled_documents "$output_app"
    stamp_build "$output_app"

    if can_notarize; then
        print_colored "$COLOR_BRIGHTYELLOW" "* Signing with Developer ID"
        sign_component "$appex_path" "$SIGNING_IDENTITY" "$appex_entitlements" --options runtime --timestamp
        sign_component "$output_app" "$SIGNING_IDENTITY" "$app_entitlements" --options runtime --timestamp
        verify_app_group "$appex_path"
        verify_app_group "$output_app"

        print_colored "$COLOR_BRIGHTYELLOW" "* Notarizing"
        local notarize_zip="$work_dir/app.zip"
        ditto -c -k --keepParent "$output_app" "$notarize_zip"
        xcrun notarytool submit "$notarize_zip" --keychain-profile "$NOTARY_PROFILE" --wait
        xcrun stapler staple "$output_app"
    else
        print_colored "$COLOR_RED" "Skipping notarization"
        print_colored "$COLOR_BRIGHTYELLOW" "* Self-signing (local, ad-hoc)"
        sign_component "$appex_path" - "$appex_entitlements"
        sign_component "$output_app" - "$app_entitlements"
        verify_app_group "$appex_path"
        verify_app_group "$output_app"
    fi

    print_colored "$COLOR_GREEN" "Done: $output_app"
    # The same text About shows, so a tester can match the two.
    if [[ "$build_stamp" == "release" ]]; then
        print_colored "$COLOR_GREEN" "Build: Version $version"
    else
        print_colored "$COLOR_GREEN" "Build: Version $version (dev $build_stamp)"
    fi

    [[ "$release_flag" == "true" ]] && package_dmg "$output_app" "$version"

    return 0
}

main "$@"
