import XCTest
@testable import MarkdownHelpers

/// Belvedere through 1.2.4 saved its shared settings in the app's own
/// container, because it was not entitled to the app group its code named.
/// Upgrading must carry them into the group without clobbering anything the
/// reader has set since.
final class LegacySharedSettingsMigrationTests: XCTestCase {

    private var suiteName = ""
    private var shared: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "belvedere.test.\(UUID().uuidString)"
        shared = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        shared.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    func testCopiesEverySettingTheGroupDoesNotHave() {
        let copied = LegacySharedSettingsMigration.migrate([
            "MarkdownPreview.appearance": "dark",
            "MarkdownPreview.documentFont": "charter",
            "MarkdownPreview.readerLayout.lineSpacing": 1.6,
        ], into: shared)
        XCTAssertEqual(copied, ["MarkdownPreview.appearance",
                                "MarkdownPreview.documentFont",
                                "MarkdownPreview.readerLayout.lineSpacing"])
        XCTAssertEqual(shared.string(forKey: "MarkdownPreview.documentFont"), "charter")
        XCTAssertEqual(shared.double(forKey: "MarkdownPreview.readerLayout.lineSpacing"), 1.6)
    }

    func testNeverOverwritesAValueChosenAfterUpgrading() {
        shared.set("light", forKey: "MarkdownPreview.appearance")
        let copied = LegacySharedSettingsMigration.migrate(["MarkdownPreview.appearance": "dark"], into: shared)
        XCTAssertEqual(copied, [])
        XCTAssertEqual(shared.string(forKey: "MarkdownPreview.appearance"), "light")
    }

    func testCopiesOnlyTheAppsOwnSettings() {
        let copied = LegacySharedSettingsMigration.migrate([
            "NSWindow Frame main": "0 0 100 100",
            LegacySharedSettingsMigration.completedKey: true,
            "MarkdownPreview.theme.appliedPreset": "Paper",
        ], into: shared)
        XCTAssertEqual(copied, ["MarkdownPreview.theme.appliedPreset"])
        XCTAssertNil(shared.object(forKey: "NSWindow Frame main"))
        XCTAssertFalse(shared.bool(forKey: LegacySharedSettingsMigration.completedKey))
    }
}
