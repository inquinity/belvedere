import Foundation
import WebKit
import XCTest
@testable import MarkdownHelpers

/// Drives the shipped page script in a real WKWebView and asserts that a
/// blocked image actually becomes a placeholder.
///
/// **Why this exists:** the first cut of F4 shipped with the hook on the wrong
/// tree — it ran against morphdom's detached `next` element, where images never
/// load and no `error` event ever fires — and on a path that document opening
/// does not take. Every existing test still passed, because they only asserted
/// that dangerous things were *absent*. Nothing asserted the feature was
/// *present*, so zero placeholders read as success.
final class DeferredImageRenderingTests: XCTestCase {

    @MainActor
    private func harness() async throws -> WKWebView {
        let purify = try TestVendor.script("md-preview/Vendor/DOMPurify/purify.min.js")
        let morphdom = try TestVendor.script("md-preview/Vendor/Morphdom/morphdom.min.js")
        let html = """
        <!DOCTYPE html>
        <html><head>
        <script>\(purify)</script>
        <script>\(morphdom)</script>
        <script>
        window.webkit = { messageHandlers: { mdPreviewHost: { postMessage(m) {
            (window.__posted = window.__posted || []).push(m);
        } } } };
        </script>
        \(MarkdownHTML.hostBridgeScript)
        </head><body><article class="markdown-body"></article></body></html>
        """
        let webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 900, height: 600))
        webView.loadHTMLString(html, baseURL: TestVendor.repositoryRoot)
        while webView.isLoading { try await Task.sleep(for: .milliseconds(10)) }
        return webView
    }

    @MainActor
    private func update(_ markdown: String, in webView: WKWebView) async throws {
        let article = MarkdownHTML.render(markdown: markdown, vendorLoading: .lazy).articleHTML
        let data = try JSONSerialization.data(withJSONObject: [article], options: [])
        let literal = String(String(data: data, encoding: .utf8)!.dropFirst().dropLast())
        _ = try await webView.evaluateJavaScript("window.MdPreview.update(\(literal)); true")
    }

    /// Image loads fail asynchronously, so poll rather than sleeping a guess.
    @MainActor
    private func waitForPlaceholders(_ webView: WKWebView,
                                     atLeast wanted: Int = 1) async throws -> Int {
        // Image loads fail asynchronously and at different speeds — a local
        // path fails at once, a remote host waits on DNS — so wait for the
        // count we expect rather than for the first one to arrive.
        var last = 0
        for _ in 0..<120 {
            last = try await webView.evaluateJavaScript(
                "document.querySelectorAll('.markdown-body [data-mdp-deferred]').length"
            ) as? Int ?? 0
            if last >= wanted { return last }
            try await Task.sleep(for: .milliseconds(50))
        }
        return last
    }

    private let doc = """
    # Doc

    ![local](images/missing-on-purpose.png)

    ![remote](https://example.invalid/pixel.png)
    """

    @MainActor
    func testBlockedImagesBecomePlaceholders() async throws {
        let webView = try await harness()
        try await update(doc, in: webView)

        let found = try await waitForPlaceholders(webView)
        XCTAssertGreaterThan(
            found, 0,
            """
            A blocked image did not become a placeholder, so the reader gets a \
            broken-image icon with no explanation and no remedy — which is the \
            whole point of F4.
            """
        )
    }

    /// The local one offers a Load button; the remote one must not.
    @MainActor
    func testOnlyLocalPlaceholdersOfferLoad() async throws {
        let webView = try await harness()
        try await update(doc, in: webView)
        _ = try await waitForPlaceholders(webView, atLeast: 2)

        let raw = try await webView.evaluateJavaScript("""
        JSON.stringify({
          total: document.querySelectorAll('[data-mdp-deferred]').length,
          remote: document.querySelectorAll('[data-mdp-remote]').length,
          remoteButtons: document.querySelectorAll('[data-mdp-remote] .mdp-deferred-load').length,
          localButtons: document.querySelectorAll('[data-mdp-deferred]:not([data-mdp-remote]) .mdp-deferred-load').length
        })
        """) as? String ?? "{}"
        let d = try JSONSerialization.jsonObject(with: Data(raw.utf8)) as? [String: Int] ?? [:]

        XCTAssertEqual(d["remote"], 1, "the remote image should be deferred and labelled \(raw)")
        XCTAssertEqual(d["remoteButtons"], 0,
                       "a remote placeholder offered Load, which could only ever fail \(raw)")
        XCTAssertEqual(d["localButtons"], 1,
                       "the local placeholder must offer Load — that is the remedy \(raw)")
    }

    /// The whole round trip: click Load, the page asks the host, the host
    /// answers, the image appears. UI automation cannot do this without
    /// Accessibility permission, so it is driven here instead.
    @MainActor
    func testClickingLoadAsksTheHostAndSwapsTheImageIn() async throws {
        let webView = try await harness()
        try await update(doc, in: webView)
        _ = try await waitForPlaceholders(webView)

        // Click the local placeholder's button the way a reader would.
        _ = try await webView.evaluateJavaScript("""
        document.querySelector('[data-mdp-deferred]:not([data-mdp-remote]) .mdp-deferred-load').click(); true
        """)

        let posted = try await webView.evaluateJavaScript("""
        JSON.stringify((window.__posted || []).filter((m) => m.kind === 'loadDeferredAsset'))
        """) as? String ?? "[]"
        let messages = try JSONSerialization.jsonObject(with: Data(posted.utf8)) as? [[String: Any]] ?? []
        XCTAssertEqual(messages.count, 1, "clicking Load must ask the host exactly once \(posted)")
        let token = try XCTUnwrap(messages.first?["token"] as? String)
        // Must be the resolved URL, not the raw attribute. Shipping
        // getAttribute('src') sent the host "images/missing-on-purpose.png",
        // which it cannot act on, so every Load answered "unavailable".
        let requested = messages.first?["src"] as? String ?? ""
        XCTAssertTrue(requested.contains("missing-on-purpose.png"),
                      "the request must name the blocked asset \(posted)")
        XCTAssertFalse(
            requested.hasPrefix("images/") || requested.hasPrefix("../"),
            """
            The host was sent a relative path. It resolves nothing, so the \
            click can only ever come back unavailable. Send img.src. \(posted)
            """
        )

        // The host answers with a data: URL, as DeferredAssetLoader would.
        let pixel = "data:image/png;base64,iVBORw0KGgo="
        _ = try await webView.evaluateJavaScript(
            "window.MdPreview.resolveDeferredAsset('\(token)', '\(pixel)', null); true"
        )
        let swapped = try await webView.evaluateJavaScript("""
        (() => {
          const img = document.querySelector('.markdown-body img[src^="data:image/png"]');
          const left = document.querySelectorAll('[data-mdp-deferred]:not([data-mdp-remote])').length;
          return JSON.stringify({ swapped: !!img, placeholdersLeft: left });
        })()
        """) as? String ?? "{}"
        XCTAssertTrue(swapped.contains("\"swapped\":true"),
                      "the granted image did not replace its placeholder \(swapped)")
        XCTAssertTrue(swapped.contains("\"placeholdersLeft\":0"),
                      "the placeholder should be gone once the image loads \(swapped)")
    }

    /// A refusal has to be visible, not silent — that is the whole reason the
    /// placeholder exists rather than a broken icon.
    @MainActor
    func testRefusalIsShownOnThePlaceholder() async throws {
        let webView = try await harness()
        try await update(doc, in: webView)
        _ = try await waitForPlaceholders(webView)

        _ = try await webView.evaluateJavaScript("""
        document.querySelector('[data-mdp-deferred]:not([data-mdp-remote]) .mdp-deferred-load').click(); true
        """)
        let token = try await webView.evaluateJavaScript("""
        (window.__posted || []).filter((m) => m.kind === 'loadDeferredAsset').pop().token
        """) as? String ?? ""
        _ = try await webView.evaluateJavaScript(
            "window.MdPreview.resolveDeferredAsset('\(token)', null, 'notAnImage'); true"
        )

        let state = try await webView.evaluateJavaScript("""
        (() => {
          const box = document.querySelector('[data-mdp-deferred]:not([data-mdp-remote])');
          return JSON.stringify({
            text: box ? box.textContent : '',
            stillOffersLoad: !!(box && box.querySelector('.mdp-deferred-load'))
          });
        })()
        """) as? String ?? "{}"
        XCTAssertTrue(state.contains("not an image"),
                      "a refusal must say why, in place \(state)")
        XCTAssertTrue(state.contains("\"stillOffersLoad\":false"),
                      "a refused asset must stop offering an action that will fail again \(state)")
    }

    /// The morph path is the one that was broken: the hook ran on the detached
    /// tree. A second update goes through morphdom rather than innerHTML.
    @MainActor
    func testPlaceholdersSurviveTheMorphUpdatePath() async throws {
        let webView = try await harness()
        try await update(doc, in: webView)
        _ = try await waitForPlaceholders(webView)

        // Prove the second update really went through morphdom rather than
        // innerHTML — otherwise this test passes without exercising the path
        // that shipped broken.
        let morphed = try await webView.evaluateJavaScript("""
        (() => {
          const a = document.querySelector('.markdown-body');
          return !!(a && a.firstElementChild && typeof morphdom === 'function');
        })()
        """) as? Bool ?? false
        XCTAssertTrue(morphed, "second update did not qualify for the morph path")

        try await update(doc + "\n\nMore text.\n", in: webView)
        let afterMorph = try await waitForPlaceholders(webView, atLeast: 2)
        XCTAssertGreaterThan(
            afterMorph, 0,
            """
            Placeholders vanished after a second update. The morphdom path \
            rebuilds the nodes, so deferral has to run on the live tree after \
            the diff — running it on the detached `next` is what shipped broken.
            """
        )
    }
}
