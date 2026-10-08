import XCTest
@testable import MarkdownHelpers

/// A file that changes on disk reloads by itself, unless the window holds
/// edits that are not saved; then the reader chooses.
final class DiskChangePolicyTests: XCTestCase {

    private func action(disk: String?, lastSaved: String? = "v1", local: String? = nil,
                        isEditing: Bool = false) -> DiskChangePolicy.Action {
        DiskChangePolicy.action(disk: disk, lastSaved: lastSaved, local: local, isEditing: isEditing)
    }

    func testAChangedFileReloadsTheOpenPreview() {
        XCTAssertEqual(action(disk: "v2"), .reloadPreview)
    }

    func testTheSameTextIsLeftAlone() {
        XCTAssertEqual(action(disk: "v1"), .ignore, "A touch, or this app's own save, changes nothing to show.")
        XCTAssertEqual(action(disk: "v1", local: "v1", isEditing: true), .ignore)
    }

    func testAnUnreadableFileIsLeftAloneUntilItComesBack() {
        XCTAssertEqual(action(disk: nil), .ignore)
        XCTAssertEqual(action(disk: nil, local: "my edits", isEditing: true), .ignore)
    }

    func testAnEditorWithNothingUnsavedTakesTheNewText() {
        XCTAssertEqual(action(disk: "v2", local: "v1", isEditing: true), .reloadEditor)
        XCTAssertEqual(action(disk: "v2", local: nil, isEditing: true), .reloadEditor)
    }

    func testUnsavedEditsAndADifferentFileAsksTheReader() {
        XCTAssertEqual(action(disk: "v2", local: "my edits", isEditing: true), .askWhatToDo)
    }

    func testAKeptDraftOutsideEditModeAsksToo() {
        XCTAssertEqual(action(disk: "v2", local: "my edits", isEditing: false), .askWhatToDo)
    }

    func testEditsThatEqualTheNewFileAreNotAConflict() {
        XCTAssertEqual(action(disk: "same", local: "same", isEditing: true), .reloadEditor)
        XCTAssertEqual(action(disk: "same", local: "same", isEditing: false), .reloadPreview)
    }

    func testEditsThatWereTypedAndRevertedAreNotUnsaved() {
        // The editor is back at the saved text, so the new disk text is simply adopted.
        XCTAssertEqual(action(disk: "v2", local: "v1", isEditing: true), .reloadEditor)
    }

    func testNoBaselineAtAllReloads() {
        XCTAssertEqual(action(disk: "v2", lastSaved: nil), .reloadPreview)
    }
}
