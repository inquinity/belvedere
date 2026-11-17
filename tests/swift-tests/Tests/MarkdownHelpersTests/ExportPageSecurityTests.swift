import AppKit
import WebKit
import XCTest
@testable import MarkdownHelpers

/// Export and printing work from a hidden copy of the reader's page. That copy
/// is a second web view, so the reader's protections have to hold there too:
/// the content policy, no navigation after its own load, and images the reader
/// chose to load still showing. The folder boundary for `md-asset:` images is
/// set by the app's `captureExportSession`, which this package does not
/// compile; `ForkPostureTests` pins that call instead.
@MainActor
final class ExportPageSecurityTests: XCTestCase {
    /// A 1x1 PNG, the form a granted image takes in the page (`data:`).
    private let grantedImage =
        "data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg=="

    func testExportPageAllowsOnlyItsOwnFirstLoad() {
        var loaded = false
        XCTAssertFalse(DocumentExportSession.allowsExportPageNavigation(
            isMainFrame: false, hasAllowedInitialLoad: &loaded), "a frame never loads")
        XCTAssertTrue(DocumentExportSession.allowsExportPageNavigation(
            isMainFrame: true, hasAllowedInitialLoad: &loaded), "the page's own load")
        XCTAssertFalse(DocumentExportSession.allowsExportPageNavigation(
            isMainFrame: true, hasAllowedInitialLoad: &loaded), "nothing after it")
    }

    /// The copy carries the policy that refuses remote content, a remote image
    /// stays unloaded, and an image the reader granted still shows.
    func testExportCopyKeepsThePolicyAndGrantedImages() async throws {
        let html = """
            <!DOCTYPE html><html><head>\(PreviewContentPolicy.metaTag)</head><body>
            <article class="markdown-body">
            <p>Before</p>
            <img id="granted" src="\(grantedImage)" alt="granted">
            <img id="remote" src="https://example.invalid/tracker.png" alt="remote">
            <p>After</p>
            </article></body></html>
            """
        _ = NSApplication.shared
        let harness = WebViewLayoutHarness(html: html, width: 800, isEditor: false, height: 600)
        defer { harness.close() }
        try await waitForLoad(harness.webView)

        let session = try await DocumentExportSession.capture(from: harness.webView)
        defer { session.close() }
        let page = try await session.webView(for: .pdf)
        let state = try await page.callAsyncJavaScript("""
            const images = Array.from(document.images);
            await Promise.allSettled(images.map(image => image.decode()));
            const policies = Array.from(document.querySelectorAll(
                'meta[http-equiv="Content-Security-Policy"]')).map(meta => meta.content);
            const width = id => document.getElementById(id)?.naturalWidth ?? -1;
            return { policies, granted: width('granted'), remote: width('remote'),
                     href: location.href };
            """, contentWorld: .page) as? [String: Any]
        let result = try XCTUnwrap(state)

        let policies = try XCTUnwrap(result["policies"] as? [String])
        XCTAssertFalse(policies.isEmpty, "the export copy has no content policy")
        for policy in policies {
            XCTAssertEqual(policy, PreviewContentPolicy.policy)
        }
        XCTAssertEqual(result["granted"] as? Int, 1, "a granted image is missing from the export")
        XCTAssertEqual(result["remote"] as? Int, 0, "a remote image loaded in the export")
        XCTAssertEqual(result["href"] as? String, "about:blank")
    }

    /// Something in the copy that tries to navigate away goes nowhere. The
    /// target is `about:blank`, which the app's general navigation policy
    /// allows and which would load instantly, so only the export page's own
    /// first-load rule keeps the document in place.
    func testExportCopyCannotNavigate() async throws {
        let html = """
            <!DOCTYPE html><html><head>\(PreviewContentPolicy.metaTag)</head><body>
            <article class="markdown-body"><p>Document</p></article></body></html>
            """
        _ = NSApplication.shared
        let harness = WebViewLayoutHarness(html: html, width: 800, isEditor: false, height: 600)
        defer { harness.close() }
        try await waitForLoad(harness.webView)

        let session = try await DocumentExportSession.capture(from: harness.webView)
        defer { session.close() }
        let page = try await session.webView(for: .pdf)
        _ = try await page.evaluateJavaScript("location.href = 'about:blank'; 0")
        try await Task.sleep(for: .milliseconds(300))
        let text = try await page.evaluateJavaScript("document.body.innerText") as? String
        XCTAssertTrue(text?.contains("Document") == true, "the export copy navigated away")
    }

    private func waitForLoad(_ webView: WKWebView) async throws {
        let deadline = Date().addingTimeInterval(10)
        while webView.isLoading && Date() < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertFalse(webView.isLoading)
    }
}
