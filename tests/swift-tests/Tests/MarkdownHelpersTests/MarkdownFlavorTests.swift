import Foundation
import XCTest
@testable import MarkdownHelpers

/// Settings ▸ General ▸ Markdown flavor: which `> [!type]` blockquotes are
/// callouts. Extended takes every type; GitHub only what GitHub shows.
final class MarkdownFlavorTests: XCTestCase {
    private func html(_ markdown: String, _ flavor: MarkdownFlavor) -> String {
        EscapingHTMLFormatter.format(markdown, markdownFlavor: flavor)
    }

    private func isCallout(_ markdown: String, _ flavor: MarkdownFlavor) -> Bool {
        html(markdown, flavor).contains("class=\"markdown-alert")
    }

    // MARK: Both flavors

    func testGitHubAlertWithTagAloneIsACalloutInBoth() {
        for flavor in MarkdownFlavor.allCases {
            let output = html("> [!WARNING]\n> Back up first.", flavor)
            XCTAssertTrue(output.contains("markdown-alert-warning"), "\(flavor): \(output)")
            XCTAssertTrue(output.contains("Back up first."), "\(flavor)")
        }
    }

    func testTagIsCaseInsensitiveInBoth() {
        for flavor in MarkdownFlavor.allCases {
            XCTAssertTrue(isCallout("> [!note]\n> Text.", flavor), "\(flavor)")
        }
    }

    // MARK: Extended

    func testExtendedTakesObsidianKindsAliasesTitlesAndFolding() {
        XCTAssertTrue(html("> [!faq]\n> Why?", .extended).contains("markdown-alert-question"))
        XCTAssertTrue(html("> [!hint]\n> Try this.", .extended).contains("markdown-alert-tip"))
        XCTAssertTrue(html("> [!NOTE] My title\n> Body.", .extended).contains("My title"))
        XCTAssertTrue(html("> [!faq]- Folded\n> Answer.", .extended).contains("<details class=\"markdown-alert"))
        XCTAssertTrue(isCallout("> [!anything]\n> Unknown types look like a note.", .extended))
    }

    // MARK: GitHub

    func testGitHubLeavesOtherTypesAsQuotations() {
        for markdown in ["> [!faq]\n> Why?", "> [!hint]\n> Try this.", "> [!anything]\n> Text."] {
            let output = html(markdown, .github)
            XCTAssertFalse(output.contains("markdown-alert"), "\(markdown): \(output)")
            XCTAssertTrue(output.contains("<blockquote"), "\(markdown): \(output)")
        }
    }

    /// GitHub shows `> [!NOTE] Title` as a quotation, so the GitHub preview
    /// does too, keeping the text the author wrote.
    func testGitHubLeavesATitleOnTheTagLineAsAQuotation() {
        let output = html("> [!NOTE] My title\n> Body.", .github)
        XCTAssertFalse(output.contains("markdown-alert"), output)
        XCTAssertTrue(output.contains("My title"), output)
    }

    func testGitHubDoesNotFold() {
        for markdown in ["> [!NOTE]-\n> Body.", "> [!NOTE]+\n> Body."] {
            let output = html(markdown, .github)
            XCTAssertFalse(output.contains("markdown-alert"), "\(markdown): \(output)")
            XCTAssertFalse(output.contains("<details"), "\(markdown): \(output)")
        }
    }

    // MARK: The whole page

    /// The flavor reaches the formatter through the page renderer, and into
    /// footnotes, which are formatted separately.
    func testPageRendererAndFootnotesFollowTheFlavor() {
        let markdown = "> [!faq]\n> Why?\n\nSee[^1].\n\n[^1]: > [!tip] In a footnote\n    > Body."
        let extended = MarkdownHTML.render(markdown: markdown, markdownFlavor: .extended).html
        let github = MarkdownHTML.render(markdown: markdown, markdownFlavor: .github).html
        // The page's stylesheet names every kind, so look for the element.
        let question = "class=\"markdown-alert markdown-alert-question\""
        let tip = "class=\"markdown-alert markdown-alert-tip\""
        XCTAssertTrue(extended.contains(question))
        XCTAssertTrue(extended.contains(tip), "the footnote's tip is a callout when extended")
        XCTAssertFalse(github.contains(question))
        XCTAssertFalse(github.contains(tip), "the footnote's titled tip is a quotation on GitHub")
    }

    func testEditorPageCarriesTheFlavor() {
        for flavor in MarkdownFlavor.allCases {
            var configuration = EditorHTML.Configuration()
            configuration.markdownFlavor = flavor
            let page = EditorHTML.render(markdown: "x", editorJavaScript: "", configuration: configuration)
            XCTAssertTrue(page.contains("data-markdown-flavor=\"\(flavor.rawValue)\""), "\(flavor)")
        }
    }

    // MARK: Storage

    func testExtendedIsTheDefaultAndIsStoredAsNothing() throws {
        let defaults = try makeDefaults()
        XCTAssertEqual(MarkdownFlavorSetting.read(from: defaults), .extended)
        MarkdownFlavorSetting.write(.github, to: defaults)
        XCTAssertEqual(MarkdownFlavorSetting.read(from: defaults), .github)
        MarkdownFlavorSetting.write(.extended, to: defaults)
        XCTAssertNil(defaults.object(forKey: MarkdownFlavorSetting.defaultsKey))
    }

    func testUnknownStoredValueReadsAsTheDefault() throws {
        let defaults = try makeDefaults()
        defaults.set("commonmark-2030", forKey: MarkdownFlavorSetting.defaultsKey)
        XCTAssertEqual(MarkdownFlavorSetting.read(from: defaults), .extended)
    }

    private func makeDefaults() throws -> UserDefaults {
        let suiteName = "MarkdownFlavorTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        addTeardownBlock { UserDefaults(suiteName: suiteName)?.removePersistentDomain(forName: suiteName) }
        return defaults
    }
}
