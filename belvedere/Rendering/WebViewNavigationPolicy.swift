//
//  WebViewNavigationPolicy.swift
//  belvedere
//

import Foundation

/// Decides which navigations of the app's own pages (the reader, the editor,
/// the Mermaid popup) WebKit may carry out.
///
/// Every page the app shows is an HTML string it builds and loads with
/// `loadHTMLString(_:baseURL: nil)`, so its main frame is only ever
/// `about:blank`. Anything else in the main frame was started by something
/// other than the app, and the one route that exists is a drop: WebKit loads
/// a file or `http(s)` URL dropped on a web view as the new top-level page
/// unless the page itself handles the drop. A dropped SVG file then runs its
/// script with the page's message handlers (`mdPreviewHost`, the editor
/// bridge) and without the app's Content Security Policy, and a dropped link
/// fetches a remote page. Drags that start in the same page are refused by
/// WebKit itself; drags from Finder or a browser are not.
/// `DropNavigationTests` reproduces this in a real `WKWebView`.
///
/// Link clicks are not decided here: the reader handles them before asking,
/// and hands them to the system.
nonisolated enum WebViewNavigationPolicy {
    /// - Parameters:
    ///   - url: the navigation's request URL.
    ///   - isMainFrame: whether it replaces the page itself. A navigation
    ///     with no target frame (a new window) counts as one. Subframes are
    ///     left to each page's Content Security Policy, which allows none.
    static func allows(url: URL?, isMainFrame: Bool) -> Bool {
        guard isMainFrame else { return true }
        guard let url, url.scheme?.lowercased() == "about" else { return false }
        // A same-document jump inside the page keeps its fragment.
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        components?.fragment = nil
        return components?.string?.lowercased() == "about:blank"
    }
}
