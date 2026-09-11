import XCTest
@testable import MarkdownHelpers

/// The boundary a document reads inside, and what a click on a link pointing
/// outside it does. Both are decisions document content can influence, so
/// each case below is one a Markdown file could arrange on its own.
final class MarkdownAccessPolicyTests: XCTestCase {

    private let project = URL(fileURLWithPath: "/Users/me/project", isDirectory: true)
    private let docs = URL(fileURLWithPath: "/Users/me/project/docs", isDirectory: true)
    private let elsewhere = URL(fileURLWithPath: "/Users/me/other", isDirectory: true)

    // MARK: - Which folder bounds a document

    /// The case the review asked for: a project opened by the reader, and a
    /// document one level down reaching a sibling folder.
    func testOpenedFolderBoundsADocumentInsideIt() {
        XCTAssertEqual(
            MarkdownAccessPolicy.containmentRoot(documentFolder: docs, openedFolder: project),
            project
        )
    }

    func testDocumentOutsideTheOpenedFolderKeepsItsOwnFolder() {
        XCTAssertEqual(
            MarkdownAccessPolicy.containmentRoot(documentFolder: elsewhere, openedFolder: project),
            elsewhere
        )
    }

    func testWithoutAnOpenedFolderTheDocumentFolderBounds() {
        XCTAssertEqual(
            MarkdownAccessPolicy.containmentRoot(documentFolder: docs, openedFolder: nil),
            docs
        )
    }

    /// An unsaved document has no folder, so nothing may resolve.
    func testUnsavedDocumentHasNoBoundary() {
        XCTAssertNil(
            MarkdownAccessPolicy.containmentRoot(documentFolder: nil, openedFolder: project)
        )
    }

    /// `/Users/me/project-private` is a sibling, not a descendant. Sharing a
    /// name prefix must not put a document inside the opened folder.
    func testSiblingFolderWithSharedPrefixIsNotInsideTheOpenedFolder() {
        let sibling = URL(fileURLWithPath: "/Users/me/project-private", isDirectory: true)
        XCTAssertEqual(
            MarkdownAccessPolicy.containmentRoot(documentFolder: sibling, openedFolder: project),
            sibling
        )
    }

    // MARK: - The opened folder is dropped when the reader leaves it

    func testOpenedFolderSurvivesADocumentInsideIt() {
        XCTAssertEqual(
            MarkdownAccessPolicy.openedFolder(project, afterLoading: docs),
            project
        )
    }

    /// The file navigator re-roots at the same moment, so a boundary that
    /// stayed behind would be one nobody could see.
    func testOpenedFolderIsDroppedForADocumentOutsideIt() {
        XCTAssertNil(MarkdownAccessPolicy.openedFolder(project, afterLoading: elsewhere))
    }

    func testOpenedFolderIsDroppedForAnUnsavedDocument() {
        XCTAssertNil(MarkdownAccessPolicy.openedFolder(project, afterLoading: nil))
    }

    // MARK: - What a clicked link does

    private func action(_ assetPath: String,
                        documentFolder: URL?,
                        boundary: URL?) -> MarkdownAccessPolicy.LinkAction {
        MarkdownAccessPolicy.linkAction(
            for: URL(string: "md-asset://\(assetPath)")!,
            documentFolder: documentFolder,
            containmentRoot: boundary,
            isMarkdown: { ["md", "markdown"].contains($0.pathExtension.lowercased()) }
        )
    }

    func testMarkdownInsideTheBoundaryOpensInTheViewer() {
        XCTAssertEqual(
            action("/Users/me/project/README.md", documentFolder: docs, boundary: project),
            .openInViewer(URL(fileURLWithPath: "/Users/me/project/README.md"))
        )
    }

    /// The other half of the review's example: `docs/guide.md` reaching
    /// `../images/architecture.png` inside an opened project.
    func testCrossFolderReferenceResolvesInsideAnOpenedProject() {
        XCTAssertEqual(
            action("/Users/me/project/images/architecture.png",
                   documentFolder: docs,
                   boundary: project),
            .openWithSystem(URL(fileURLWithPath: "/Users/me/project/images/architecture.png"))
        )
    }

    func testMarkdownOutsideTheBoundaryIsOfferedRatherThanOpened() {
        XCTAssertEqual(
            action("/Users/me/other/notes.md", documentFolder: docs, boundary: project),
            .confirmOpenOutside(URL(fileURLWithPath: "/Users/me/other/notes.md"))
        )
    }

    /// Never `NSWorkspace.open` for a path document content chose: revealing
    /// shows the file without launching it.
    func testOtherFileOutsideTheBoundaryIsOfferedAsReveal() {
        XCTAssertEqual(
            action("/etc/passwd", documentFolder: docs, boundary: project),
            .confirmRevealOutside(URL(fileURLWithPath: "/etc/passwd"))
        )
    }

    /// A traversal that climbs out of the boundary is not silently followed.
    /// Four levels up from `project/docs` reaches the filesystem root.
    func testTraversalOutOfTheBoundaryIsNeverFollowedSilently() {
        let escape = action("/Users/me/project/docs/../../../../etc/passwd",
                            documentFolder: docs,
                            boundary: project)
        XCTAssertEqual(escape, .confirmRevealOutside(URL(fileURLWithPath: "/etc/passwd")))
    }

    /// Previously a silent no-op, which is what the review objected to.
    func testRelativeLinkInAnUnsavedDocumentOffersToSaveIt() {
        XCTAssertEqual(
            action("/notes.md", documentFolder: nil, boundary: nil),
            .saveDocumentFirst
        )
    }

    /// A **directory** named `trap.md` passes any extension-based check, and
    /// opening a directory as a document mounts it as the window's folder
    /// root — the one act that widens what a document may read. The caller's
    /// `isMarkdown` therefore answers "a Markdown *file*", and a target it
    /// rejects never reaches the viewer, inside the boundary or outside it.
    func testATargetTheCallerRejectsAsMarkdownNeverOpensInTheViewer() {
        let inside = MarkdownAccessPolicy.linkAction(
            for: URL(string: "md-asset:///Users/me/project/docs/trap.md")!,
            documentFolder: docs,
            containmentRoot: project,
            isMarkdown: { _ in false }
        )
        XCTAssertEqual(
            inside,
            .openWithSystem(URL(fileURLWithPath: "/Users/me/project/docs/trap.md"))
        )

        let outside = MarkdownAccessPolicy.linkAction(
            for: URL(string: "md-asset:///Users/me/other/trap.md")!,
            documentFolder: docs,
            containmentRoot: project,
            isMarkdown: { _ in false }
        )
        XCTAssertEqual(
            outside,
            .confirmRevealOutside(URL(fileURLWithPath: "/Users/me/other/trap.md"))
        )
    }

    /// `/__vendor/` is served from the app bundle and is never a file path,
    /// so an authored link to one stays inert.
    func testVendorLinksAreIgnored() {
        XCTAssertEqual(
            action("/__vendor/mermaid.min.js", documentFolder: docs, boundary: project),
            .ignore
        )
    }

    func testLinksWithAnotherSchemeAreNotThisPolicysBusiness() {
        XCTAssertEqual(
            MarkdownAccessPolicy.linkAction(
                for: URL(string: "https://example.com/a.md")!,
                documentFolder: docs,
                containmentRoot: project,
                isMarkdown: { _ in true }
            ),
            .ignore
        )
    }
}
