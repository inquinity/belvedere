import Foundation
import XCTest
@testable import MarkdownHelpers

/// Guards the check standing between a click and an arbitrary file read.
///
/// **What a failure here means:** the placeholder's Load button can be made to
/// read something that is not an image. The click is the only gate — document
/// content cannot synthesise it, because the sanitiser strips scripts and the
/// CSP forbids them — so what the gate admits is the whole security property.
final class DeferredAssetLoaderTests: XCTestCase {

    private let png = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A] + Array(repeating: 0, count: 32))
    private let jpeg = Data([0xFF, 0xD8, 0xFF, 0xE0] + Array(repeating: 0, count: 32))

    // MARK: - What must be refused

    func testTextIsRefusedEvenThoughItIsReadable() {
        let passwd = Data("root:x:0:0:root:/root:/bin/sh\n".utf8)
        XCTAssertEqual(
            DeferredAssetLoader.outcome(for: passwd), .refused(.notAnImage),
            """
            A text file was accepted as an image. The placeholder would then \
            read arbitrary files on a single click.
            """
        )
    }

    func testRenamingAFileDoesNotMakeItEligible() {
        // The path says .png; the bytes say otherwise. Bytes win.
        let disguised = Data("root:x:0:0:root:/root:/bin/sh\n".utf8)
        XCTAssertEqual(
            DeferredAssetLoader.outcome(forFileAt: "/tmp/passwd.png", reader: { _ in disguised }),
            .refused(.notAnImage),
            "Eligibility must come from magic bytes, not the extension, which document content chooses."
        )
    }

    func testOversizeIsRefusedBeforeEncoding() {
        let big = png + Data(repeating: 0, count: 4096)
        XCTAssertEqual(
            DeferredAssetLoader.outcome(for: big, maxBytes: 1024), .refused(.tooLarge),
            "A click must not be able to pull an unbounded file into memory and base64 it."
        )
    }

    func testUnreadableFileIsRefusedRatherThanCrashing() {
        XCTAssertEqual(
            DeferredAssetLoader.outcome(forFileAt: "/nonexistent/nope.png",
                                        reader: { _ in throw CocoaError(.fileReadNoSuchFile) }),
            .refused(.unreadable)
        )
    }

    /// SVG is excluded deliberately — it is a document format, not a raster.
    func testSVGIsNotEligible() {
        let svg = Data("<svg xmlns=\"http://www.w3.org/2000/svg\"><circle r=\"1\"/></svg>".utf8)
        XCTAssertEqual(DeferredAssetLoader.outcome(for: svg), .refused(.notAnImage))
    }

    // MARK: - What must be allowed

    func testPNGLoadsAsADataURL() {
        guard case let .loaded(url) = DeferredAssetLoader.outcome(for: png) else {
            return XCTFail("a real PNG must be eligible")
        }
        XCTAssertTrue(url.hasPrefix("data:image/png;base64,"))
    }

    func testJPEGLoads() {
        guard case let .loaded(url) = DeferredAssetLoader.outcome(for: jpeg) else {
            return XCTFail("a real JPEG must be eligible")
        }
        XCTAssertTrue(url.hasPrefix("data:image/jpeg;base64,"))
    }

    func testRasterFormatsAreRecognised() {
        let cases: [(String, [UInt8])] = [
            ("image/gif",  [0x47, 0x49, 0x46, 0x38, 0x39, 0x61]),
            ("image/bmp",  [0x42, 0x4D, 0x00, 0x00]),
            ("image/tiff", [0x49, 0x49, 0x2A, 0x00]),
            ("image/webp", [0x52, 0x49, 0x46, 0x46, 0, 0, 0, 0, 0x57, 0x45, 0x42, 0x50]),
            ("image/heic", [0, 0, 0, 0, 0x66, 0x74, 0x79, 0x70, 0x68, 0x65, 0x69, 0x63]),
            ("image/avif", [0, 0, 0, 0, 0x66, 0x74, 0x79, 0x70, 0x61, 0x76, 0x69, 0x66]),
        ]
        for (mime, bytes) in cases {
            XCTAssertEqual(DeferredAssetLoader.imageMIMEType(of: Data(bytes)), mime, mime)
        }
    }

    func testEmptyAndTruncatedInputAreRefusedWithoutReadingPastTheEnd() {
        XCTAssertNil(DeferredAssetLoader.imageMIMEType(of: Data()))
        XCTAssertNil(DeferredAssetLoader.imageMIMEType(of: Data([0x89, 0x50])))
        XCTAssertNil(DeferredAssetLoader.imageMIMEType(of: Data([0x52, 0x49, 0x46, 0x46])))
    }
}

/// The URL a granted click resolves to. This is where F4's worst bug lived:
/// the page sent the raw `src` attribute, so the host received a relative path
/// and answered "unavailable" for every image the reader asked for.
final class DeferredAssetPathTests: XCTestCase {

    private let scheme = "md-asset"

    func testResolvedSchemeURLYieldsItsPath() {
        let url = URL(string: "md-asset:///Users/me/notes/images/logo.png")!
        XCTAssertEqual(DeferredAssetLoader.localPath(for: url, scheme: scheme),
                       "/Users/me/notes/images/logo.png")
    }

    func testFileURLYieldsItsPath() {
        let url = URL(fileURLWithPath: "/Users/me/notes/logo.png")
        XCTAssertEqual(DeferredAssetLoader.localPath(for: url, scheme: scheme),
                       "/Users/me/notes/logo.png")
    }

    func testRelativeReferenceIsRefusedRatherThanGuessedAt() {
        let url = URL(string: "../images/logo.png")!
        XCTAssertNil(
            DeferredAssetLoader.localPath(for: url, scheme: scheme),
            """
            A relative reference was accepted. It means nothing on this side, \
            so resolving it would produce a path relative to the process \
            working directory — a file the document never named.
            """
        )
    }

    func testRemoteURLsAreNotServed() {
        for s in ["https://example.com/pixel.png", "http://example.com/pixel.png"] {
            XCTAssertNil(
                DeferredAssetLoader.localPath(for: URL(string: s)!, scheme: scheme),
                "fetching remote content would disclose the reader to the document's author"
            )
        }
    }

    func testSchemeURLCarryingAHostIsRefused() {
        let url = URL(string: "md-asset://evil.example/etc/passwd")!
        XCTAssertNil(DeferredAssetLoader.localPath(for: url, scheme: scheme),
                     "a host makes it someone else's file, not one on this disk")
    }

    func testBareRootIsRefused() {
        XCTAssertNil(DeferredAssetLoader.localPath(for: URL(string: "md-asset:///")!, scheme: scheme))
    }
}
