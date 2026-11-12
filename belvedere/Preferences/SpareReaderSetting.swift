//
//  SpareReaderSetting.swift
//  belvedere
//
//  Storage behind "Prepare the next window in advance" (Settings ▸ General).
//  Kept free of AppKit so the SPM helper tests can exercise it.
//

import Foundation

/// Whether `SpareReaderPool` keeps a reader prepared for the next document
/// window. On by default: the second and later documents open faster. Off
/// saves the memory of one extra WebKit page process while documents are open.
///
/// Stored as the negative, `belvedere.disableSpareReader`, which existed first
/// as a launch argument for timing runs (`-belvedere.disableSpareReader YES`).
/// Keeping that key means the argument still works, and nothing saved before
/// needs migrating: absent means on.
nonisolated enum SpareReaderSetting {
    static let disabledDefaultsKey = "belvedere.disableSpareReader"

    static func isEnabled(in defaults: UserDefaults) -> Bool {
        !defaults.bool(forKey: disabledDefaultsKey)
    }

    /// On clears the key rather than storing `false`, as the other
    /// preferences do: an untouched preference leaves no trace. A launch
    /// argument still wins over what is stored here, for that run.
    static func write(_ isEnabled: Bool, to defaults: UserDefaults) {
        if isEnabled {
            defaults.removeObject(forKey: disabledDefaultsKey)
        } else {
            defaults.set(true, forKey: disabledDefaultsKey)
        }
    }
}
