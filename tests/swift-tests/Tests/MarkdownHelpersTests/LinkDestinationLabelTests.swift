import XCTest
@testable import MarkdownHelpers

/// The link-destination bar shows where a link goes, from its resolved address.
/// It must never be made to read differently from that address.
final class LinkDestinationLabelTests: XCTestCase {

    private func text(_ string: String, fragment: String? = nil) -> String? {
        LinkDestinationLabel.text(for: URL(string: string)!, sameDocumentFragment: fragment)
    }

    func testAWebLinkShowsItsFullAddress() {
        XCTAssertEqual(text("https://example.com/docs/page?x=1#top"), "https://example.com/docs/page?x=1#top")
    }

    func testUserInfoIsShownSoADisguisedHostReadsAsWhatItIs() {
        XCTAssertEqual(text("https://paypal.com@evil.test/login"), "https://paypal.com@evil.test/login")
    }

    func testAnInternationalisedHostShowsAsPunycode() {
        // Safari and WebKit hand over `href` already in punycode, so a
        // look-alike Cyrillic "a" cannot pass for the Latin one.
        XCTAssertEqual(text("https://xn--pple-43d.com/"), "https://xn--pple-43d.com/")
    }

    func testMailtoIsShownAsSuch() {
        XCTAssertEqual(text("mailto:someone@example.com"), "mailto:someone@example.com")
    }

    func testARelativeLinkShowsTheFileItResolvesTo() {
        XCTAssertEqual(text("md-asset:///Users/me/notes/other.md"), "/Users/me/notes/other.md")
        XCTAssertEqual(text("md-asset:///Users/me/notes/other.md#part"), "/Users/me/notes/other.md#part")
    }

    func testAFileLinkShowsItsPath() {
        XCTAssertEqual(text("file:///Users/me/a.md"), "/Users/me/a.md")
    }

    func testALinkWithinTheDocumentShowsOnlyTheSection() {
        XCTAssertEqual(text("md-asset:///Users/me/notes/#install", fragment: "install"), "#install")
    }

    func testTheReservedVendorNamespaceShowsNothing() {
        XCTAssertNil(text("md-asset:///__vendor/mermaid.js"))
    }

    func testALongAddressKeepsItsHostAndLosesTheMiddleOfThePath() throws {
        let path = String(repeating: "segment/", count: 40)
        let shown = try XCTUnwrap(text("https://docs.example.org/\(path)final-page.html"))
        XCTAssertLessThanOrEqual(shown.count, LinkDestinationLabel.maxLength)
        XCTAssertTrue(shown.hasPrefix("https://docs.example.org/seg"), shown)
        XCTAssertTrue(shown.hasSuffix("final-page.html"), shown)
        XCTAssertTrue(shown.contains("…"), shown)
    }

    func testAHostLongerThanTheLimitIsStillShownWhole() throws {
        let host = String(repeating: "a", count: 60) + "." + String(repeating: "b", count: 60) + ".example"
        let shown = try XCTUnwrap(text("https://\(host)/some/long/path/that/would/be/cut/\(String(repeating: "x", count: 80))"))
        XCTAssertTrue(shown.hasPrefix("https://\(host)"), shown)
    }

    func testAShortAddressIsNeverTouched() {
        let address = "https://example.com/" + String(repeating: "p", count: 60)
        XCTAssertEqual(text(address), address)
    }

    func testAPathLosesItsMiddleAndKeepsTheFileName() throws {
        let path = "/Users/me/" + String(repeating: "folder/", count: 30) + "target.md"
        let shown = try XCTUnwrap(text("file://" + path))
        XCTAssertLessThanOrEqual(shown.count, LinkDestinationLabel.maxLength)
        XCTAssertTrue(shown.hasPrefix("/Users/me/"), shown)
        XCTAssertTrue(shown.hasSuffix("target.md"), shown)
    }

    func testLongUserInfoCannotPushTheRealHostOffTheEnd() throws {
        let userInfo = "paypal.com:" + String(repeating: "x", count: 90)
        let shown = try XCTUnwrap(text("https://\(userInfo)@evil.test/login"))
        XCTAssertTrue(shown.hasPrefix("https://"), shown)
        XCTAssertTrue(shown.contains("@evil.test/login"), shown)
        XCTAssertLessThan(shown.distance(from: shown.startIndex, to: try XCTUnwrap(shown.range(of: "@evil.test")).lowerBound), 40, shown)
    }

    func testAHugeSectionNameIsCapped() throws {
        let shown = try XCTUnwrap(text("md-asset:///Users/me/#x", fragment: String(repeating: "a", count: 5_000_000)))
        XCTAssertLessThanOrEqual(shown.count, LinkDestinationLabel.maxLength)
    }

    func testControlAndBidirectionalCharactersAreReplaced() throws {
        let hidden = "https://example.com/\u{202E}gpj.exe"      // right-to-left override
        let shown = try XCTUnwrap(LinkDestinationLabel.text(for: URL(string: "https://example.com/x")!,
                                                            sameDocumentFragment: "a\u{202E}b\u{0007}c"))
        XCTAssertEqual(shown, "#a\u{FFFD}b\u{FFFD}c")
        XCTAssertFalse(hidden.isEmpty)
    }
}
