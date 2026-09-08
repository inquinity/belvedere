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
    private func harness(withHostBridge: Bool = true) async throws -> WKWebView {
        let purify = try TestVendor.script("md-preview/Vendor/DOMPurify/purify.min.js")
        let morphdom = try TestVendor.script("md-preview/Vendor/Morphdom/morphdom.min.js")
        let html = """
        <!DOCTYPE html>
        <html><head>
        <script>\(purify)</script>
        <script>\(morphdom)</script>
        <script>
        \(withHostBridge
          ? """
            window.webkit = { messageHandlers: { mdPreviewHost: { postMessage(m) {
                (window.__posted = window.__posted || []).push(m);
            } } } };
            """
          : "window.webkit = { messageHandlers: {} };")
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

    /// The local reference points *outside* the document folder on purpose:
    /// that is what containment refuses, and so the only case with a remedy.
    /// An inside-folder failure is broken rather than blocked and is covered
    /// by `testInsideFolderFailuresAreNotOfferedALoadButton`.
    private let doc = """
    # Doc

    ![local](../elsewhere/missing-on-purpose.png)

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
        XCTAssertTrue(state.contains("load failed: not an image"),
                      """
                      A refusal must read as the outcome of the action the \
                      reader just took, not as a bare property of the file. \
                      \(state)
                      """)
        XCTAssertTrue(state.contains("\"stillOffersLoad\":false"),
                      "a refused asset must stop offering an action that will fail again \(state)")
    }

    /// A file inside the document's own folder was never blocked, so a
    /// failure there means broken rather than withheld — and offering Load
    /// would be offering to retry the thing that just failed.
    @MainActor
    func testInsideFolderFailuresAreNotOfferedALoadButton() async throws {
        let webView = try await harness()
        try await update("""
        # Doc

        ![inside](images/missing.png)

        ![outside](../elsewhere/logo.png)
        """, in: webView)
        _ = try await waitForPlaceholders(webView, atLeast: 2)

        let raw = try await webView.evaluateJavaScript("""
        JSON.stringify({
          broken: document.querySelectorAll('[data-mdp-broken]').length,
          brokenButtons: document.querySelectorAll('[data-mdp-broken] .mdp-deferred-load').length,
          outsideButtons: document.querySelectorAll(
              '[data-mdp-deferred]:not([data-mdp-broken]):not([data-mdp-remote]) .mdp-deferred-load'
          ).length,
          brokenText: (document.querySelector('[data-mdp-broken]') || {}).textContent || ''
        })
        """) as? String ?? "{}"

        XCTAssertTrue(raw.contains("\"broken\":1"),
                      "a reference inside the document folder must be marked broken, not blocked \(raw)")
        XCTAssertTrue(raw.contains("\"brokenButtons\":0"),
                      """
                      A file inside the document folder was offered Load. \
                      Resolution is already permitted there, so the button \
                      can only retry what already failed. \(raw)
                      """)
        XCTAssertTrue(raw.contains("\"outsideButtons\":1"),
                      "an out-of-folder reference is the one with a remedy \(raw)")
        XCTAssertTrue(raw.contains("load failed"),
                      """
                      The label must read as a failed load, and must not claim \
                      the file is missing — nothing checked. It could equally \
                      be unreadable or a format WebKit does not render. \(raw)
                      """)
    }

    /// Loads the **whole page** and lets it start itself, rather than driving
    /// `MdPreview.update`.
    ///
    /// This is the path that opening a document takes, and it is the one that
    /// shipped broken: `start()` was never hooked, so the feature did nothing
    /// in the app while every update-driven test passed. Every other test here
    /// calls `update` directly and would have stayed green.
    @MainActor
    func testInitialPageRenderDefersOnItsOwn() async throws {
        let base = MarkdownAssetResolution.baseHref(
            forFolder: URL(fileURLWithPath: "/docs/notes", isDirectory: true)
        )
        let pageHTML = MarkdownHTML.render(
            markdown: """
            # Doc

            ![inside](images/missing.png)

            ![outside](../elsewhere/logo.png)
            """,
            assetBaseHref: base,
            vendorLoading: .inline
        ).html

        // MarkdownHTML reads vendor bundles from Bundle.main, which in an SPM
        // test has none — so the page's `sanitize()` would fail closed and
        // render nothing, and this test would pass vacuously against an empty
        // article. Supply DOMPurify from the repo instead.
        let purify = try TestVendor.script("md-preview/Vendor/DOMPurify/purify.min.js")
        let page = pageHTML.replacingOccurrences(
            of: "<head>", with: "<head><script>\(purify)</script>", options: [], range: pageHTML.range(of: "<head>")
        )

        let webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 900, height: 600))
        // A host bridge, so grants are on offer — this is the app-window shape.
        let config = WKUserScript(
            source: """
            window.webkit = { messageHandlers: { mdPreviewHost: { postMessage(m) {
                (window.__posted = window.__posted || []).push(m);
            } } } };
            """,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: true
        )
        webView.configuration.userContentController.addUserScript(config)
        webView.loadHTMLString(page, baseURL: nil)
        while webView.isLoading { try await Task.sleep(for: .milliseconds(10)) }

        let found = try await waitForPlaceholders(webView, atLeast: 2)
        XCTAssertGreaterThanOrEqual(
            found, 2,
            """
            The initial render did not defer. Nothing here called \
            MdPreview.update — this is the path that opening a document takes, \
            and the one that shipped doing nothing at all.
            """
        )
    }

    /// The document-level offer. It exists because a reader thinks in
    /// documents rather than folders, so it must count what it can actually
    /// act on — not remote references, which have no remedy.
    @MainActor
    func testLoadAllOffersAndRequestsOnlyTheLoadableOnes() async throws {
        let webView = try await harness()
        try await update("""
        # Doc

        ![a](../elsewhere/one.png)

        ![b](../elsewhere/two.png)

        ![c](https://example.invalid/pixel.png)
        """, in: webView)
        _ = try await waitForPlaceholders(webView, atLeast: 3)

        let before = try await webView.evaluateJavaScript("""
        (() => {
          const b = document.querySelector('.mdp-deferred-banner');
          return JSON.stringify({ shown: !!b, text: b ? b.textContent : '' });
        })()
        """) as? String ?? "{}"
        XCTAssertTrue(before.contains("\"shown\":true"), "two loadable images should raise the banner \(before)")
        XCTAssertTrue(before.contains("2 images blocked"),
                      "the count must exclude the remote one, which has no remedy \(before)")

        _ = try await webView.evaluateJavaScript(
            "document.querySelector('.mdp-deferred-banner button').click(); true"
        )
        let posted = try await webView.evaluateJavaScript("""
        JSON.stringify((window.__posted || [])
          .filter((m) => m.kind === 'loadDeferredAsset')
          .map((m) => m.src))
        """) as? String ?? "[]"
        XCTAssertTrue(posted.contains("one.png") && posted.contains("two.png"),
                      "Load all must request every loadable image \(posted)")
        XCTAssertFalse(posted.contains("example.invalid"),
                       """
                       Load all requested a remote image. Fetching one would \
                       disclose the reader to the document's author, which is \
                       what the CSP prevents. \(posted)
                       """)
    }

    /// Grants are per document, per session. A reader who loaded something
    /// once has not consented to it loading forever, and F4 deliberately
    /// remembers nothing — durable grants are F3.
    @MainActor
    func testGrantsDoNotPersistIntoAFreshRender() async throws {
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
            "window.MdPreview.resolveDeferredAsset('\(token)', 'data:image/png;base64,iVBORw0KGgo=', null); true"
        )

        // Reopening the document is a fresh page, not a fresh update.
        let reopened = try await harness()
        try await update(doc, in: reopened)
        let again = try await waitForPlaceholders(reopened)
        XCTAssertGreaterThan(
            again, 0,
            """
            A previously granted image loaded on its own in a new page. The \
            grant must not outlive the document — that is what makes it a \
            per-asset decision rather than a standing permission.
            """
        )
    }

    /// Quick Look registers no `mdPreviewHost` handler, so nothing can answer
    /// a request. Offering Load there produced a button that spun on
    /// "Loading…" forever — and it appeared on *every* failed image, because
    /// the Quick Look page loads with a nil base URL, so the in/out-of-folder
    /// check has no folder to compare against and calls everything external.
    @MainActor
    func testQuickLookGetsLabelsButNoGrants() async throws {
        let webView = try await harness(withHostBridge: false)
        try await update(doc, in: webView)
        _ = try await waitForPlaceholders(webView, atLeast: 2)

        let raw = try await webView.evaluateJavaScript("""
        JSON.stringify({
          placeholders: document.querySelectorAll('[data-mdp-deferred]').length,
          buttons: document.querySelectorAll('.mdp-deferred-load').length,
          banners: document.querySelectorAll('.mdp-deferred-banner').length,
          text: [...document.querySelectorAll('.mdp-deferred-label')].map(e => e.textContent).join(' | ')
        })
        """) as? String ?? "{}"

        XCTAssertTrue(raw.contains("\"buttons\":0"),
                      """
                      Quick Look offered a Load button. There is no host to \
                      answer it, so it can only spin forever — and Quick Look \
                      is reached by pressing space on a file the reader did \
                      not choose, so it offers no grants by design. \(raw)
                      """)
        XCTAssertTrue(raw.contains("\"banners\":0"),
                      "\"Load all\" needs a host too \(raw)")
        XCTAssertGreaterThan(
            (try? JSONSerialization.jsonObject(with: Data(raw.utf8)) as? [String: Any])
                .flatMap { $0?["placeholders"] as? Int } ?? 0, 0,
            "a label is information rather than an affordance, and should still appear \(raw)"
        )
        XCTAssertFalse(
            raw.contains("could not be displayed"),
            """
            Quick Look must not claim a boundary decision it cannot make: with \
            a nil base URL there is no document folder to compare against. \(raw)
            """
        )
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
