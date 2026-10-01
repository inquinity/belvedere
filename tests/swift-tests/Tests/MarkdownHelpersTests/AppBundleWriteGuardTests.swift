import Foundation
import XCTest
@testable import MarkdownHelpers

/// Belvedere must never write inside its own app bundle. The guard decides
/// from the path alone, so these build a stand-in bundle in a temp folder.
final class AppBundleWriteGuardTests: XCTestCase {
    private var root: URL!
    private var bundle: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("bundle-guard-\(UUID().uuidString)")
        bundle = root.appendingPathComponent("Belvedere.app")
        try FileManager.default.createDirectory(
            at: bundle.appendingPathComponent("Contents/Resources"),
            withIntermediateDirectories: true)
        try "x".write(to: bundle.appendingPathComponent("Contents/Resources/Acknowledgements.md"),
                      atomically: true, encoding: .utf8)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    private func inside(_ url: URL) -> Bool {
        AppBundleWriteGuard.isInside(url, bundle: bundle)
    }

    func testAFileInsideTheBundleIsInside() {
        XCTAssertTrue(inside(bundle.appendingPathComponent("Contents/Resources/Acknowledgements.md")))
        XCTAssertTrue(inside(bundle))
    }

    func testAFileThatDoesNotExistYetIsJudgedByItsFolder() {
        XCTAssertTrue(inside(bundle.appendingPathComponent("Contents/Resources/New Copy.md")))
        XCTAssertTrue(inside(bundle.appendingPathComponent("Contents/Brand New Folder/a/b.md")))
    }

    func testAnOutsidePathIsOutside() {
        XCTAssertFalse(inside(root.appendingPathComponent("notes.md")))
        XCTAssertFalse(inside(FileManager.default.temporaryDirectory.appendingPathComponent("a.md")))
    }

    /// `Belvedere.app-old` and `Belvedere.application` share a string prefix
    /// with the bundle but are different folders.
    func testASiblingWithTheSamePrefixIsOutside() throws {
        let sibling = root.appendingPathComponent("Belvedere.app-old")
        try FileManager.default.createDirectory(at: sibling, withIntermediateDirectories: true)
        XCTAssertFalse(inside(sibling.appendingPathComponent("a.md")))
        XCTAssertFalse(inside(root.appendingPathComponent("Belvedere.application/a.md")))
    }

    func testDotDotCannotWalkIntoTheBundle() {
        XCTAssertTrue(inside(root.appendingPathComponent("elsewhere/../Belvedere.app/Contents/x.md")))
    }

    func testASymlinkIntoTheBundleIsInside() throws {
        let link = root.appendingPathComponent("link")
        try FileManager.default.createSymbolicLink(
            at: link, withDestinationURL: bundle.appendingPathComponent("Contents/Resources"))
        XCTAssertTrue(inside(link.appendingPathComponent("Acknowledgements.md")))
        XCTAssertTrue(inside(link.appendingPathComponent("Not There Yet.md")))
    }

    func testASymlinkOutOfTheBundleIsOutside() throws {
        let outside = root.appendingPathComponent("outside")
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        let link = bundle.appendingPathComponent("Contents/out")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: outside)
        XCTAssertFalse(inside(link.appendingPathComponent("a.md")))
    }

    func testCaseDifferencesDoNotHideTheBundle() {
        XCTAssertTrue(inside(root.appendingPathComponent("BELVEDERE.APP/Contents/Resources/x.md")))
    }

    func testRequireOutsideThrowsOnlyForTheRunningBundle() throws {
        // The test process is not Belvedere, so an ordinary path passes.
        XCTAssertNoThrow(try AppBundleWriteGuard.requireOutsideAppBundle(root.appendingPathComponent("a.md")))
        XCTAssertTrue(AppBundleWriteGuard.isInsideAppBundle(Bundle.main.bundleURL.appendingPathComponent("x.md")))
        XCTAssertThrowsError(try AppBundleWriteGuard.requireOutsideAppBundle(
            Bundle.main.bundleURL.appendingPathComponent("Contents/x.md")))
    }
}
