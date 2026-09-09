import Foundation
import XCTest

/// Guards the fork's posture against an upstream merge quietly undoing it.
///
/// Upstream ships roughly seventy commits a month and every one of these
/// properties lives in a file they also edit — entitlements, `Info.plist`,
/// `project.pbxproj`. A conflict resolved the wrong way would restore telemetry
/// or an updater without anyone noticing at review time. These tests read the
/// real files in the checkout and fail loudly instead.
///
/// They are deliberately assertions about *configuration*, not behaviour. The
/// behavioural side lives in `SanitizerNegativeTests` and
/// `QuickLookContentPolicyTests`.
final class ForkPostureTests: XCTestCase {

    // MARK: - Network egress

    /// Both targets need this entitlement and neither can give it up.
    ///
    /// A sandboxed app cannot complete a WKWebView load without it — the window
    /// renders entirely blank. It was removed in M3 on the assumption that the
    /// sandbox could enforce "no network connections" structurally; it cannot.
    /// The guarantee rests on the absence of code that connects, plus a CSP for
    /// content-initiated requests.
    ///
    /// This is asserted rather than merely documented so nobody re-derives the
    /// original, wrong conclusion and ships a blank app.
    func testBothTargetsKeepTheNetworkEntitlementWKWebViewRequires() throws {
        for path in ["md-preview/md-preview.entitlements",
                     "quick-look/quick-look.entitlements"] {
            let entitlements = try plist(at: path)
            XCTAssertEqual(
                entitlements["com.apple.security.network.client"] as? Bool, true,
                """
                \(path) has lost com.apple.security.network.client. That surface \
                will render blank — silently, with no error. Removing it does not \
                buy a no-network guarantee; WKWebView simply stops working.
                """
            )
        }
    }

    func testAppleEventsEntitlementsAreGone() throws {
        let entitlements = try plist(at: "md-preview/md-preview.entitlements")
        XCTAssertNil(entitlements["com.apple.security.automation.apple-events"])
        XCTAssertNil(
            entitlements["com.apple.security.temporary-exception.apple-events"],
            "The Terminal automation exception is back. It existed only for the CLI installer."
        )
    }

    // MARK: - Telemetry and updater

    func testInfoPlistCarriesNoTelemetryOrUpdaterKeys() throws {
        let info = try plist(at: "Info.plist")
        for key in ["SentryDSN", "PostHogProjectToken",
                    "SUFeedURL", "SUPublicEDKey",
                    "SUEnableAutomaticChecks", "SUEnableInstallerLauncherService"] {
            XCTAssertNil(info[key], "Info.plist has regained \(key).")
        }
    }

    func testProjectDeclaresNoTelemetryOrUpdaterDependencies() throws {
        let project = try text(at: "md-preview.xcodeproj/project.pbxproj")
        for needle in ["sentry-cocoa", "Sentry", "Sparkle", "sentry-cli"] {
            XCTAssertFalse(
                project.contains(needle),
                "project.pbxproj references \(needle) again."
            )
        }
    }

    func testNoSourceFileImportsTelemetryOrUpdaterFrameworks() throws {
        let offenders = try swiftSources().filter { url in
            guard let source = try? String(contentsOf: url, encoding: .utf8) else { return false }
            return source.contains("import Sentry") || source.contains("import Sparkle")
        }
        XCTAssertTrue(
            offenders.isEmpty,
            "Telemetry/updater imports are back in: \(offenders.map(\.lastPathComponent))"
        )
    }

    /// The reporters are stubs, not deletions, so that upstream's call sites
    /// keep compiling untouched. That only holds while the bodies stay empty.
    func testTelemetryReportersRemainStubs() throws {
        for path in ["md-preview/App/CrashReporter.swift",
                     "md-preview/App/UsageAnalyticsReporter.swift"] {
            let source = try text(at: path)
            XCTAssertFalse(source.contains("URLSession"),
                           "\(path) has regained a URLSession.")
            XCTAssertFalse(source.contains("https://"),
                           "\(path) has regained an endpoint URL.")
        }
    }

    /// The About box tells the user the app never connects on its own. That
    /// claim rests on the two reporters above being stubs and the updater being
    /// gone, so the claim and the code that makes it true are asserted together.
    ///
    /// If a merge ever restores telemetry, `testTelemetryReportersRemainStubs`
    /// fails first. This test exists for the opposite direction: it fails if the
    /// claim is quietly softened or deleted while the posture still holds, and
    /// it names the file to edit if the posture ever legitimately changes.
    func testAboutBoxStillMakesTheNoNetworkClaim() throws {
        let source = try text(at: "md-preview/App/AboutCopy.swift")
        XCTAssertTrue(
            source.contains("Never connects on its own."),
            """
            The About box no longer claims the app never connects on its own. \
            If that is because the app gained an outbound connection, this test \
            is the least of it. If the wording simply changed, update the string \
            here and in both Localizable.strings files.
            """
        )
        XCTAssertTrue(
            source.contains("Remote content stays blocked until you allow it."),
            "The About box no longer states that remote content is blocked by default."
        )
    }

    // MARK: - Identity

    func testBundleIdentityIsOursAndNotUpstreams() throws {
        let project = try text(at: "md-preview.xcodeproj/project.pbxproj")
        XCTAssertFalse(
            project.contains("doc.md-preview"),
            "An upstream bundle identifier is back — a merge conflict was resolved the wrong way."
        )
        XCTAssertFalse(
            project.contains("5P3TSMNV42"),
            "Upstream's DEVELOPMENT_TEAM is back; the build would not sign with our certificate."
        )
        XCTAssertTrue(project.contains("com.altmansoftwaredesign.belvedere"))
        XCTAssertTrue(project.contains("DEVELOPMENT_TEAM = 45GJWJVQN2;"))
    }

    // MARK: - Quick Look policy is actually applied

    /// `QuickLookContentPolicyTests` proves the policy is correct. This proves
    /// it is reached: both preview paths must pass their HTML through it.
    func testBothQuickLookPathsApplyTheContentPolicy() throws {
        for path in ["quick-look/PreviewViewController.swift",
                     "quick-look/PreviewProvider.swift"] {
            XCTAssertTrue(
                try text(at: path).contains("QuickLookContentPolicy.applying"),
                """
                \(path) no longer applies the Content-Security-Policy. The page \
                would ship without one and a previewed document could load \
                remote images.
                """
            )
        }
    }

    // MARK: - Helpers

    private func url(_ relativePath: String) -> URL {
        TestVendor.repositoryRoot.appendingPathComponent(relativePath)
    }

    private func text(at relativePath: String) throws -> String {
        try String(contentsOf: url(relativePath), encoding: .utf8)
    }

    private func plist(at relativePath: String) throws -> [String: Any] {
        let data = try Data(contentsOf: url(relativePath))
        let parsed = try PropertyListSerialization.propertyList(
            from: data, options: [], format: nil
        )
        return try XCTUnwrap(parsed as? [String: Any], "\(relativePath) is not a plist dictionary")
    }

    /// Every Swift file shipped in the app and the extension. Excludes the test
    /// package, which symlinks a subset of them.
    private func swiftSources() throws -> [URL] {
        ["md-preview", "quick-look"].flatMap { directory -> [URL] in
            let root = url(directory)
            guard let walker = FileManager.default.enumerator(
                at: root, includingPropertiesForKeys: nil
            ) else { return [] }
            return walker.compactMap { $0 as? URL }.filter { $0.pathExtension == "swift" }
        }
    }
}
