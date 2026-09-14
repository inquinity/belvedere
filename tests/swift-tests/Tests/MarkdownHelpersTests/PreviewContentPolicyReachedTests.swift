import Foundation
import XCTest

/// `PreviewContentPolicyTests` and `QuickLookContentPolicyTests` prove the
/// policies are correct. This proves they are actually reached: every place
/// that hands rendered HTML to a `WKWebView` (or, for Quick Look, back to the
/// host as a `QLPreviewReply`) must route it through `applying(to:)` first.
/// A call site added later and left unwrapped would ship a page with no CSP
/// at all, silently — this fails loudly instead.
final class PreviewContentPolicyReachedTests: XCTestCase {

    private func text(at relativePath: String) throws -> String {
        try String(
            contentsOf: TestVendor.repositoryRoot.appendingPathComponent(relativePath),
            encoding: .utf8
        )
    }

    func testEveryAppWindowLoadAppliesThePreviewPolicy() throws {
        let source = try text(at: "md-preview/Rendering/MarkdownWebView.swift")
        let raw = source.components(separatedBy: "loadHTMLString(rendered.html").count - 1
        XCTAssertEqual(raw, 0, "found rendered.html handed to loadHTMLString unwrapped")
        let wrapped = source.components(separatedBy: "PreviewContentPolicy.applying(to: rendered.html)").count - 1
        XCTAssertEqual(wrapped, 3, "expected three policy-wrapped loads in MarkdownWebView.swift")
    }

    func testEditorLoadAppliesThePreviewPolicy() throws {
        let source = try text(at: "md-preview/Features/Editor/EditorViewController.swift")
        XCTAssertTrue(source.contains("PreviewContentPolicy.applying(to: Self.editorHTML("))
    }

    func testBothQuickLookPathsApplyTheQuickLookPolicy() throws {
        for path in ["quick-look/PreviewViewController.swift", "quick-look/PreviewProvider.swift"] {
            XCTAssertTrue(
                try text(at: path).contains("QuickLookContentPolicy.applying"),
                "\(path) no longer applies the Content-Security-Policy"
            )
        }
    }
}
