import Foundation
import XCTest
@testable import QuickLookHelpers

/// The Quick Look extension cannot give up `com.apple.security.network.client`
/// — WKWebView inside a sandboxed extension renders blank without it — so this
/// policy is the only thing stopping a spacebar preview from reaching out to a
/// server named by the document. These tests guard that.
final class QuickLookContentPolicyTests: XCTestCase {

    private let head = "<!DOCTYPE html><html><head><meta charset=\"UTF-8\"></head><body>x</body></html>"

    func testPolicyIsInsertedAsTheFirstChildOfHead() {
        let result = QuickLookContentPolicy.applying(to: head)
        XCTAssertTrue(
            result.contains("<head>" + QuickLookContentPolicy.metaTag),
            "The policy must be the first element in <head>, before anything it governs."
        )
    }

    func testRemoteOriginsAreNotPermitted() {
        for scheme in ["http:", "https:", "//"] {
            XCTAssertFalse(
                QuickLookContentPolicy.policy.contains(scheme),
                "\(scheme) must not appear in the policy — a document that "
                    + "references a remote image would then phone home when the "
                    + "file is previewed in Finder."
            )
        }
    }

    func testEverythingIsDeniedByDefault() {
        XCTAssertTrue(QuickLookContentPolicy.policy.hasPrefix("default-src 'none'"))
    }

    /// Both preview paths must keep working: the view controller inlines images
    /// as data URLs, QLPreviewReply passes them as cid: attachments.
    func testBothLocalImageTransportsArePermitted() {
        XCTAssertTrue(QuickLookContentPolicy.policy.contains("img-src data: cid:"))
    }

    /// If MarkdownHTML ever stops emitting a <head>, `applying(to:)` silently
    /// returns the page unpoliced rather than blanking the preview. This test
    /// is what turns that into a loud failure instead.
    func testRendererStillEmitsAHeadToInsertInto() {
        XCTAssertNotEqual(
            QuickLookContentPolicy.applying(to: head), head,
            "No <head> was found. The page would ship without a CSP."
        )
    }

    func testHTMLWithoutAHeadIsReturnedUnchanged() {
        let headless = "<p>no head here</p>"
        XCTAssertEqual(QuickLookContentPolicy.applying(to: headless), headless)
    }
}
