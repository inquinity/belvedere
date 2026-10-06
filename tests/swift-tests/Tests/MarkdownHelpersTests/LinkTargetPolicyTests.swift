import XCTest
@testable import MarkdownHelpers

/// What a clicked local link may open directly.
///
/// Every case here is a real file in a temporary folder, because the decision
/// rests on what the filesystem says about the target (symlinks, packages, the
/// execute bit, the type the system assigns), not on the URL's text. The
/// bypasses this guards against were all found by a guard that read only the
/// type of the path as written.
final class LinkTargetPolicyTests: XCTestCase {

    private var folder: URL!

    override func setUpWithError() throws {
        folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("LinkTargetPolicyTests-\(UUID().uuidString)", isDirectory: true)
            .resolvingSymlinksInPath()
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: folder)
    }

    // MARK: - Opened directly

    func testDisplayOnlyFilesOpen() throws {
        for name in ["photo.png", "photo.jpg", "scan.pdf", "notes.txt", "clip.mp4", "song.mp3", "data.csv"] {
            let file = try makeFile(name)
            assertOpens(file, file, name)
        }
    }

    func testPlainFolderOpens() throws {
        let plain = try makeFolder("assets")
        assertOpens(plain, plain)
    }

    // MARK: - Nothing there

    func testMissingTargetIsNotOpened() {
        let missing = folder.appendingPathComponent("not-there.png")
        XCTAssertEqual(LinkTargetPolicy.disposition(for: missing), .missing)
    }

    /// A symlink to nothing is something there that could not be classified.
    /// Opening it would hand over whatever it points to by then, unchecked.
    func testDanglingSymlinkIsRevealedNotOpened() throws {
        let link = folder.appendingPathComponent("picture.png")
        try FileManager.default.createSymbolicLink(
            at: link, withDestinationURL: folder.appendingPathComponent("gone.app"))
        assertReveals(link, link)
    }

    // MARK: - Shown in Finder

    /// The bypass that started this: the old guard saw `public.symlink`.
    func testSymlinkToAnAppIsRevealedAsTheApp() throws {
        let app = try makeApp("Tool.app")
        let link = folder.appendingPathComponent("notes.txt")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: app)
        assertReveals(link, app)
    }

    func testSymlinkToAnExecutableIsRevealed() throws {
        let tool = try makeFile("tool", executable: true)
        let link = folder.appendingPathComponent("readme.txt")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: tool)
        assertReveals(link, tool)
    }

    /// A symlink to something harmless opens the target, not the link: what
    /// was checked is what is opened.
    func testSymlinkToAnImageOpensTheResolvedTarget() throws {
        let image = try makeFile("real.png")
        let link = folder.appendingPathComponent("alias.png")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: image)
        assertOpens(link, image)
    }

    /// File types the old denylist let through. None needs an execute bit.
    func testLaunchersAndInstallersAreRevealed() throws {
        for name in ["setup.terminal", "target.fileloc", "target.inetloc", "target.webloc",
                     "tool.jar", "setup.command", "setup.sh", "script.py", "script.applescript",
                     "profile.mobileconfig", "bundle.mpkg", "setup.pkg", "disk.dmg",
                     "page.html", "drawing.svg", "report.docx", "archive.zip", "unknown.xyz"] {
            let file = try makeFile(name)
            assertReveals(file, file, name)
        }
    }

    func testPackagesAreRevealed() throws {
        let app = try makeApp("Tool.app")
        assertReveals(app, app)
        for name in ["Pane.prefPane", "Flow.workflow"] {
            let bundle = try makeFolder(name)
            try makeFolder("\(name)/Contents")
            assertReveals(bundle, bundle, name)
        }
    }

    /// A per-file "Open With" choice overrides the type's app when the file is
    /// opened, so a `.png` can name Terminal. The attribute's value does not
    /// matter; carrying one at all is enough.
    func testFileThatNamesItsOwnAppIsRevealed() throws {
        for name in ["diagram.png", "notes.txt", "scan.pdf"] {
            let file = try makeFile(name)
            let value = Data("bplist00".utf8)
            let status = value.withUnsafeBytes {
                setxattr(file.path, LinkTargetPolicy.openWithAttribute, $0.baseAddress, value.count, 0, 0)
            }
            XCTAssertEqual(status, 0, "could not set the attribute on \(name)")
            assertReveals(file, file, name)
        }
    }

    func testPlaylistsAreRevealed() throws {
        for name in ["list.m3u", "list.m3u8"] {
            let file = try makeFile(name)
            assertReveals(file, file, name)
        }
    }

    /// The execute bit wins over a harmless-looking name.
    func testExecutableBitIsRevealedWhateverTheName() throws {
        let file = try makeFile("notes.txt", executable: true)
        assertReveals(file, file)
    }

    // MARK: - Helpers

    /// Compared by path: a resolved directory URL may differ from the one the
    /// test built only in its trailing slash.
    private func assertOpens(_ link: URL, _ expected: URL, _ message: String = "",
                             file: StaticString = #filePath, line: UInt = #line) {
        guard case let .open(target) = LinkTargetPolicy.disposition(for: link) else {
            return XCTFail("expected open: \(message) \(link.path)", file: file, line: line)
        }
        XCTAssertEqual(target.path, expected.path, message, file: file, line: line)
    }

    private func assertReveals(_ link: URL, _ expected: URL, _ message: String = "",
                               file: StaticString = #filePath, line: UInt = #line) {
        guard case let .reveal(target) = LinkTargetPolicy.disposition(for: link) else {
            return XCTFail("expected reveal: \(message) \(link.path)", file: file, line: line)
        }
        XCTAssertEqual(target.path, expected.path, message, file: file, line: line)
    }

    @discardableResult
    private func makeFile(_ name: String, executable: Bool = false) throws -> URL {
        let url = folder.appendingPathComponent(name)
        try Data("x".utf8).write(to: url)
        if executable {
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        }
        return url
    }

    @discardableResult
    private func makeFolder(_ name: String) throws -> URL {
        let url = folder.appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url.standardizedFileURL
    }

    /// A minimal bundle macOS recognises as an application.
    private func makeApp(_ name: String) throws -> URL {
        let app = try makeFolder(name)
        try makeFolder("\(name)/Contents/MacOS")
        try makeFile("\(name)/Contents/MacOS/Tool", executable: true)
        let plist: [String: Any] = ["CFBundleExecutable": "Tool", "CFBundlePackageType": "APPL"]
        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        try data.write(to: app.appendingPathComponent("Contents/Info.plist"))
        return app
    }
}
