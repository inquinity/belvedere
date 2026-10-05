//
//  SettingsKeyMigration.swift
//  belvedere
//
//  Fork-only. Belvedere through 1.x saved every setting under a key beginning
//  `MarkdownPreview.`, the project's old name. Version 2.0 saves them under
//  `belvedere.`. This carries each saved value across, once, so nobody loses a
//  setting by upgrading.
//

import Foundation
import os

nonisolated enum SettingsKeyMigration {

    static let oldPrefix = "MarkdownPreview."
    static let newPrefix = "belvedere."

    private static let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "belvedere",
                                    category: "migration")

    /// Renames the keys in the app's own defaults and in the app group the app
    /// and Quick Look share. Run it before anything reads a setting, and before
    /// `LegacySharedSettingsMigration`, which writes under the new prefix.
    static func runIfNeeded(bundle: Bundle = .main) {
        if let identifier = bundle.bundleIdentifier {
            report(migrate(.standard, domain: identifier), in: "app")
        }
        if let group = bundle.object(forInfoDictionaryKey: AppearanceMode.appGroupInfoKey) as? String,
           !group.isEmpty, let shared = UserDefaults(suiteName: group) {
            report(migrate(shared, domain: group), in: "group")
        }
    }

    /// Copies each `MarkdownPreview.` key in `defaults`' own saved domain to the
    /// same name under `belvedere.`, then removes the old one. A value already
    /// saved under the new name wins, so a setting changed after upgrading is
    /// never overwritten. Reads the saved domain, not the merged view, so a
    /// launch argument or another domain is never copied into storage. Safe to
    /// run on every launch: once the old keys are gone it finds nothing.
    /// Returns the new key names it wrote, sorted.
    @discardableResult
    static func migrate(_ defaults: UserDefaults, domain: String) -> [String] {
        let stored = defaults.persistentDomain(forName: domain) ?? [:]
        var written: [String] = []
        for (key, value) in stored where key.hasPrefix(oldPrefix) {
            let renamed = newPrefix + key.dropFirst(oldPrefix.count)
            if stored[renamed] == nil {
                defaults.set(value, forKey: renamed)
                written.append(renamed)
            }
            defaults.removeObject(forKey: key)
        }
        return written.sorted()
    }

    private static func report(_ keys: [String], in place: String) {
        guard !keys.isEmpty else { return }
        // Names only, never values.
        log.notice("Renamed \(keys.count, privacy: .public) saved settings in the \(place, privacy: .public) defaults: \(keys.joined(separator: ", "), privacy: .public)")
    }
}
