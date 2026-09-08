import XCTest
import WebKit
@testable import MarkdownHelpers

/// Negative tests: things that must **not** work.
///
/// These drive the shipped pipeline — bundled DOMPurify plus
/// `MarkdownHTML.hostBridgeScript` — in a real WKWebView, feed it the
/// adversarial fixtures in `tests/fixtures/security/`, and assert the dangerous
/// markup is gone from the rendered DOM.
///
/// The Swift layer is deliberately not the sanitizer: CommonMark passes raw
/// HTML through and `EscapingHTMLFormatter` honours that. DOMPurify is the only
/// control, which is exactly why it deserves end-to-end coverage rather than
/// string assertions over the emitted page.
final class SanitizerNegativeTests: XCTestCase {

    // MARK: - Inline HTML

    @MainActor
    func testInlineHTMLAttacksDoNotSurviveSanitization() async throws {
        let webView = try await loadHarness()
        try await render(fixture: "inline-html.md", in: webView)

        let survivors = try await survivors(in: webView)

        XCTAssertGreaterThan(
            survivors.headings, 0,
            """
            The fixture did not render at all, so every assertion below would \
            pass vacuously. Fix the harness before trusting this test. \
            \(survivors.raw)
            """
        )
        XCTAssertFalse(survivors.scriptExecuted,
                       "A script from document content executed. \(survivors.raw)")
        XCTAssertEqual(survivors.scripts, 0, survivors.raw)
        XCTAssertEqual(survivors.iframes, 0, survivors.raw)
        XCTAssertEqual(survivors.objects, 0, survivors.raw)
        XCTAssertEqual(survivors.embeds, 0, survivors.raw)
        XCTAssertEqual(survivors.forms, 0,
                       "A form survived: a document could present a credential prompt. \(survivors.raw)")
        XCTAssertEqual(
            survivors.formControls, 0,
            """
            A form control survived, so a document can draw a credential prompt \
            with no <form> around it. DOMPurify's KEEP_CONTENT default unwraps \
            the forbidden form and reparents its children, which is why \
            counting <form> alone is not enough. \(survivors.raw)
            """
        )
        XCTAssertGreaterThan(
            survivors.taskCheckboxes, 0,
            """
            Task-list checkboxes disappeared. The input rule admits exactly the \
            checkbox EscapingHTMLFormatter emits and drops every other input -- \
            this says it dropped the legitimate one too. \(survivors.raw)
            """
        )
        XCTAssertEqual(survivors.bases, 0,
                       "A <base> survived: it would re-point every relative URL on the page. \(survivors.raw)")
        XCTAssertEqual(survivors.metas, 0,
                       "A <meta> survived: http-equiv refresh would redirect the preview. \(survivors.raw)")
        XCTAssertEqual(survivors.links, 0, survivors.raw)
        XCTAssertEqual(survivors.styleTags, 0, survivors.raw)
        XCTAssertEqual(survivors.eventHandlerAttributes, 0,
                       "An inline event handler survived. \(survivors.raw)")
        XCTAssertEqual(survivors.scriptedHrefs, 0,
                       "A javascript: URL survived. \(survivors.raw)")
    }

    /// `style` is stripped specifically so a hidden segment cannot ride along in
    /// `textContent` when the reader uses the code-block copy button — the
    /// clipboard would carry markup the reader never saw.
    @MainActor
    func testStyleAttributesAreStrippedSoCopiedTextMatchesWhatIsVisible() async throws {
        let webView = try await loadHarness()
        try await render(fixture: "inline-html.md", in: webView)

        let survivors = try await survivors(in: webView)
        XCTAssertEqual(survivors.styleAttributes, 0, survivors.raw)
    }

    /// Fail-closed behaviour: without DOMPurify the bootstrap must render
    /// nothing rather than fall back to raw `innerHTML`.
    @MainActor
    func testRenderingRefusesToProceedWithoutTheSanitizer() async throws {
        let webView = try await loadHarness(includesSanitizer: false)
        try await render(fixture: "inline-html.md", in: webView)

        let survivors = try await survivors(in: webView)
        XCTAssertEqual(
            survivors.headings, 0,
            """
            Content rendered with no sanitizer present. sanitize() must fail \
            closed and return an empty string, not fall back to raw innerHTML. \
            \(survivors.raw)
            """
        )
        XCTAssertFalse(survivors.scriptExecuted,
                       "Content rendered unsanitized when DOMPurify was absent. \(survivors.raw)")
        XCTAssertEqual(survivors.scripts, 0, survivors.raw)
        XCTAssertEqual(survivors.iframes, 0, survivors.raw)
    }

    // MARK: - Remote content

    /// Remote `<img>` elements survive sanitization: `ALLOWED_URI_REGEXP`
    /// permits `http`/`https`, so DOMPurify keeps them in the DOM.
    ///
    /// That is no longer a disclosure risk, because nothing fetches them —
    /// `PreviewContentPolicy` omits both schemes from `img-src`, so the load is
    /// refused by the page. The element is present and broken rather than
    /// absent, which is why this test still passes and still matters: it pins
    /// the sanitizer's behaviour, so if the CSP were ever dropped the exposure
    /// would return silently.
    ///
    /// Tightening `ALLOWED_URI_REGEXP` to drop `http`/`https` is the belt to
    /// this braces, and is on the upstream contribution track.
    @MainActor
    func testRemoteImagesSurviveSanitizationAndAreStoppedByThePolicyInstead() async throws {
        let webView = try await loadHarness()
        try await render(fixture: "remote-beacon.md", in: webView)

        let survivors = try await survivors(in: webView)
        XCTAssertGreaterThan(survivors.headings, 0, "fixture did not render \(survivors.raw)")
        XCTAssertGreaterThan(
            survivors.remoteImages + survivors.deferredRemote, 0,
            """
            Remote references no longer survive sanitization. That is an \
            improvement, not a failure — it means ALLOWED_URI_REGEXP was \
            tightened, so this assertion should be inverted and the CSP left \
            as defence in depth. Note the count includes deferred placeholders: \
            F4 replaces a remote image that failed to load with one naming it, \
            so the raw <img> count alone stopped being a proxy for what the \
            sanitizer kept. \(survivors.raw)
            """
        )
        XCTAssertEqual(
            survivors.deferredLoadButtons, 0,
            """
            A remote placeholder offered a Load button. Fetching remote content \
            would send the reader's IP to the document's author, which is the \
            disclosure the CSP exists to prevent, and the host refuses it — so \
            the button could only ever fail. \(survivors.raw)
            """
        )
        // Whatever else changes, a remote stylesheet must never survive.
        XCTAssertEqual(survivors.links, 0, survivors.raw)
    }

    // MARK: - Harness

    @MainActor
    private func loadHarness(includesSanitizer: Bool = true) async throws -> WKWebView {
        let purify = includesSanitizer
            ? try "<script>\(TestVendor.script("md-preview/Vendor/DOMPurify/purify.min.js"))</script>"
            : ""
        let morphdom = try TestVendor.script("md-preview/Vendor/Morphdom/morphdom.min.js")

        let html = """
        <!DOCTYPE html>
        <html><head>
        <meta name="viewport" content="width=device-width, initial-scale=1.0">
        \(purify)
        <script>\(morphdom)</script>
        <script>
        window.webkit = { messageHandlers: { mdPreviewHost: { postMessage() {} } } };
        </script>
        \(MarkdownHTML.hostBridgeScript)
        </head><body>
        <article class="markdown-body"></article>
        </body></html>
        """

        let webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 900, height: 600))
        webView.loadHTMLString(html, baseURL: TestVendor.repositoryRoot)
        while webView.isLoading {
            try await Task.sleep(for: .milliseconds(10))
        }
        return webView
    }

    @MainActor
    private func render(fixture name: String, in webView: WKWebView) async throws {
        let url = TestVendor.repositoryRoot
            .appendingPathComponent("tests/fixtures/security")
            .appendingPathComponent(name)
        let markdown = try String(contentsOf: url, encoding: .utf8)
        let article = MarkdownHTML.render(markdown: markdown, vendorLoading: .lazy).articleHTML

        let literal = try jsStringLiteral(article)
        _ = try await webView.evaluateJavaScript("window.MdPreview.update(\(literal)); true")
        // Give any surviving script a turn on the run loop before we look.
        try await Task.sleep(for: .milliseconds(50))
    }

    private func jsStringLiteral(_ value: String) throws -> String {
        let data = try JSONSerialization.data(withJSONObject: [value], options: [])
        let array = try XCTUnwrap(String(data: data, encoding: .utf8))
        return String(array.dropFirst().dropLast())
    }

    @MainActor
    private func survivors(in webView: WKWebView) async throws -> Survivors {
        let result = try await webView.evaluateJavaScript("""
        (() => {
            const a = document.querySelector('.markdown-body');
            const handlerAttrs = ['onerror', 'onclick', 'onload', 'onmouseover', 'onfocus'];
            const withHandler = [...a.querySelectorAll('*')].filter(
                (el) => handlerAttrs.some((h) => el.hasAttribute(h))
            ).length;
            const scripted = [...a.querySelectorAll('a[href]')].filter(
                (el) => el.getAttribute('href').trim().toLowerCase().startsWith('javascript:')
            ).length;
            const remoteImages = [...a.querySelectorAll('img[src]')].filter(
                (el) => /^https?:/i.test(el.getAttribute('src'))
            ).length;
            return JSON.stringify({
                headings: a.querySelectorAll('h1, h2').length,
                scripts: a.querySelectorAll('script').length,
                iframes: a.querySelectorAll('iframe').length,
                objects: a.querySelectorAll('object').length,
                embeds: a.querySelectorAll('embed').length,
                forms: a.querySelectorAll('form').length,
                // Our own affordances are excluded by class. That is not a
                // loophole: `button` is in FORBID_TAGS, so document content
                // cannot produce one at all, and any button present is markup
                // this app injected after sanitising (F4's deferred-image
                // placeholder).
                // `button` is not counted: the app emits its own (the Mermaid
                // HUD, the code-copy control), so a surviving button is not
                // evidence of anything. What matters is whether a document can
                // put something on the page that invites typing.
                formControls: a.querySelectorAll(
                    'select, textarea, label, fieldset, legend, output, datalist, option'
                ).length
                + [...a.querySelectorAll('input')].filter(
                    (el) => (el.getAttribute('type') || '').toLowerCase() !== 'checkbox'
                ).length,
                taskCheckboxes: a.querySelectorAll('input[type=checkbox]').length,
                bases: a.querySelectorAll('base').length,
                metas: a.querySelectorAll('meta').length,
                links: a.querySelectorAll('link').length,
                styleTags: a.querySelectorAll('style').length,
                styleAttributes: a.querySelectorAll('[style]').length,
                eventHandlerAttributes: withHandler,
                scriptedHrefs: scripted,
                remoteImages: remoteImages,
                deferredRemote: a.querySelectorAll('[data-mdp-remote]').length,
                deferredLoadButtons: a.querySelectorAll('.mdp-deferred-remote .mdp-deferred-load').length,
                scriptExecuted: window.__pwned === true
            });
        })()
        """)
        let json = try XCTUnwrap(result as? String)
        var survivors = try JSONDecoder().decode(Survivors.self, from: Data(json.utf8))
        survivors.raw = json
        return survivors
    }

    private struct Survivors: Decodable {
        var headings = 0
        var scripts = 0
        var iframes = 0
        var objects = 0
        var embeds = 0
        var forms = 0
        var formControls = 0
        var taskCheckboxes = 0
        var bases = 0
        var metas = 0
        var links = 0
        var styleTags = 0
        var styleAttributes = 0
        var eventHandlerAttributes = 0
        var scriptedHrefs = 0
        var remoteImages = 0
        var deferredRemote = 0
        var deferredLoadButtons = 0
        var scriptExecuted = false
        var raw = ""

        private enum CodingKeys: String, CodingKey {
            case headings, scripts, iframes, objects, embeds, forms, bases, metas, links
            case formControls, taskCheckboxes
            case styleTags, styleAttributes, eventHandlerAttributes, scriptedHrefs
            case remoteImages, scriptExecuted, deferredRemote, deferredLoadButtons
        }
    }
}

/// The app's own Mermaid controls must survive sanitisation.
///
/// `MarkdownHTML+Mermaid` emits the five HUD buttons as part of the article
/// HTML, so they pass through DOMPurify like any other markup. Adding `button`
/// to `FORBID_TAGS` removed all five, and that shipped in 1.0.4 and 1.0.5
/// because every sanitiser test asserted what must be *absent* and none
/// asserted what must remain.
final class SanitizerKeepsAppControlsTests: XCTestCase {

    @MainActor
    func testMermaidHUDButtonsSurviveSanitisation() async throws {
        let purify = try TestVendor.script("md-preview/Vendor/DOMPurify/purify.min.js")
        let morphdom = try TestVendor.script("md-preview/Vendor/Morphdom/morphdom.min.js")
        let page = """
        <!DOCTYPE html><html><head>
        <script>\(purify)</script><script>\(morphdom)</script>
        <script>window.webkit={messageHandlers:{mdPreviewHost:{postMessage(){}}}};</script>
        \(MarkdownHTML.hostBridgeScript)
        </head><body><article class="markdown-body"></article></body></html>
        """
        let webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 900, height: 600))
        webView.loadHTMLString(page, baseURL: TestVendor.repositoryRoot)
        while webView.isLoading { try await Task.sleep(for: .milliseconds(10)) }

        let article = MarkdownHTML.render(
            markdown: "```mermaid\ngraph TD; A-->B\n```\n", vendorLoading: .lazy
        ).articleHTML
        _ = try await webView.evaluateJavaScript(
            "window.MdPreview.update(\(MarkdownHTML.javaScriptStringLiteral(article))); true"
        )
        try await Task.sleep(for: .milliseconds(120))

        let count = try await webView.evaluateJavaScript(
            "document.querySelectorAll('.mermaid-hud button').length"
        ) as? Int ?? 0
        XCTAssertEqual(
            count, 5,
            """
            The Mermaid HUD controls did not survive sanitisation. They are \
            emitted as article HTML, so anything that forbids <button> deletes \
            zoom out, reset, zoom in, fill width and open-in-window — with no \
            other test noticing, because the rest assert only what must be absent.
            """
        )
    }
}
