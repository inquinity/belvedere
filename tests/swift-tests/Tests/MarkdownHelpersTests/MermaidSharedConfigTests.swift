import JavaScriptCore
import XCTest
@testable import MarkdownHelpers

/// The Mermaid settings both views pass to `mermaid.initialize`. The layout
/// tests compare the reading view with the editor, so they cannot notice a
/// setting removed from both at once; these pin the values themselves.
final class MermaidSharedConfigTests: XCTestCase {
    private func sharedConfig() throws -> [String: Any] {
        let context = try XCTUnwrap(JSContext())
        let value = context.evaluateScript("(\(MarkdownHTML.mermaidSharedConfig))")
        XCTAssertNil(context.exception, "mermaidSharedConfig is not a valid object literal")
        return try XCTUnwrap(value?.toDictionary() as? [String: Any])
    }

    /// Mermaid 12's defaults (ELK, the neo look, 120 px minimum node width
    /// and 120 px wrap) change existing diagrams; these keep 11.15's.
    func testKeepsMermaid11LayoutLookAndNodeSizes() throws {
        let config = try sharedConfig()
        XCTAssertEqual(config["layout"] as? String, "dagre")
        XCTAssertEqual(config["look"] as? String, "classic")
        for section in ["flowchart", "state"] {
            let settings = try XCTUnwrap(config[section] as? [String: Any], section)
            XCTAssertEqual(settings["minNodeWidth"] as? Int, 0, section)
            XCTAssertEqual(settings["wrappingWidth"] as? Int, 200, section)
        }
        let swimlane = try XCTUnwrap(config["swimlane"] as? [String: Any])
        XCTAssertEqual(swimlane["layout"] as? String, "swimlane",
                       "a top-level layout would otherwise lay swimlane diagrams out without lanes")
    }

    func testKeepsStrictSecurityAndTheReaderFont() throws {
        let config = try sharedConfig()
        XCTAssertEqual(config["securityLevel"] as? String, "strict")
        XCTAssertTrue((config["fontFamily"] as? String)?.hasPrefix("-apple-system") == true)
        XCTAssertNil(config["startOnLoad"], "each view sets startOnLoad itself, after the shared settings")
        XCTAssertNil(config["theme"], "each view sets the theme itself, after the shared settings")
    }

    /// Both views must use the one definition, not a copy.
    func testReaderAndEditorBothUseTheSharedSettings() {
        XCTAssertTrue(MarkdownHTML.mermaidInitWiring.contains(MarkdownHTML.mermaidSharedConfig))
        let editor = EditorHTML.render(markdown: "x", editorJavaScript: "", mermaidJavaScript: "",
                                       configuration: .init(fullWidth: false, usesPageScrolling: false))
        XCTAssertTrue(editor.contains(MarkdownHTML.mermaidSharedConfig))
    }
}
