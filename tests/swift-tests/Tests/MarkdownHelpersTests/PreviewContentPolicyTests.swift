import Foundation
import XCTest
@testable import MarkdownHelpers

/// With `com.apple.security.network.client` un-removable from both targets,
/// this policy is the only thing preventing a document rendered in the app
/// window from reaching a server. These tests guard it.
final class PreviewContentPolicyTests: XCTestCase {

    private let head = "<!DOCTYPE html><html><head><meta charset=\"UTF-8\"></head><body>x</body></html>"

    func testPolicyIsInsertedAsTheFirstChildOfHead() {
        let result = PreviewContentPolicy.applying(to: head)
        XCTAssertTrue(
            result.contains("<head>" + PreviewContentPolicy.metaTag),
            "The policy must precede everything it governs."
        )
    }

    func testRemoteOriginsAreNotPermitted() {
        for scheme in ["http:", "https:"] {
            XCTAssertFalse(
                PreviewContentPolicy.policy.contains(scheme),
                """
                \(scheme) must not appear. A document referencing a remote image \
                would otherwise tell that server it had been opened.
                """
            )
        }
    }

    func testEverythingIsDeniedByDefault() {
        XCTAssertTrue(PreviewContentPolicy.policy.hasPrefix("default-src 'none'"))
    }

    /// The reader lazy-loads KaTeX, highlight.js and Mermaid over the custom
    /// scheme after first paint. Without this the document renders unstyled and
    /// diagram-free, which is the silent-breakage mode a CSP is prone to.
    func testLazilyLoadedVendorScriptsAreStillPermitted() {
        XCTAssertTrue(PreviewContentPolicy.policy.contains("script-src 'unsafe-inline' md-asset:"))
    }

    /// Local images resolve against the page's `<base href>` to md-asset: URLs.
    func testLocalImagesAreStillPermitted() {
        XCTAssertTrue(PreviewContentPolicy.policy.contains("img-src md-asset: data:"))
    }

    /// The bundled KaTeX CSS carries its fonts as base64 data: URIs, so no
    /// external font origin is required — but the scheme must be allowed or
    /// every equation renders in a fallback face.
    func testEmbeddedFontsAreStillPermitted() {
        XCTAssertTrue(PreviewContentPolicy.policy.contains("font-src data:"))
    }

    /// The two policies must stay distinct. Quick Look inlines its vendor
    /// bundles and carries images as data:/cid:; this page fetches both over
    /// md-asset:. Merging them would produce the union, which is weaker.
    func testThisPolicyIsNotInterchangeableWithTheQuickLookOne() {
        XCTAssertTrue(PreviewContentPolicy.policy.contains("md-asset:"))
        XCTAssertFalse(
            PreviewContentPolicy.policy.contains("cid:"),
            "cid: belongs to the QLPreviewReply attachment path, not this page."
        )
    }

    func testHTMLWithoutAHeadIsReturnedUnchanged() {
        let headless = "<p>no head here</p>"
        XCTAssertEqual(PreviewContentPolicy.applying(to: headless), headless)
    }

    /// Fails loudly if `MarkdownHTML` stops emitting a `<head>`, since
    /// `applying(to:)` would then silently ship the page unpoliced.
    func testRendererStillEmitsAHeadToInsertInto() {
        XCTAssertNotEqual(PreviewContentPolicy.applying(to: head), head)
    }
}
