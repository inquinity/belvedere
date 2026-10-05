import XCTest
@testable import MarkdownHelpers

/// 1.x saved every setting under `MarkdownPreview.`; 2.0 uses `belvedere.`.
/// Upgrading must carry each value across, and never clobber a newer one.
final class SettingsKeyMigrationTests: XCTestCase {

    private var suiteName = ""
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "belvedere.test.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    func testRenamesEverySettingAndKeepsItsValue() {
        defaults.set("dark", forKey: "MarkdownPreview.appearance")
        defaults.set(true, forKey: "MarkdownPreview.strictLineBreaks")
        defaults.set(1.6, forKey: "MarkdownPreview.readerLayout.lineSpacing")
        defaults.set(Data([1, 2, 3]), forKey: "MarkdownPreview.theme.savedLook.v1.paper")

        let written = SettingsKeyMigration.migrate(defaults, domain: suiteName)

        XCTAssertEqual(written, ["belvedere.appearance", "belvedere.readerLayout.lineSpacing",
                                 "belvedere.strictLineBreaks", "belvedere.theme.savedLook.v1.paper"])
        XCTAssertEqual(defaults.string(forKey: "belvedere.appearance"), "dark")
        XCTAssertEqual(defaults.object(forKey: "belvedere.strictLineBreaks") as? Bool, true)
        XCTAssertEqual(defaults.double(forKey: "belvedere.readerLayout.lineSpacing"), 1.6)
        XCTAssertEqual(defaults.data(forKey: "belvedere.theme.savedLook.v1.paper"), Data([1, 2, 3]))
    }

    func testRemovesTheOldKeys() {
        defaults.set("dark", forKey: "MarkdownPreview.appearance")
        SettingsKeyMigration.migrate(defaults, domain: suiteName)
        XCTAssertNil(defaults.persistentDomain(forName: suiteName)?["MarkdownPreview.appearance"])
    }

    func testAValueSavedAfterUpgradingWins() {
        defaults.set("dark", forKey: "MarkdownPreview.appearance")
        defaults.set("light", forKey: "belvedere.appearance")
        let written = SettingsKeyMigration.migrate(defaults, domain: suiteName)
        XCTAssertEqual(written, [])
        XCTAssertEqual(defaults.string(forKey: "belvedere.appearance"), "light")
        XCTAssertNil(defaults.persistentDomain(forName: suiteName)?["MarkdownPreview.appearance"],
                     "The old key is still removed.")
    }

    func testRunningTwiceChangesNothing() {
        defaults.set("dark", forKey: "MarkdownPreview.appearance")
        SettingsKeyMigration.migrate(defaults, domain: suiteName)
        XCTAssertEqual(SettingsKeyMigration.migrate(defaults, domain: suiteName), [])
        XCTAssertEqual(defaults.string(forKey: "belvedere.appearance"), "dark")
    }

    func testLeavesOtherKeysAlone() {
        defaults.set("x", forKey: "NSWindow Frame main")
        defaults.set("y", forKey: "MainSplitView.didSeedInitialState")
        defaults.set("z", forKey: "belvedere.contentWidth")
        XCTAssertEqual(SettingsKeyMigration.migrate(defaults, domain: suiteName), [])
        XCTAssertEqual(defaults.string(forKey: "NSWindow Frame main"), "x")
        XCTAssertEqual(defaults.string(forKey: "MainSplitView.didSeedInitialState"), "y")
        XCTAssertEqual(defaults.string(forKey: "belvedere.contentWidth"), "z")
    }

    /// A launch argument lives in the argument domain; it must not be copied
    /// into saved settings.
    func testIgnoresLaunchArguments() {
        let standard = UserDefaults.standard
        let original = standard.volatileDomain(forName: UserDefaults.argumentDomain)
        defer { standard.setVolatileDomain(original, forName: UserDefaults.argumentDomain) }
        var arguments = original
        arguments["MarkdownPreview.appearance"] = "dark"
        standard.setVolatileDomain(arguments, forName: UserDefaults.argumentDomain)
        XCTAssertEqual(SettingsKeyMigration.migrate(defaults, domain: suiteName), [])
    }
}
