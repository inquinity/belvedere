import Foundation
import XCTest
@testable import MarkdownHelpers

final class SpareReaderSettingTests: XCTestCase {
    /// On unless someone turned it off: nothing stored means enabled, so
    /// every existing installation keeps the faster opening it had.
    func testNothingStoredMeansEnabled() throws {
        XCTAssertTrue(SpareReaderSetting.isEnabled(in: try makeDefaults()))
    }

    /// The key is the one the timing launch argument already used, so
    /// `-belvedere.disableSpareReader YES` keeps working.
    func testLaunchArgumentKeyStillTurnsItOff() throws {
        let defaults = try makeDefaults()
        defaults.set(true, forKey: "belvedere.disableSpareReader")
        XCTAssertFalse(SpareReaderSetting.isEnabled(in: defaults))
    }

    /// A `false` left by an earlier build still means on.
    func testStoredFalseMeansEnabled() throws {
        let defaults = try makeDefaults()
        defaults.set(false, forKey: SpareReaderSetting.disabledDefaultsKey)
        XCTAssertTrue(SpareReaderSetting.isEnabled(in: defaults))
    }

    func testTurningOnClearsTheKey() throws {
        let defaults = try makeDefaults()
        SpareReaderSetting.write(false, to: defaults)
        XCTAssertFalse(SpareReaderSetting.isEnabled(in: defaults))
        SpareReaderSetting.write(true, to: defaults)
        XCTAssertTrue(SpareReaderSetting.isEnabled(in: defaults))
        XCTAssertNil(defaults.object(forKey: SpareReaderSetting.disabledDefaultsKey),
                     "an untouched preference leaves no trace")
    }

    private func makeDefaults() throws -> UserDefaults {
        let suiteName = "SpareReaderSettingTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        addTeardownBlock {
            UserDefaults(suiteName: suiteName)?.removePersistentDomain(forName: suiteName)
        }
        return defaults
    }
}
