//
//  MarkdownDocumentController.swift
//  belvedere
//

import Cocoa
import UniformTypeIdentifiers

final class MarkdownDocumentController: NSDocumentController {
    private static let markdownFileExtensions = ["md", "markdown", "mdown", "mdx", "txt"]

    override func beginOpenPanel(
        _ openPanel: NSOpenPanel,
        forTypes inTypes: [String]?
    ) async -> Int {
        openPanel.allowsMultipleSelection = false
        openPanel.canChooseDirectories = true
        openPanel.canChooseFiles = true
        openPanel.message = NSLocalizedString(
            "Choose a Markdown file or folder",
            comment: "Open panel prompt"
        )
        openPanel.allowedContentTypes = Self.markdownFileExtensions
            .compactMap { UTType(filenameExtension: $0) }
        return await super.beginOpenPanel(openPanel, forTypes: inTypes)
    }

    override func openDocument(
        withContentsOf url: URL,
        display displayDocument: Bool,
        completionHandler: @escaping (NSDocument?, Bool, Error?) -> Void
    ) {
        if url.isExistingDirectory,
           let appDelegate = NSApp.delegate as? AppDelegate {
            appDelegate.openFolder(url)
            completionHandler(nil, false, nil)
            return
        }

        super.openDocument(
            withContentsOf: url,
            display: displayDocument,
            completionHandler: completionHandler
        )
    }

    /// File ▸ New (⌘N) always makes a window of its own. Without this the new
    /// window joined the front window's tab group whenever macOS's "Prefer tabs
    /// when opening documents" was on, so ⌘N added a tab and a separate window
    /// needed a drag. Tabs stay an explicit choice: File ▸ New Tab (⌘T) and the
    /// *Open documents in tabs* preference are unaffected.
    override func openUntitledDocumentAndDisplay(_ displayDocument: Bool) throws -> NSDocument {
        DocumentWindowController.markNextWindowAsSeparate()
        // The flag is consumed when the window is built; clear it if no window
        // was, so it cannot leak to whatever opens next.
        defer { DocumentWindowController.nextWindowDeclinesTabbing = false }
        let document = try super.openUntitledDocumentAndDisplay(displayDocument)
        if displayDocument {
            (document.windowControllers.first as? DocumentWindowController)?
                .enterEditMode(autofocus: true)
        }
        return document
    }
}
