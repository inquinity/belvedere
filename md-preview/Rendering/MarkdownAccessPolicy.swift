//
//  MarkdownAccessPolicy.swift
//  md-preview
//

import Foundation

/// Which folder a document may read from, and what a click on a link
/// pointing outside it should do.
///
/// These are two questions, deliberately kept apart. An asset load happens
/// because a document was rendered — nobody asked for it, so it stays silent
/// and bounded. A link click happened because the reader asked, so it may
/// offer a way through, with the reader deciding and the target named.
///
/// Pure Foundation, so the helper test package covers it.
nonisolated enum MarkdownAccessPolicy {

    /// The folder that bounds a document's asset loads and link targets.
    ///
    /// A folder the reader explicitly opened wins for documents inside it, so
    /// a project keeps working: `docs/guide.md` reaches `../images/logo.png`.
    /// Everything else falls back to the document's own folder — that is what
    /// a standalone file gets, and what Quick Look always gets.
    ///
    /// The opened folder is never derived from where a document sits. See
    /// `MarkdownAssetResolution` for why a boundary that widens with the
    /// document's location is not a boundary at all.
    static func containmentRoot(documentFolder: URL?, openedFolder: URL?) -> URL? {
        guard let documentFolder else { return nil }
        guard let openedFolder,
              MarkdownAssetResolution.isContained(documentFolder, in: openedFolder)
        else { return documentFolder }
        return openedFolder
    }

    /// The opened folder that survives loading a document: kept while the
    /// document is inside it, dropped otherwise.
    ///
    /// Dropping it matters because the file navigator re-roots to the new
    /// file at that same moment. A boundary that stayed behind while the
    /// sidebar showed something else would be one nobody could see.
    static func openedFolder(_ openedFolder: URL?, afterLoading documentFolder: URL?) -> URL? {
        guard let openedFolder, let documentFolder,
              MarkdownAssetResolution.isContained(documentFolder, in: openedFolder)
        else { return nil }
        return openedFolder
    }

    /// What activating a link should do.
    enum LinkAction: Equatable {
        /// A Markdown file inside the boundary: open it in the viewer.
        case openInViewer(URL)
        /// Another file type inside the boundary: hand it to the system.
        case openWithSystem(URL)
        /// A Markdown file outside the boundary: confirm, then open it in the
        /// viewer, where it is rendered under its own boundary.
        case confirmOpenOutside(URL)
        /// Another file type outside the boundary: confirm, then reveal it in
        /// Finder. Never launched — document content named this path, and
        /// launching it would run whatever it points at.
        case confirmRevealOutside(URL)
        /// The document has no folder yet, so a relative link cannot resolve
        /// to anything. Offer to save it rather than doing nothing.
        case saveDocumentFirst
        /// Vendor URLs, and anything naming no file at all.
        case ignore
    }

    /// Decides what a clicked `md-asset:` link should do.
    ///
    /// `isMarkdown` is supplied by the caller so this stays free of the
    /// document-type list, which lives with the view.
    static func linkAction(for assetURL: URL,
                           documentFolder: URL?,
                           containmentRoot: URL?,
                           isMarkdown: (URL) -> Bool) -> LinkAction {
        guard assetURL.scheme == MarkdownAssetResolution.scheme,
              !assetURL.path.hasPrefix(MarkdownAssetResolution.vendorPathPrefix)
        else { return .ignore }

        // No folder: an unsaved document. Relative references have nothing to
        // resolve against, which is a reason to say so, not to ignore the
        // click.
        guard documentFolder != nil else { return .saveDocumentFirst }

        guard let target = MarkdownAssetResolution.candidateFileURL(for: assetURL) else {
            return .ignore
        }

        if let containmentRoot,
           MarkdownAssetResolution.fileURL(for: assetURL, containedIn: containmentRoot) != nil {
            return isMarkdown(target) ? .openInViewer(target) : .openWithSystem(target)
        }
        return isMarkdown(target) ? .confirmOpenOutside(target) : .confirmRevealOutside(target)
    }
}
