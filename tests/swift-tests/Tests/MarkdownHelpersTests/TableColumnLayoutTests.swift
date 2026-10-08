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

    private static let long = String(repeating: "Remotes, tracking scripts, this document and the FORK STATUS blocks. ", count: 4)

    func testShortColumnsKeepTheirWordsNextToAWideColumn() async throws {
        let long = Self.long
        try await assertColumnsKeepTheirWords("""
        | # | Milestone | Contents |
        | --- | --- | --- |
        | M0 | Repo setup | \(long) |
        | M3b | Deprivileging | \(long) |
        | M5 | Distribution | \(long) |
        """)
    }

    /// Inline code sets `overflow-wrap: anywhere` on itself, so a column of
    /// nothing but code spans needs its own rule to keep its words.
    func testColumnsOfCodeSpansKeepTheirWords() async throws {
        let long = Self.long
        try await assertColumnsKeepTheirWords("""
        | Command | Notes | Contents |
        | --- | --- | --- |
        | `just release` | `RELEASE-AUTOMATION` | \(long) |
        | `notarytool` | `Deprivileging` | \(long) |
        | `Distribution` | `Containment` | \(long) |
        """)
    }

    /// The reported case: Full Width, a wide window, and a wide column between
    /// narrow ones at both ends, the way the roadmap table is shaped. The
    /// last column squeezed to a letter as badly as the first.
    func testNarrowFirstAndLastColumnsKeepTheirWordsInFullWidth() async throws {
        let long = Self.long
        let rows = (1...3).map { "| F\($0)9 | Quick Look repair setting | \(long) | 2.1 candidate |" }.joined(separator: "\n")
        let markdown = "| ID | Item | Where it stands | Release |\n| --- | --- | --- | --- |\n" + rows
        try await assertColumnsKeepTheirWords(markdown, contentWidth: .full, width: 2000)
        try await assertColumnsKeepTheirWords(markdown, contentWidth: .full, width: 1100)
    }

    /// Something that cannot break, such as a long address, widens its column and
    /// the table scrolls sideways. It is not cut into pieces and it does not
    /// squeeze the other columns.
    func testAnUnbreakableStringScrollsInsteadOfSqueezingTheOthers() async throws {
        let address = "https://example.com/" + String(repeating: "segment/", count: 40) + "end"
        let markdown = "| ID | Link | Release |\n| --- | --- | --- |\n| F19 | \(address) | 2.1 candidate |"
        let html = MarkdownHTML.render(
            markdown: markdown, allowsScroll: true, contentWidth: .full,
            documentFont: .system, readerLayout: ReaderLayoutSetting(),
            pageTopClearance: MarkdownHTML.appPageTopClearance
        ).html
        let harness = WebViewLayoutHarness(html: html, width: 900, isEditor: false, height: 900)
        defer { harness.close() }
        _ = try await harness.layout(texts: [], imageCount: 0, selectors: ["table": 1])
        let result = try await harness.webView.callAsyncJavaScript("""
            const table = document.querySelector('table');
            const widths = [...table.querySelector('tr').children].map(c => c.getBoundingClientRect().width);
            return JSON.stringify({scrolls: table.scrollWidth > table.clientWidth + 1, first: widths[0], last: widths[2]});
            """, in: nil, contentWorld: .page)
        let json = try XCTUnwrap(result as? String)
        let measured = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any])
        XCTAssertEqual(measured["scrolls"] as? Bool, true)
        XCTAssertGreaterThan(measured["first"] as? Double ?? 0, 30, "The first column was squeezed.")
        XCTAssertGreaterThan(measured["last"] as? Double ?? 0, 60, "The last column was squeezed.")
    }

    private func assertColumnsKeepTheirWords(_ markdown: String,
                                             contentWidth: MarkdownHTML.ContentWidth = .centered,
                                             width: CGFloat = 900) async throws {
        let html = MarkdownHTML.render(
            markdown: markdown, allowsScroll: true, contentWidth: contentWidth,
            documentFont: .system, readerLayout: ReaderLayoutSetting(),
            pageTopClearance: MarkdownHTML.appPageTopClearance
        ).html
        let harness = WebViewLayoutHarness(html: html, width: width, isEditor: false, height: 900)
        defer { harness.close() }
        _ = try await harness.layout(texts: [], imageCount: 0, selectors: ["table": 1])

        let result = try await harness.webView.callAsyncJavaScript("""
            // The width of each word of a cell (a hyphen is a break opportunity), measured in the cell's own font,
            // against the width its column actually gave it.
            const probe = document.createElement('span');
            probe.style.cssText = 'position:absolute;visibility:hidden;white-space:nowrap';
            document.body.appendChild(probe);
            const problems = [];
            for (const cell of document.querySelectorAll('tr > *')) {
                const style = getComputedStyle(cell);
                probe.style.font = style.font;
                const room = cell.clientWidth - parseFloat(style.paddingLeft) - parseFloat(style.paddingRight);
                for (const word of cell.textContent.trim().split(/[\\s-]+/)) {
                    probe.textContent = word;
                    const needed = probe.getBoundingClientRect().width;
                    if (needed > room + 0.5) problems.push(word + ': needs ' + needed.toFixed(1) + ', has ' + room.toFixed(1));
                }
            }
            // The table must still fit its article: nothing here is an unbreakable
            // string, so a sideways scroll would mean the fix over-corrected.
            const table = document.querySelector('table');
            if (table.scrollWidth > table.clientWidth + 1) {
                problems.push('table scrolls sideways: ' + table.scrollWidth + ' in ' + table.clientWidth);
            }
            return JSON.stringify(problems);
            """, in: nil, contentWorld: .page)
        let json = try XCTUnwrap(result as? String)
        let problems = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String])
        XCTAssertEqual(problems, [], "A short column is narrower than its longest word, so words break mid-word.")
    }
}
