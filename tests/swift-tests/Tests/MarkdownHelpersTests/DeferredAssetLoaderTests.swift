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
            DeferredAssetLoader.outcome(forFileAt: "/tmp/passwd.png",
                                        exists: { _ in true },
                                        reader: { _ in disguised }),
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

    func testAbsentFileIsRefusedRatherThanCrashing() {
        XCTAssertEqual(
            DeferredAssetLoader.outcome(forFileAt: "/nonexistent/nope.png",
                                        reader: { _ in throw CocoaError(.fileReadNoSuchFile) }),
            .refused(.missing),
            "an absent file is missing, not unreadable — see DeferredAssetMissingTests"
        )
    }

    /// The SVG check is lexical and refuses whatever it does not recognise.
    /// Each of these would need the check to understand more XML than it does,
    /// or is simply not an SVG document.
    func testThingsThatAreNotPlainlySVGAreRefused() {
        let cases: [(String, String)] = [
            ("an HTML page containing an svg",
             "<!DOCTYPE html><html><body><svg xmlns=\"http://www.w3.org/2000/svg\"/></body></html>"),
            ("a DOCTYPE with an internal subset, where entities are declared",
             "<?xml version=\"1.0\"?><!DOCTYPE svg [<!ENTITY a \"aaaa\">]><svg>&a;</svg>"),
            ("a namespace-prefixed root",
             "<svg:svg xmlns:svg=\"http://www.w3.org/2000/svg\"/>"),
            ("an element that merely starts with svg", "<svgfoo/>"),
            ("text before the root", "hello <svg/>"),
            ("an unterminated comment", "<!-- <svg/>"),
            ("an unterminated processing instruction", "<?xml version=\"1.0\" <svg/>"),
            ("a root cut off at the end of the bytes", "<svg"),
            ("a bare word", "svg"),
        ]
        for (name, text) in cases {
            XCTAssertEqual(DeferredAssetLoader.outcome(for: Data(text.utf8)), .refused(.notAnImage), name)
        }
    }

    func testOversizeSVGIsRefusedLikeAnyOtherImage() {
        let big = Data(("<svg>" + String(repeating: " ", count: 4096) + "</svg>").utf8)
        XCTAssertEqual(DeferredAssetLoader.outcome(for: big, maxBytes: 1024), .refused(.tooLarge))
    }

    /// Conservative on purpose: XML spells it upper-case, and a refusal costs
    /// a badge, where a misreading could cost more.
    func testLowerCaseDoctypeAndBracketsInADoctypeAreRefused() {
        for text in ["<!doctype svg><svg/>", "<!DOCTYPE svg SYSTEM \"a[b].dtd\"><svg/>"] {
            XCTAssertNil(DeferredAssetLoader.imageMIMEType(of: Data(text.utf8)), text)
        }
    }

    func testSVGRootJustInsideThePrologueLimitIsRecognised() {
        let limit = DeferredAssetLoader.svgPrologueLimit
        let padded = String(repeating: " ", count: limit - 5) + "<svg/>"
        XCTAssertEqual(DeferredAssetLoader.imageMIMEType(of: Data(padded.utf8)), "image/svg+xml")
        let cut = String(repeating: " ", count: limit - 4) + "<svg/>"
        XCTAssertNil(DeferredAssetLoader.imageMIMEType(of: Data(cut.utf8)),
                     "the byte after <svg falls past the limit, so the root cannot be confirmed")
    }

    func testUTF16SVGIsRefused() {
        let utf16 = "<svg xmlns=\"http://www.w3.org/2000/svg\"/>".data(using: .utf16)!
        XCTAssertNil(DeferredAssetLoader.imageMIMEType(of: utf16))
    }

    func testSVGRootBeyondThePrologueLimitIsRefused() {
        let padding = "<!--" + String(repeating: "x", count: DeferredAssetLoader.svgPrologueLimit) + "-->"
        XCTAssertNil(
            DeferredAssetLoader.imageMIMEType(of: Data((padding + "<svg/>").utf8)),
            "the check must stop at its limit rather than scan an arbitrarily long prologue"
        )
    }

    // MARK: - What must be allowed

    func testPNGLoadsAsADataURL() {
        guard case let .loaded(url) = DeferredAssetLoader.outcome(for: png) else {
            return XCTFail("a real PNG must be eligible")
        }
        XCTAssertTrue(url.hasPrefix("data:image/png;base64,"))
    }

    /// A local file outside the folder is granted on the same terms as a
    /// remote one; the extension still decides nothing.
    func testLocalSVGOutsideTheFolderLoadsOnItsBytes() {
        let svg = Data("<?xml version=\"1.0\"?>\n<svg xmlns=\"http://www.w3.org/2000/svg\"/>".utf8)
        guard case let .loaded(url) = DeferredAssetLoader.outcome(forFileAt: "/elsewhere/logo.txt",
                                                                  exists: { _ in true },
                                                                  reader: { _ in svg }) else {
            return XCTFail("a local SVG must be eligible on its bytes")
        }
        XCTAssertTrue(url.hasPrefix("data:image/svg+xml;base64,"))
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

    /// Badges from shields.io and similar services are SVG. A page shows a
    /// granted image only through `<img>`, where WebKit runs no SVG script and
    /// loads nothing the SVG names.
    func testSVGDocumentsAreRecognised() {
        let cases: [(String, String)] = [
            ("a bare root", "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"90\" height=\"20\"></svg>"),
            ("a self-closing root", "<svg/>"),
            ("a root followed by a newline", "<svg\n xmlns=\"http://www.w3.org/2000/svg\"/>"),
            ("an XML declaration", "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<svg/>"),
            ("a comment", "<!-- Generator: Sketch -->\n<svg/>"),
            ("an external DOCTYPE",
             "<?xml version=\"1.0\"?>\n<!DOCTYPE svg PUBLIC \"-//W3C//DTD SVG 1.1//EN\" "
                + "\"http://www.w3.org/Graphics/SVG/1.1/DTD/svg11.dtd\">\n<svg/>"),
            ("leading whitespace", "  \r\n\t<svg/>"),
        ]
        for (name, text) in cases {
            XCTAssertEqual(DeferredAssetLoader.imageMIMEType(of: Data(text.utf8)), "image/svg+xml", name)
        }
        let withBOM = Data([0xEF, 0xBB, 0xBF]) + Data("<svg/>".utf8)
        XCTAssertEqual(DeferredAssetLoader.imageMIMEType(of: withBOM), "image/svg+xml", "a UTF-8 byte-order mark")
    }

    /// The data URL is spliced into a single-quoted JavaScript string by the
    /// host. SVG is text and can hold a quote or a `</script>`; only base64
    /// keeps them out of that string.
    func testSVGDataURLIsBase64AndCannotCloseAJavaScriptString() {
        let hostile = Data("<svg onload=\"alert('x')\"><script>'</script></svg>".utf8)
        guard case let .loaded(url) = DeferredAssetLoader.outcome(for: hostile) else {
            return XCTFail("an SVG document must be eligible")
        }
        XCTAssertTrue(url.hasPrefix("data:image/svg+xml;base64,"))
        let payload = url.dropFirst("data:image/svg+xml;base64,".count)
        XCTAssertTrue(payload.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || "+/=".contains($0)) },
                      "the payload must be pure base64")
    }

    func testEmptyAndTruncatedInputAreRefusedWithoutReadingPastTheEnd() {
        XCTAssertNil(DeferredAssetLoader.imageMIMEType(of: Data()))
        XCTAssertNil(DeferredAssetLoader.imageMIMEType(of: Data([0x89, 0x50])))
        XCTAssertNil(DeferredAssetLoader.imageMIMEType(of: Data([0x52, 0x49, 0x46, 0x46])))
    }
}

/// The URL a granted click resolves to. This is where F2's worst bug lived:
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

/// Absence reported separately from unreadability. Telling a reader "cannot
/// read file" for a file that is not there sends them hunting a permissions
/// problem that does not exist.
final class DeferredAssetMissingTests: XCTestCase {

    private let png = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A] + Array(repeating: 0, count: 8))

    func testAbsentFileReportsMissing() {
        XCTAssertEqual(
            DeferredAssetLoader.outcome(forFileAt: "/nope/gone.png",
                                        exists: { _ in false },
                                        reader: { _ in throw CocoaError(.fileReadNoSuchFile) }),
            .refused(.missing)
        )
    }

    func testPresentButUnreadableFileReportsUnreadable() {
        XCTAssertEqual(
            DeferredAssetLoader.outcome(forFileAt: "/locked/secret.png",
                                        exists: { _ in true },
                                        reader: { _ in throw CocoaError(.fileReadNoPermission) }),
            .refused(.unreadable),
            "a file that exists but cannot be opened is a different problem from one that is absent"
        )
    }

    func testPresentTextFileStillReportsNotAnImage() {
        XCTAssertEqual(
            DeferredAssetLoader.outcome(forFileAt: "/tmp/passwd.png",
                                        exists: { _ in true },
                                        reader: { _ in Data("root:x:0:0".utf8) }),
            .refused(.notAnImage)
        )
    }

    // MARK: - In-folder classification

    func testInFolderReasonIsNilWhenTheFileWouldHaveLoaded() {
        XCTAssertNil(
            DeferredAssetLoader.reasonForInFolderFailure(atPath: "/doc/ok.png",
                                                         exists: { _ in true },
                                                         reader: { _ in self.png }),
            """
            A file that is present and valid has no explanation to give. \
            Inventing one would be worse than admitting WebKit declined it \
            for a reason of its own.
            """
        )
    }

    func testInFolderReasonDistinguishesMissingFromUnreadable() {
        XCTAssertEqual(
            DeferredAssetLoader.reasonForInFolderFailure(atPath: "/doc/gone.png",
                                                         exists: { _ in false },
                                                         reader: { _ in Data() }),
            .missing
        )
        XCTAssertEqual(
            DeferredAssetLoader.reasonForInFolderFailure(atPath: "/doc/locked.png",
                                                         exists: { _ in true },
                                                         reader: { _ in throw CocoaError(.fileReadNoPermission) }),
            .unreadable
        )
    }
}

// MARK: - Reading only what is safe to read

final class DeferredAssetSafeReadTests: XCTestCase {

    private let png = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A] + Array(repeating: 0, count: 8))

    private func makeFolder() throws -> URL {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    func testARegularImageLoads() throws {
        let folder = try makeFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let image = folder.appendingPathComponent("ok.png")
        try png.write(to: image)
        guard case .loaded = DeferredAssetLoader.outcome(forFileAt: image.path) else {
            return XCTFail("a small regular PNG must load")
        }
    }

    /// An oversized file is refused from its size alone. Reading it first and
    /// then checking would already have pulled it into memory.
    func testAnOversizedFileIsRefusedBeforeReading() throws {
        let folder = try makeFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let big = folder.appendingPathComponent("big.png")
        try (png + Data(repeating: 0, count: 4096)).write(to: big)
        XCTAssertEqual(DeferredAssetLoader.outcome(forFileAt: big.path, maxBytes: 1024), .refused(.tooLarge))
    }

    /// A FIFO would block `open`, and then never reach end of file. Both
    /// callers run on the main thread, so this is a hang, not a slow read.
    func testAFIFOIsRefusedWithoutBlocking() throws {
        let folder = try makeFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let fifo = folder.appendingPathComponent("pipe.png")
        XCTAssertEqual(mkfifo(fifo.path, 0o600), 0)
        let started = Date()
        XCTAssertEqual(DeferredAssetLoader.outcome(forFileAt: fifo.path), .refused(.unreadable))
        XCTAssertLessThan(Date().timeIntervalSince(started), 1)
    }

    /// The failure explainer judges containment by the scheme handler's rule.
    /// `..%2F` decodes to a real `..` only after a string-prefix test, so it
    /// must be the resolved URL that is checked, not the path text.
    func testAnEncodedParentEscapeIsOutsideTheBoundary() throws {
        let folder = try makeFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let escape = URL(string: "md-asset://" + folder.path + "/..%2F..%2F..%2Fetc%2Fpasswd")!
        XCTAssertNil(MarkdownAssetResolution.fileURL(for: escape, containedIn: folder))
    }
}
