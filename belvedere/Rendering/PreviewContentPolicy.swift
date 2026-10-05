import Foundation

/// Content-Security-Policy for the app's own preview and editor pages.
///
/// The companion to `QuickLookContentPolicy`, and the more important of the
/// two now: `com.apple.security.network.client` cannot be removed from either
/// target — WKWebView will not complete a load without it, and both surfaces
/// render blank — so the sandbox cannot stop a document from reaching the
/// network. This policy is what does.
///
/// Without it, a Markdown file referencing `https://example.com/pixel.png`
/// causes that request on open, telling the server the document was read, by
/// whom (by IP) and when. The app itself contacts nothing; that guarantee comes
/// from the telemetry and updater code being gone. This closes the other half:
/// content the app renders on someone else's behalf.
///
/// Deliberately *not* shared with `QuickLookContentPolicy`. The two pages have
/// genuinely different shapes — Quick Look inlines its vendor bundles and
/// carries images as `data:`/`cid:`, while this page fetches scripts and images
/// over the `md-asset:` scheme — so a single policy would have to be the union
/// of both, which is weaker than either.
enum PreviewContentPolicy {

    /// Why each source is permitted:
    ///
    /// - `script-src 'unsafe-inline'` — the host bridge, the DOMPurify
    ///   bootstrap, the theme injection and the editor's CodeMirror bundle are
    ///   all emitted inline. Unavoidable without restructuring upstream's
    ///   renderer.
    /// - `script-src md-asset:` — the reader lazy-loads KaTeX, highlight.js and
    ///   Mermaid over the custom scheme after first paint (`VendorLoading.lazy`).
    ///   The scheme handler serves only an allow-listed set of bundled files,
    ///   so this is narrower than it looks.
    /// - `img-src md-asset:` — local images in the document, resolved against
    ///   the page's `<base href>`.
    /// - `font-src data:` — the bundled KaTeX CSS carries its fonts as base64
    ///   `data:` URIs, so no external font origin is needed.
    ///
    /// What matters is what is absent: `http:` and `https:`. `default-src
    /// 'none'` covers everything not named, including `connect-src`, so
    /// `fetch`/XHR to any origin is denied too.
    static let policy = [
        "default-src 'none'",
        "script-src 'unsafe-inline' md-asset:",
        "style-src 'unsafe-inline'",
        "img-src md-asset: data:",
        "font-src data:"
    ].joined(separator: "; ")

    static let metaTag =
        #"<meta http-equiv="Content-Security-Policy" content="\#(policy)">"#

    /// Inserts the policy as the first child of `<head>`.
    ///
    /// Returns the HTML unchanged when there is no `<head>`, for the same
    /// reason as the Quick Look policy: a missing head means the renderer
    /// changed shape, and blanking the reader's document over a
    /// defence-in-depth measure would be a worse failure than the one being
    /// prevented. `PreviewContentPolicyTests` catches the shape change instead.
    static func applying(to html: String) -> String {
        guard let head = html.range(of: "<head>") else { return html }
        return html.replacingCharacters(in: head, with: "<head>" + metaTag)
    }
}
