import AppKit
import WebKit
import XCTest
@testable import MarkdownHelpers

/// Drops a file and a link on a real `WKWebView` set up like the reader (a
/// string-loaded page with an `mdPreviewHost` handler) and checks that the
/// shipped navigation policy keeps the page in place.
///
/// **Why this exists:** the reader once allowed every navigation that was not
/// a link click. WebKit loads a file or `http(s)` URL dropped on a web view as
/// the new top-level page, so an SVG dragged in from Finder ran its script
/// with the host bridge, outside the app's Content Security Policy. Drags
/// that start in the same page are refused by WebKit, which is why nobody saw
/// it by dragging inside one window.
///
/// The drop is synthetic (an `NSDraggingInfo` with a private pasteboard,
/// delivered through `WKWebView`'s own dragging methods), so the control test
/// proves it still reaches WebKit's load-on-drop; without it, a WebKit change
/// that ignored the fake drop would make the refusal tests pass vacuously.
/// No test here touches the network: an `http(s)` navigation is recorded and
/// then cancelled whatever the policy says.
final class DropNavigationTests: XCTestCase {

    private static let svg = """
    <svg xmlns="http://www.w3.org/2000/svg" width="10" height="10"><script>
    window.webkit.messageHandlers.mdPreviewHost.postMessage('svg-script-ran');
    </script></svg>
    """

    private static let page = """
    <!DOCTYPE html><html><body><article class="markdown-body"><p id="doc">Reader page</p></article></body></html>
    """

    private var scratch: URL!

    override func setUpWithError() throws {
        scratch = FileManager.default.temporaryDirectory
            .appendingPathComponent("drop-navigation-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: scratch)
    }

    // MARK: - Policy

    func testOnlyTheAppsOwnBlankPageMayFillTheMainFrame() {
        let allowed = ["about:blank", "about:blank#section-2", "ABOUT:BLANK"]
        let refused = [
            "file:///Users/someone/Downloads/badge.svg",
            "https://example.com/",
            "http://example.com/",
            "md-asset:///docs/diagram.svg",
            "data:image/svg+xml;base64,PHN2Zy8+",
            "about:srcdoc",
            "about:blankish",
        ]
        for raw in allowed {
            XCTAssertTrue(WebViewNavigationPolicy.allows(url: URL(string: raw), isMainFrame: true), raw)
        }
        for raw in refused {
            XCTAssertFalse(WebViewNavigationPolicy.allows(url: URL(string: raw), isMainFrame: true), raw)
        }
        XCTAssertFalse(WebViewNavigationPolicy.allows(url: nil, isMainFrame: true))
    }

    func testSubframesAreLeftToTheContentSecurityPolicy() {
        XCTAssertTrue(WebViewNavigationPolicy.allows(url: URL(string: "about:srcdoc"), isMainFrame: false))
    }

    // MARK: - Drops in WebKit

    @MainActor
    func testControlWebKitLoadsADroppedFileWhenNothingStopsIt() async throws {
        let file = try writeSVG()
        let run = try await drop(file, policy: .allowEverything)
        XCTAssertEqual(run.messages, ["svg-script-ran"],
                       "The synthetic drop no longer reaches load-on-drop; the refusal tests prove nothing until it does")
        XCTAssertEqual(run.finalURL?.isFileURL, true)
    }

    @MainActor
    func testADroppedSVGFileDoesNotReplaceThePageOrRunItsScript() async throws {
        let file = try writeSVG()
        let run = try await drop(file, policy: .shipped)
        XCTAssertEqual(run.refused.map(\.isFileURL), [true], "The drop should have reached the policy and been refused")
        XCTAssertEqual(run.messages, [])
        XCTAssertEqual(run.finalURL?.absoluteString, "about:blank")
        XCTAssertEqual(run.pageText, "Reader page")
    }

    @MainActor
    func testADroppedLinkIsRefusedWithoutAFetch() async throws {
        let run = try await drop(URL(string: "https://example.invalid/page")!, policy: .shipped)
        XCTAssertEqual(run.refused.map(\.absoluteString), ["https://example.invalid/page"])
        XCTAssertEqual(run.finalURL?.absoluteString, "about:blank")
        XCTAssertEqual(run.pageText, "Reader page")
    }

    @MainActor
    func testTheAppsOwnPageLoadsStillGoThrough() async throws {
        let host = Host(policy: .shipped)
        try await host.load(Self.page)
        let first = try await host.pageText()
        XCTAssertEqual(first, "Reader page")
        try await host.load(Self.page.replacingOccurrences(of: "Reader page", with: "Second document"))
        let second = try await host.pageText()
        XCTAssertEqual(second, "Second document")
        XCTAssertEqual(host.recorder.refused, [])
    }

    // MARK: - Harness

    private func writeSVG() throws -> URL {
        let file = scratch.appendingPathComponent("badge.svg")
        try Data(Self.svg.utf8).write(to: file)
        return file
    }

    private struct Run {
        let messages: [String]
        let refused: [URL]
        let finalURL: URL?
        let pageText: String?
    }

    @MainActor
    private func drop(_ url: URL, policy: Recorder.Policy) async throws -> Run {
        let host = Host(policy: policy)
        try await host.load(Self.page)
        try await host.drop(url)
        if policy == .allowEverything { try await host.waitForMessage() }
        return Run(messages: host.recorder.messages,
                   refused: host.recorder.refused,
                   finalURL: host.webView.url,
                   pageText: try? await host.pageText())
    }

    @MainActor
    private final class Host {
        let recorder: Recorder
        let webView: WKWebView
        private let window: NSWindow

        init(policy: Recorder.Policy) {
            recorder = Recorder(policy: policy)
            let config = WKWebViewConfiguration()
            config.websiteDataStore = .nonPersistent()
            config.userContentController.add(recorder, name: "mdPreviewHost")
            webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 600, height: 400), configuration: config)
            webView.navigationDelegate = recorder
            // Drops are delivered in window coordinates, so the view needs a
            // window; far off screen, as in `WebViewLayoutHarness`.
            window = NSWindow(contentRect: CGRect(x: -30000, y: -30000, width: 600, height: 400),
                              styleMask: [.borderless], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.contentView = webView
            window.orderFront(nil)
        }

        deinit {
            MainActor.assumeIsolated { window.orderOut(nil) }
        }

        func load(_ html: String) async throws {
            webView.loadHTMLString(html, baseURL: nil)
            try await settle()
        }

        func pageText() async throws -> String? {
            try await webView.evaluateJavaScript("document.getElementById('doc')?.textContent ?? null") as? String
        }

        func drop(_ url: URL) async throws {
            let pasteboard = NSPasteboard(name: .init("belvedere-drop-test-\(UUID().uuidString)"))
            defer { pasteboard.releaseGlobally() }
            pasteboard.clearContents()
            pasteboard.writeObjects([url as NSURL])
            let info = SyntheticDrop(pasteboard: pasteboard,
                                     location: NSPoint(x: 300, y: 200),
                                     window: window)
            // Each step is answered by the web content process asynchronously,
            // and the next one reads that answer.
            _ = webView.draggingEntered(info)
            try await Task.sleep(for: .milliseconds(200))
            _ = webView.draggingUpdated(info)
            try await Task.sleep(for: .milliseconds(200))
            _ = webView.prepareForDragOperation(info)
            _ = webView.performDragOperation(info)
            // Wait for the dropped URL to reach the policy, then for any page
            // it loaded to run its script.
            for _ in 0..<60 where !recorder.decided.contains(url) {
                try await Task.sleep(for: .milliseconds(50))
            }
            try await settle()
            // A page the drop loaded may run its script a little later; the
            // control test waits for that message, this grace period covers
            // the refusal tests, which expect none.
            try await Task.sleep(for: .milliseconds(300))
        }

        /// Waits for the page's script to post, up to a deadline.
        func waitForMessage() async throws {
            for _ in 0..<60 where recorder.messages.isEmpty {
                try await Task.sleep(for: .milliseconds(50))
            }
        }

        private func settle() async throws {
            for _ in 0..<500 where webView.isLoading {
                try await Task.sleep(for: .milliseconds(10))
            }
            XCTAssertFalse(webView.isLoading, "The page did not finish loading in 5 seconds")
        }
    }

    @MainActor
    private final class Recorder: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        enum Policy { case shipped, allowEverything }

        let policy: Policy
        var messages: [String] = []
        var decided: [URL] = []
        var refused: [URL] = []

        init(policy: Policy) { self.policy = policy }

        func userContentController(_ userContentController: WKUserContentController,
                                   didReceive message: WKScriptMessage) {
            messages.append("\(message.body)")
        }

        func webView(_ webView: WKWebView,
                     decidePolicyFor navigationAction: WKNavigationAction,
                     decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void) {
            let url = navigationAction.request.url
            if let url { decided.append(url) }
            // The same call the reader, editor and Mermaid popup make.
            let allowed = switch policy {
            case .shipped:
                WebViewNavigationPolicy.allows(url: url,
                                               isMainFrame: navigationAction.targetFrame?.isMainFrame ?? true)
            case .allowEverything:
                true
            }
            if !allowed, let url { refused.append(url) }
            let isRemote = ["http", "https"].contains(url?.scheme?.lowercased() ?? "")
            decisionHandler(allowed && !isRemote ? .allow : .cancel)
        }
    }
}

/// A drop from outside the page: no dragging source, so WebKit does not see it
/// as a drag that started in the same page.
@MainActor
private final class SyntheticDrop: NSObject, @MainActor NSDraggingInfo {
    let draggingPasteboard: NSPasteboard
    let draggingLocation: NSPoint
    let draggingDestinationWindow: NSWindow?

    init(pasteboard: NSPasteboard, location: NSPoint, window: NSWindow) {
        draggingPasteboard = pasteboard
        draggingLocation = location
        draggingDestinationWindow = window
    }

    var draggingSourceOperationMask: NSDragOperation { [.copy, .link, .generic] }
    var draggedImageLocation: NSPoint { draggingLocation }
    var draggedImage: NSImage? { nil }
    var draggingSource: Any? { nil }
    var draggingSequenceNumber: Int { 1 }
    var draggingFormation: NSDraggingFormation = .default
    var animatesToDestination = false
    var numberOfValidItemsForDrop = 1
    var springLoadingHighlight: NSSpringLoadingHighlight { .none }

    func slideDraggedImage(to screenPoint: NSPoint) {}
    override func namesOfPromisedFilesDropped(atDestination dropDestination: URL) -> [String]? { nil }
    func enumerateDraggingItems(options enumOpts: NSDraggingItemEnumerationOptions = [],
                                for view: NSView?,
                                classes classArray: [AnyClass],
                                searchOptions: [NSPasteboard.ReadingOptionKey: Any] = [:],
                                using block: (NSDraggingItem, Int, UnsafeMutablePointer<ObjCBool>) -> Void) {}
    func resetSpringLoading() {}
}
