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

    // MARK: - The app bundle is never written

    /// `AppBundleWriteGuard` only protects the places that call it, so a call
    /// removed in a later change would pass every other test and quietly let
    /// the app save into its own signed bundle again. Each place that writes a
    /// file the reader chose, or moves one, must still name the guard.
    func testEveryWriteSiteStillCallsTheAppBundleGuard() throws {
        let sites = [
            ("belvedere/Document/DocumentWindowController+EditSession.swift", 4),
            ("belvedere/Document/DocumentWindowController+ImageHandling.swift", 2),
            ("belvedere/Rendering/MarkdownWebView+PDFExport.swift", 1),
        ]
        for (path, minimum) in sites {
            let calls = try text(at: path).components(separatedBy: "AppBundleWriteGuard").count - 1
            XCTAssertGreaterThanOrEqual(
                calls, minimum,
                "\(path) names AppBundleWriteGuard \(calls) times, expected at least \(minimum). A write site lost its guard."
            )
        }
    }

    // MARK: - Windows

    /// ⌘N makes a window of its own, whatever macOS's "Prefer tabs" setting
    /// says. The behaviour lives in AppKit's document machinery and needs the
    /// running app, so this only keeps the call from being deleted.
    func testNewDocumentAlwaysGetsItsOwnWindow() throws {
        let source = try text(at: "belvedere/App/MarkdownDocumentController.swift")
        let start = try XCTUnwrap(source.range(of: "func openUntitledDocumentAndDisplay"))
        XCTAssertTrue(source[start.lowerBound...].contains("markNextWindowAsSeparate()"),
                      "File > New must decline tab placement, or it joins the front window's tabs again.")
    }

    /// A window's folder boundary is its own. It lives on that window's
    /// controller and its web view, and nothing may hold one in a place every
    /// window can reach: a `static` or global store of a folder root is how a
    /// second window would come to read what only the first was allowed to.
    func testFolderBoundaryIsNeverSharedBetweenWindows() throws {
        let boundaryNames = ["openedFolderRoot", "containmentRoot", "currentContainmentRoot"]
        for file in try swiftSources() {
            let source = try String(contentsOf: file, encoding: .utf8)
            for line in source.components(separatedBy: "\n") {
                let code = line.trimmingCharacters(in: .whitespaces)
                guard !code.hasPrefix("//"), code.contains("static var") || code.contains("static let") else { continue }
                for name in boundaryNames {
                    XCTAssertFalse(code.contains(name),
                                   "\(file.lastPathComponent) stores \(name) in a static, shared by every window: \(code)")
                }
            }
        }
    }

    // MARK: - Opening folders

    /// A folder dropped on the Dock icon, or sent with Open With, is only
    /// accepted if the app declares it can open one. It must be ranked
    /// Alternate: Owner would make Belvedere the default app for every folder
    /// in Finder. Nothing here has an `NSDocumentClass`, because a folder never
    /// becomes a document: `MarkdownDocumentController` and the app delegate
    /// route it to `openFolder` first.
    func testInfoPlistAcceptsFoldersWithoutClaimingThem() throws {
        let info = try plist(at: "Info.plist")
        let types = try XCTUnwrap(info["CFBundleDocumentTypes"] as? [[String: Any]])
        let folder = try XCTUnwrap(
            types.first { ($0["LSItemContentTypes"] as? [String])?.contains("public.folder") == true },
            "Info.plist no longer declares public.folder, so the Dock icon rejects a dropped folder."
        )
        XCTAssertEqual(folder["LSHandlerRank"] as? String, "Alternate",
                       "Folders must be ranked Alternate, or Belvedere becomes the default for every folder.")
        XCTAssertNil(folder["NSDocumentClass"], "A folder is never a document.")
    }

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
        for path in ["belvedere/belvedere.entitlements",
                     "belvedere-quick-look/belvedere-quick-look.entitlements"] {
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
        let entitlements = try plist(at: "belvedere/belvedere.entitlements")
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
        let project = try text(at: "belvedere.xcodeproj/project.pbxproj")
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
        for path in ["belvedere/App/CrashReporter.swift",
                     "belvedere/App/UsageAnalyticsReporter.swift"] {
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
        let source = try text(at: "belvedere/App/AboutCopy.swift")
        XCTAssertTrue(
            source.contains("never connects on its own."),
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

    /// The one place this app connects, and the one way to reach it.
    ///
    /// "Never connects on its own" is a claim about code, not about intent. It
    /// holds while the app has exactly one URL session, that session belongs to
    /// the granted image fetch, and nothing builds it except the click that
    /// grants the image. A second session anywhere — a font, an update check, a
    /// "helpful" prefetch — falsifies the About box the moment it is added.
    func testTheOnlyURLSessionBelongsToTheGrantedImageFetch() throws {
        let owners = try swiftSources().filter { url in
            guard let source = try? String(contentsOf: url, encoding: .utf8) else { return false }
            return source.contains("URLSession(configuration:")
        }
        XCTAssertEqual(
            owners.map(\.lastPathComponent).sorted(), ["RemoteImageFetcher.swift"],
            """
            A URL session appeared outside the granted image fetch. Whatever it \
            is for, the About box now says something untrue: check \
            docs/FORK-NOTES.md (F2) before deciding this test is wrong.
            """
        )
    }

    /// Quick Look grants nothing, so it does not get the code that fetches.
    ///
    /// The extension previews whatever Finder has selected, with no window to
    /// ask in and no prompt to answer, so a remote image there could only be
    /// fetched without consent. Rather than rely on the button never appearing,
    /// the fetch is not compiled into that target at all.
    func testQuickLookDoesNotCompileTheFetcher() throws {
        let project = try text(at: "belvedere.xcodeproj/project.pbxproj")
        XCTAssertFalse(
            project.contains("Rendering/RemoteImageFetcher.swift"),
            """
            RemoteImageFetcher.swift is listed in the belvedere-quick-look target's \
            membership exceptions, so the extension now compiles the network \
            fetch. It has no way to ask the reader for consent.
            """
        )
        let webView = try text(at: "belvedere/Rendering/MarkdownWebView.swift")
        XCTAssertTrue(
            webView.contains("#if QUICK_LOOK_EXTENSION\n            return resolve(nil, \"unavailable\")"),
            """
            The deferred-asset path no longer refuses remote URLs in Quick Look \
            before reaching the fetcher. Without that branch the extension does \
            not build, and if it did, it would fetch without consent.
            """
        )
    }

    // MARK: - Identity

    func testBundleIdentityIsOursAndNotUpstreams() throws {
        let project = try text(at: "belvedere.xcodeproj/project.pbxproj")
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
        for path in ["belvedere-quick-look/PreviewViewController.swift",
                     "belvedere-quick-look/PreviewProvider.swift"] {
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

    /// Every page the app itself loads carries a Content-Security-Policy.
    /// The reader and the editor go through `PreviewContentPolicy`; the Mermaid
    /// popup builds a self-contained page with its own `default-src 'none'`.
    /// A new render path that loads HTML without either -- the kind of thing an
    /// upstream restructure adds -- would let a document reach the network.
    func testEveryAppPageLoadCarriesAContentPolicy() throws {
        let appSources = try swiftSources().filter { !$0.path.contains("/belvedere-quick-look/") }
        var loads = 0
        for file in appSources {
            let source = try String(contentsOf: file, encoding: .utf8)
            let lines = source.components(separatedBy: "\n")
            for (index, line) in lines.enumerated() where line.contains("loadHTMLString(")
                && !line.trimmingCharacters(in: .whitespaces).hasPrefix("//")
                && !line.contains("\"[mdp-perf") {
                if line.contains("loadHTMLString(\"\"") { continue }   // blanking a page
                loads += 1
                let call = lines[index..<min(index + 3, lines.count)].joined(separator: " ")
                let selfContained = file.lastPathComponent == "MermaidDiagramPopup.swift"
                    && source.contains("Content-Security-Policy\" content=\"default-src 'none'")
                XCTAssertTrue(
                    call.contains("PreviewContentPolicy.applying") || selfContained,
                    "\(file.lastPathComponent):\(index + 1) loads HTML without PreviewContentPolicy."
                )
            }
        }
        XCTAssertGreaterThanOrEqual(loads, 4, "Found too few page loads; has the scan stopped matching?")
    }

    // MARK: - Features declined from upstream

    /// Upstream's reopen snapshots wrote a PNG of each opened document's
    /// first screen to the app's Caches folder and kept up to 40 of them,
    /// with no clean-up when the document closed or was deleted. Belvedere
    /// removed the code, not just its default; a merge must not bring it back.
    func testDocumentSnapshotsStayRemoved() throws {
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: url("belvedere/Rendering/DocumentSnapshotCache.swift").path),
            "DocumentSnapshotCache.swift is back; an upstream merge restored reopen snapshots."
        )
        for file in try swiftSources() {
            let source = try String(contentsOf: file, encoding: .utf8)
            XCTAssertFalse(
                source.contains("DocumentSnapshotCache") || source.contains("\"DocumentSnapshots\""),
                "\(file.lastPathComponent) references the removed document snapshot cache."
            )
        }
    }

    /// Upstream's What's New window describes Markdown Preview's release,
    /// links to upstream's GitHub, and keys off upstream's build numbers, so it
    /// would open for every Belvedere user on each upstream bump. Its files are
    /// deleted, and a merge that restores them must not bring a caller with it.
    func testWhatsNewIsNeverPresented() throws {
        for file in try swiftSources() {
            let source = try String(contentsOf: file, encoding: .utf8)
            for call in ["WhatsNewWindow.present", "WhatsNewWindow.noteLaunch", "installWhatsNewMenuItem"] {
                XCTAssertFalse(
                    source.contains(call),
                    "\(file.lastPathComponent) calls \(call); upstream's What's New must stay switched off."
                )
            }
        }
    }

    // MARK: - License notices ship inside the app

    /// MIT, BSD and Apache attach their notices to *copies* of the code, and
    /// every DMG we publish is one. Anything under `belvedere/` is an app
    /// resource by virtue of the synchronized folder, so a file existing here
    /// means it is in the bundle.
    ///
    /// Upstream's notice ships as a copy rather than `LICENSE` itself, because
    /// Mermaid's license already takes the name `LICENSE` in the bundle.
    func testUpstreamLicenseShipsInTheApp() throws {
        XCTAssertEqual(
            try text(at: "belvedere/Licenses/Markdown-Preview-LICENSE.txt"),
            try text(at: "LICENSE"),
            """
            The copy of LICENSE shipped in the app no longer matches LICENSE. \
            Copy LICENSE over belvedere/Licenses/Markdown-Preview-LICENSE.txt.
            """
        )
    }

    /// Swift packages are compiled into the binary, so their notices ship too.
    ///
    /// Covers direct packages only. `Package.resolved` is not committed, so a
    /// dependency a package pulls in (swift-cmark, here) is listed by hand;
    /// check `SourcePackages/checkouts` whenever the package list changes.
    func testEveryLinkedPackageShipsItsNotices() throws {
        let marker = "XCRemoteSwiftPackageReference \""
        let project = try text(at: "belvedere.xcodeproj/project.pbxproj")
        let packages = Set(project.components(separatedBy: marker).dropFirst().compactMap {
            $0.split(separator: "\"", maxSplits: 1).first.map(String.init)
        })
        XCTAssertEqual(
            packages, ["swift-markdown"],
            """
            The app's Swift packages changed. Ship each new package's license \
            (and NOTICE, if it has one) in belvedere/Licenses/, including any \
            package it pulls in, then update this list.
            """
        )
        for path in ["belvedere/Licenses/swift-markdown-LICENSE.txt",
                     "belvedere/Licenses/swift-markdown-NOTICE.txt",
                     "belvedere/Licenses/swift-cmark-COPYING.txt"] {
            XCTAssertFalse(try text(at: path).isEmpty, "\(path) is empty.")
        }
    }

    /// Every vendored JavaScript library keeps its license beside it.
    func testEveryVendoredLibraryShipsItsLicense() throws {
        let libraries = try vendoredLibraries()
        XCTAssertFalse(libraries.isEmpty, "No vendored libraries found; has belvedere/Vendor moved?")
        for library in libraries {
            let files = try FileManager.default.contentsOfDirectory(atPath: library.path)
            XCTAssertTrue(
                files.contains { $0.uppercased().contains("LICENSE") },
                "belvedere/Vendor/\(library.lastPathComponent) has no license file beside it."
            )
        }
    }

    /// The About box's Acknowledgements link opens `Acknowledgements.md`: each
    /// component and the license it is used under, linked to that license,
    /// written by `bin/make-acknowledgements.sh`. The license texts themselves
    /// are the notices above, which ship in the app on their own.
    ///
    /// Its `--check` fails if any notice that ships is not acknowledged, if a
    /// license is named without an https link, or if the committed page is
    /// not what the script would write -- so a new vendored library cannot
    /// ship with the page still silent about it.
    func testAcknowledgementsAccountForEveryNotice() throws {
        let check = Process()
        check.executableURL = URL(fileURLWithPath: "/bin/bash")
        check.arguments = [url("bin/make-acknowledgements.sh").path, "--check"]
        let output = Pipe()
        check.standardOutput = output
        check.standardError = output
        try check.run()
        let report = String(
            decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self
        )
        check.waitUntilExit()
        XCTAssertEqual(check.terminationStatus, 0, "bin/make-acknowledgements.sh --check: \(report)")

        XCTAssertTrue(
            try text(at: "belvedere/App/AboutCopy.swift")
                .contains(#"forResource: "Acknowledgements", withExtension: "md""#),
            "The About box no longer links to Acknowledgements.md."
        )
    }

    // MARK: - Helpers

    private func vendoredLibraries() throws -> [URL] {
        try FileManager.default.contentsOfDirectory(
            at: url("belvedere/Vendor"), includingPropertiesForKeys: [.isDirectoryKey]
        ).filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
    }

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
        ["belvedere", "belvedere-quick-look"].flatMap { directory -> [URL] in
            let root = url(directory)
            guard let walker = FileManager.default.enumerator(
                at: root, includingPropertiesForKeys: nil
            ) else { return [] }
            return walker.compactMap { $0 as? URL }.filter { $0.pathExtension == "swift" }
        }
    }
}
