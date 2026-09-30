//
//  LegacySharedSettingsMigration.swift
//  md-preview
//
//  Fork-only. Carries the reading settings Belvedere 1.2.4 and earlier saved
//  into the app group the app and Quick Look now actually share.
//

import Foundation
import os

/// Belvedere through 1.2.4 was signed for an app group named with the
/// literal, unexpanded `$(DEVELOPMENT_TEAM)`, while its code asked for the
/// real group, `45GJWJVQN2.com.altmansoftwaredesign.belvedere`. A sandboxed
/// app that opens a `UserDefaults(suiteName:)` it is not entitled to gets a
/// private copy inside its own container instead, at
/// `Library/Preferences/<suite>.plist`, so every shared setting -- appearance,
/// theme and each theme's saved look, document font, reading layout, custom
/// colors -- went there. Signed correctly, the same suite resolves to the
/// group container, which starts out empty, and upgrading would reset them all.
///
/// This copies them across once, before the other launch-time migrations
/// read the suite. It only fills keys the group does not have yet, so a value
/// chosen after upgrading always wins, and it only copies `MarkdownPreview.`
/// keys, which is every setting the app keeps in that suite.
nonisolated enum LegacySharedSettingsMigration {

    static let completedKey = "MarkdownPreview.legacyContainerSuiteMigrated"
    static let keyPrefix = "MarkdownPreview."

    private static let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Belvedere",
                                    category: "migration")

    /// Runs the migration the first time this build launches with a working
    /// app group, and never again. A missing legacy file -- a fresh install,
    /// or one that never changed a setting -- still marks it done.
    static func runIfNeeded(bundle: Bundle = .main) {
        guard let group = bundle.object(forInfoDictionaryKey: AppearanceMode.appGroupInfoKey) as? String,
              !group.isEmpty,
              let shared = UserDefaults(suiteName: group),
              !shared.bool(forKey: completedKey) else { return }

        // In the sandbox, the home directory is the app's own container.
        let legacyFile = URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent("Library/Preferences/\(group).plist")
        // Notice level, so the outcome is kept in the log store: whether an
        // upgrade found anything is the first question if settings look reset.
        if let legacy = NSDictionary(contentsOf: legacyFile) as? [String: Any] {
            let copied = migrate(legacy, into: shared)
            // Key names only: which settings came across, never their values.
            log.notice("Carried \(copied.count, privacy: .public) settings from before 1.3.0: \(copied.joined(separator: ", "), privacy: .public)")
        } else {
            log.notice("No settings from before 1.3.0 to carry over")
        }
        shared.set(true, forKey: completedKey)
    }

    /// Copies each `MarkdownPreview.` setting in `legacy` that `shared` does
    /// not already hold, and returns the keys it copied, sorted.
    @discardableResult
    static func migrate(_ legacy: [String: Any], into shared: UserDefaults) -> [String] {
        var copied: [String] = []
        for (key, value) in legacy
        where key.hasPrefix(keyPrefix) && key != completedKey && shared.object(forKey: key) == nil {
            shared.set(value, forKey: key)
            copied.append(key)
        }
        return copied.sorted()
    }
}
