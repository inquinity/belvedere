import AppKit
import XCTest
@testable import MarkdownHelpers

/// The saved default width, and what each choice does to the page.
@MainActor
final class ContentWidthSettingTests: XCTestCase {
    private let key = "belvedere.contentWidth"
    private var saved: Any?

    override func setUp() {
        saved = UserDefaults.standard.object(forKey: key)
        UserDefaults.standard.removeObject(forKey: key)
    }

    override func tearDown() {
        if let saved { UserDefaults.standard.set(saved, forKey: key) }
        else { UserDefaults.standard.removeObject(forKey: key) }
    }

    func testNothingSavedMeansFullWidth() {
        XCTAssertEqual(ContentWidthSetting.current, .fullWidth)
    }

    func testQuickLookWidthIsSavedUnderItsOldName() {
        ContentWidthSetting.current = .quickLook
        XCTAssertEqual(UserDefaults.standard.string(forKey: key), "normal",
                       "Stored as normal so a value saved before the rename still reads back.")
        XCTAssertEqual(ContentWidthSetting.current, .quickLook)
    }

    func testFullWidthStoresNothing() {
        ContentWidthSetting.current = .quickLook
        ContentWidthSetting.current = .fullWidth
        XCTAssertNil(UserDefaults.standard.object(forKey: key))
    }

    func testValuesSavedByEarlierVersionsStillRead() {
        UserDefaults.standard.set("fullWidth", forKey: key)
        XCTAssertEqual(ContentWidthSetting.current, .fullWidth)
        UserDefaults.standard.set("normal", forKey: key)
        XCTAssertEqual(ContentWidthSetting.current, .quickLook)
        UserDefaults.standard.set("nonsense", forKey: key)
        XCTAssertEqual(ContentWidthSetting.current, .fullWidth, "An unreadable value falls back to the default.")
    }

    func testTheCappedColumnHasAClearName() {
        XCTAssertEqual(ContentWidthSetting.quickLook.title, "Quick Look Width")
    }

    /// Full width follows the window as it grows; the Quick Look width stops at
    /// its column. Both shrink the same way, because below the cap they are
    /// the same layout.
    func testFullWidthGrowsWithTheWindowAndQuickLookWidthStopsAtItsColumn() async throws {
        var widths: [Int: (full: Double, quickLook: Double)] = [:]
        for window in [500, 700, 1000, 1500] {
            var measured: [Double] = []
            for setting in [ContentWidthSetting.fullWidth, .quickLook] {
                let html = MarkdownHTML.render(
                    markdown: "# Heading\n\n" + String(repeating: "A paragraph of ordinary text that wraps. ", count: 40),
                    allowsScroll: true, contentWidth: setting.renderWidth,
                    documentFont: .system, readerLayout: ReaderLayoutSetting(),
                    pageTopClearance: MarkdownHTML.appPageTopClearance
                ).html
                let harness = WebViewLayoutHarness(html: html, width: CGFloat(window), isEditor: false, height: 800)
                defer { harness.close() }
                _ = try await harness.layout(texts: [], imageCount: 0)
                let width = try await harness.webView.callAsyncJavaScript(
                    "return document.querySelector('article').getBoundingClientRect().width",
                    in: nil, contentWorld: .page)
                measured.append(try XCTUnwrap(width as? Double))
            }
            widths[window] = (measured[0], measured[1])
        }
        let column = Double(MarkdownHTML.contentColumnWidth)
        for (window, pair) in widths.sorted(by: { $0.key < $1.key }) {
            XCTAssertLessThanOrEqual(pair.quickLook, column + 0.5, "quick look at \(window)")
        }
        // Growing: full width keeps getting wider, quick look stays at its column.
        XCTAssertGreaterThan(widths[1500]!.full, widths[1000]!.full + 100)
        XCTAssertGreaterThan(widths[1000]!.full, widths[700]!.full + 100)
        XCTAssertEqual(widths[1500]!.quickLook, column, accuracy: 0.5)
        // Shrinking: where the window is narrower than the column, both are the same.
        XCTAssertEqual(widths[500]!.full, widths[500]!.quickLook, accuracy: 0.5)
    }
}
