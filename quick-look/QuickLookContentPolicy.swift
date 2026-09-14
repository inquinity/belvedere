import Foundation

/// Content-Security-Policy for the Quick Look preview page.
///
/// The extension holds `com.apple.security.network.client`, and cannot give it
/// up: without it, WKWebView inside a sandboxed app extension never completes
/// its load, `didFinish` never fires, and the preview renders blank. Verified
/// by removing the entitlement and watching Quick Look go blank while the
/// extension still launched and `qlmanage` still exited zero.
///
/// The consequence is that a Markdown document referencing a remote image
/// reaches the network when a file is merely spacebar-previewed in Finder — no
/// click, no app launch — telling that server the file was opened. Since the
/// sandbox can't prevent it, the page does. See #339 for the full write-up and
/// a working PoC.
///
/// This is safe to make strict because the Quick Look shell is entirely
/// self-contained. `MarkdownHTML` inlines the vendor bundles as `<script>`
/// blocks rather than referencing them, `InlineLocalAssets` rewrites local
/// images to `data:` URLs (view-controller path) or `cid:` attachments
/// (`QLPreviewReply` path), and the page loads with a nil base URL. Nothing
/// legitimate on this page needs an external origin.
///
/// The main app's preview is a different shape — it serves vendor scripts and
/// images over the `md-asset:` scheme — and is not covered here; see
/// `PreviewContentPolicy`.
enum QuickLookContentPolicy {

    /// `'unsafe-inline'` is unavoidable: the host bridge, the DOMPurify
    /// bootstrap and the vendor bundles are all emitted inline, and the theme
    /// is injected as an inline `<style>`. The security value here is
    /// `default-src 'none'` and, above all, the absence of `http:`/`https:`
    /// from `img-src`.
    static let policy = [
        "default-src 'none'",
        "script-src 'unsafe-inline'",
        "style-src 'unsafe-inline'",
        // data: for the view-controller path, cid: for QLPreviewReply attachments.
        "img-src data: cid:",
        "font-src data:"
    ].joined(separator: "; ")

    static let metaTag =
        #"<meta http-equiv="Content-Security-Policy" content="\#(policy)">"#

    /// Inserts the policy as the first child of `<head>`.
    ///
    /// Returns the HTML unchanged when there is no `<head>` to insert into.
    /// That should never happen — `MarkdownHTML` always emits one — so rather
    /// than fail closed and hand the reader a blank preview over a
    /// defence-in-depth measure, the shape change is caught by
    /// `QuickLookContentPolicyTests` instead.
    static func applying(to html: String) -> String {
        guard let head = html.range(of: "<head>") else { return html }
        return html.replacingCharacters(in: head, with: "<head>" + metaTag)
    }
}
