import AppKit
import XCTest
@testable import MarkdownHelpers

/// The article sets `overflow-wrap: anywhere`, and every table cell inherits
/// it. `anywhere` also lowers a cell's minimum width to one character, so next
/// to a wide column the narrow ones were squeezed to a letter each ("M" over
/// "0", "setu" over "p"). That arrived in 1.3.0 with upstream's #431 and made
/// wide tables, such as the fork notes' roadmap, unreadable.
@MainActor
final class TableColumnLayoutTests: XCTestCase {

    func testShortColumnsKeepTheirWordsNextToAWideColumn() async throws {
        let long = String(repeating: "Remotes, tracking scripts, this document and the FORK STATUS blocks. ", count: 4)
        let markdown = """
        | # | Milestone | Contents |
        | --- | --- | --- |
        | M0 | Repo setup | \(long) |
        | M3b | Deprivileging | \(long) |
        | M5 | Distribution | \(long) |
        """
        let html = MarkdownHTML.render(
            markdown: markdown, allowsScroll: true, contentWidth: .centered,
            documentFont: .system, readerLayout: ReaderLayoutSetting(),
            pageTopClearance: MarkdownHTML.appPageTopClearance
        ).html
        let harness = WebViewLayoutHarness(html: html, width: 900, isEditor: false, height: 900)
        defer { harness.close() }
        _ = try await harness.layout(texts: [], imageCount: 0, selectors: ["table": 1])

        let result = try await harness.webView.callAsyncJavaScript("""
            // The width of each word of a cell, measured in the cell's own font,
            // against the width its column actually gave it.
            const probe = document.createElement('span');
            probe.style.cssText = 'position:absolute;visibility:hidden;white-space:nowrap';
            document.body.appendChild(probe);
            const problems = [];
            for (const cell of document.querySelectorAll('tr > :nth-child(-n+2)')) {
                const style = getComputedStyle(cell);
                probe.style.font = style.font;
                const room = cell.clientWidth - parseFloat(style.paddingLeft) - parseFloat(style.paddingRight);
                for (const word of cell.textContent.trim().split(/\\s+/)) {
                    probe.textContent = word;
                    const needed = probe.getBoundingClientRect().width;
                    if (needed > room + 0.5) problems.push(word + ': needs ' + needed.toFixed(1) + ', has ' + room.toFixed(1));
                }
            }
            return JSON.stringify(problems);
            """, in: nil, contentWorld: .page)
        let json = try XCTUnwrap(result as? String)
        let problems = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String])
        XCTAssertEqual(problems, [], "A short column is narrower than its longest word, so words break mid-word.")
    }
}
