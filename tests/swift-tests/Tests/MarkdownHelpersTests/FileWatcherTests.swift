import XCTest
@testable import MarkdownHelpers

/// The watcher has to keep working however a tool writes the file. One case
/// used to leave it deaf for good: the file deleted, then written again more
/// than a quarter of a second later.
@MainActor
final class FileWatcherTests: XCTestCase {
    private var directory: URL!
    private var file: URL!
    private var watcher: FileWatcher!
    private var changes = 0

    override func setUp() async throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("file-watcher-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        file = directory.appendingPathComponent("note.md")
        try "one\n".write(to: file, atomically: false, encoding: .utf8)
        changes = 0
        watcher = FileWatcher(url: file) { [weak self] in self?.changes += 1 }
    }

    override func tearDown() async throws {
        watcher.cancel()
        try? FileManager.default.removeItem(at: directory)
    }

    /// Runs `change`, then waits for the watcher to report at least once.
    private func expectChange(_ name: String, timeout: TimeInterval = 4, _ change: () throws -> Void,
                              file: StaticString = #filePath, line: UInt = #line) async throws {
        let before = changes
        try change()
        let deadline = Date().addingTimeInterval(timeout)
        while changes == before, Date() < deadline {
            try await Task.sleep(for: .milliseconds(50))
        }
        XCTAssertGreaterThan(changes, before, "\(name): the change was not detected", file: file, line: line)
    }

    func testInPlaceWrite() async throws {
        try await expectChange("append") {
            let handle = try FileHandle(forWritingTo: file)
            handle.seekToEndOfFile()
            handle.write(Data("two\n".utf8))
            try handle.close()
        }
        try await expectChange("rewrite") { try "three\n".write(to: file, atomically: false, encoding: .utf8) }
    }

    func testAtomicReplacementsKeepBeingDetected() async throws {
        for text in ["a", "b", "c"] {
            try await expectChange("atomic replace \(text)") { try text.write(to: file, atomically: true, encoding: .utf8) }
        }
    }

    func testDeleteAndQuickRecreate() async throws {
        try await expectChange("delete, recreate after 100 ms") {
            try FileManager.default.removeItem(at: file)
            Thread.sleep(forTimeInterval: 0.1)
            try "back\n".write(to: file, atomically: false, encoding: .utf8)
        }
        try await expectChange("write after") { try "more\n".write(to: file, atomically: false, encoding: .utf8) }
    }

    func testDeleteThenRecreateMuchLater() async throws {
        try FileManager.default.removeItem(at: file)
        try await Task.sleep(for: .milliseconds(900))
        try await expectChange("recreated after 900 ms") { try "late\n".write(to: file, atomically: false, encoding: .utf8) }
        try await expectChange("write after the late recreate") { try "later\n".write(to: file, atomically: false, encoding: .utf8) }
    }

    func testMovedAsideAndANewFileAtThePath() async throws {
        try await expectChange("moved aside, new file") {
            try FileManager.default.moveItem(at: file, to: directory.appendingPathComponent("note.md~"))
            try "new\n".write(to: file, atomically: false, encoding: .utf8)
        }
        try await expectChange("write after") { try "newer\n".write(to: file, atomically: false, encoding: .utf8) }
    }

    func testACancelledWatcherStaysQuiet() async throws {
        watcher.cancel()
        let before = changes
        try "ignored\n".write(to: file, atomically: false, encoding: .utf8)
        try await Task.sleep(for: .milliseconds(600))
        XCTAssertEqual(changes, before)
    }
}
