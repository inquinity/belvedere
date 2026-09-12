import XCTest
@testable import MarkdownHelpers

/// The rules a granted remote image is fetched under.
///
/// The fetch itself needs a network and so is not tested here; what *is*
/// testable is everything that decides whether a request happens at all, and
/// that is where the mistakes would be.
final class RemoteImageRequestPolicyTests: XCTestCase {

    func testOnlyHTTPAndHTTPSAreEligible() {
        XCTAssertTrue(RemoteImageRequestPolicy.isEligible(URL(string: "https://example.com/a.png")!))
        XCTAssertTrue(RemoteImageRequestPolicy.isEligible(URL(string: "http://example.com/a.png")!))
        // Uppercase reaches us straight from document text.
        XCTAssertTrue(RemoteImageRequestPolicy.isEligible(URL(string: "HTTPS://example.com/a.png")!))
    }

    /// The interesting half. A `file:` URL arriving here would turn a remote
    /// grant into an unbounded local read, and a custom scheme would hand the
    /// click to whatever app registered it.
    func testEverythingElseIsRefusedBeforeARequestExists() {
        for raw in ["file:///etc/passwd",
                    "md-asset:///Users/someone/secret.png",
                    "ftp://example.com/a.png",
                    "javascript:alert(1)",
                    "data:image/png;base64,AAAA",
                    "https:///no-host.png",
                    "//example.com/protocol-relative.png"] {
            guard let url = URL(string: raw) else { continue }
            XCTAssertFalse(RemoteImageRequestPolicy.isEligible(url),
                           "\(raw) must not be fetchable")
        }
    }

    /// A redirect is a second URL the reader never saw, so it is held to the
    /// same rule as the first one.
    func testRedirectsAreHeldToTheSameRule() {
        XCTAssertTrue(RemoteImageRequestPolicy.allowsRedirect(to: URL(string: "https://cdn.example.com/a.png")!))
        XCTAssertFalse(RemoteImageRequestPolicy.allowsRedirect(to: URL(string: "file:///etc/passwd")!))
        XCTAssertFalse(RemoteImageRequestPolicy.allowsRedirect(to: URL(string: "customapp://open")!))
    }

    func testRedirectChainsAndTransfersAreBounded() {
        XCTAssertGreaterThan(RemoteImageRequestPolicy.maximumRedirects, 0)
        XCTAssertLessThanOrEqual(RemoteImageRequestPolicy.maximumRedirects, 5,
                                 "a long redirect chain is a tour of hosts the reader did not choose")
        XCTAssertLessThanOrEqual(RemoteImageRequestPolicy.timeout, 30,
                                 "a click must not be able to hang the placeholder indefinitely")
        XCTAssertEqual(RemoteImageRequestPolicy.maximumBytes, DeferredAssetLoader.defaultMaxBytes,
                       "a remote grant must not be allowed to pull more than a local one")
    }

    /// The request says who is asking rather than impersonating a browser.
    /// Volunteering a fake identity is its own kind of disclosure, and the
    /// version is public in every release anyway.
    func testUserAgentNamesTheAppAndItsVersion() {
        XCTAssertEqual(RemoteImageRequestPolicy.userAgent(name: "Belvedere", version: "1.2.2"),
                       "Belvedere/1.2.2")
        let agent = RemoteImageRequestPolicy.userAgent(name: "Belvedere", version: "1.2.2")
        XCTAssertFalse(agent.lowercased().contains("mozilla"),
                       "the fetch must not pretend to be a browser")
    }

    /// The refusal the page shows when a host does not answer. Without its own
    /// case it would be reported as "cannot read file", sending the reader to
    /// look for a local problem that does not exist.
    func testUnreachableIsItsOwnRefusal() {
        XCTAssertEqual(DeferredAssetLoader.Refusal.unreachable.rawValue, "unreachable")
        XCTAssertNotEqual(DeferredAssetLoader.Refusal.unreachable, .unreadable)
    }
}
