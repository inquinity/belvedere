import AppKit
import WebKit

/// A read-only snapshot of one table, using the regular sanitized renderer and
/// link/asset policies. The source document and its editing state stay intact.
///
/// `containmentRoot` has no default: the table's images load under the same
/// folder boundary as the document they came from. A caller that left it out
/// would quietly apply a different boundary from the one on screen.
@MainActor
final class TablePreviewWindow: NSObject, NSWindowDelegate {
    static let shared = TablePreviewWindow()
    private var tableWindow: NSWindow?
    private var preview: MarkdownWebView?

    func present(markdown: String, title: String?, assetBaseURL: URL?, containmentRoot: URL?,
                 relativeTo parent: NSWindow?) {
        guard !markdown.isEmpty else { return }
        let window: NSWindow
        let preview: MarkdownWebView
        if let existing = tableWindow, let existingPreview = self.preview {
            window = existing
            preview = existingPreview
        } else {
            let frame = (parent?.screen ?? NSScreen.main)?.visibleFrame
                ?? NSRect(x: 0, y: 0, width: 1100, height: 800)
            window = NSWindow(contentRect: frame.insetBy(dx: 32, dy: 32),
                              styleMask: [.titled, .closable, .resizable, .miniaturizable],
                              backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.collectionBehavior = [.fullScreenPrimary]
            window.delegate = self
            preview = MarkdownWebView(frame: .zero)
            // Fill the table window independently of the document's reading
            // column and custom margins. Keep the standard theme and fonts.
            preview.webView.configuration.userContentController.addUserScript(WKUserScript(source: """
                const tableWindowStyle = document.createElement('style');
                tableWindowStyle.textContent = `
                    body { padding: 24px !important; }
                    article.markdown-body { max-width: none !important; margin: 0 !important; }
                    [data-md-app="table-actions"] { display: none !important; }
                    .md-table-wrap { padding-top: 0 !important; margin-top: 0 !important; }
                    /* The header row sticks to the window, so the page
                       must be the only scroller: the article and the table
                       scroll horizontally in the document. A theme page
                       color wins over the default background here. */
                    html { overflow-x: auto !important; }
                    :where(html) { background: -apple-system-text-background; }
                    article.markdown-body, table { overflow: visible; }
                    /* Only a single column header row: row headers in a raw
                       HTML table body, or several header rows, would pile
                       up at the top. */
                    thead > tr:only-child > th {
                        position: sticky;
                        top: 0;
                        background: var(--mdp-page-bg, -apple-system-text-background);
                        box-shadow: inset 0 -1px var(--grid);
                    }
                `;
                document.head.append(tableWindowStyle);
                """, injectionTime: .atDocumentEnd, forMainFrameOnly: true))
            window.contentView = preview
            tableWindow = window
            self.preview = preview
        }
        window.title = title.flatMap { $0.isEmpty ? nil : $0 }
            ?? NSLocalizedString("Table", comment: "Expanded table window title")
        preview.contentDidReplace = { [weak window, weak preview] in
            preview?.contentDidReplace = nil
            guard let window else { return }
            window.makeKeyAndOrderFront(nil)
            if !window.styleMask.contains(.fullScreen) { window.toggleFullScreen(nil) }
        }
        preview.display(markdown: markdown, assetBaseURL: assetBaseURL, containmentRoot: containmentRoot)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }

    func windowDidExitFullScreen(_ notification: Notification) {
        tableWindow?.close()
    }

    func windowWillClose(_ notification: Notification) {
        preview?.contentDidReplace = nil
        preview?.clearContent()
        preview = nil
        tableWindow = nil
    }
}
