import Foundation

/// Shared by document previews and Quick Look. Joining is the default since
/// 1.4: a single newline in the source is a space, as in CommonMark, on GitHub
/// and in editor previews, so a hard-wrapped file reflows to the window
/// instead of keeping the width its author wrapped at. Turning it off shows each
/// newline as a line break. Stored as `strictLineBreaks`, true meaning join.
nonisolated enum StrictLineBreaksSetting {
    static let defaultsKey = "MarkdownPreview.strictLineBreaks"
    /// What a reader gets when nothing is saved.
    static let defaultValue = true

    static var current: Bool {
        get { read(from: AppearanceMode.sharedDefaults()) }
        set { write(newValue, to: AppearanceMode.sharedDefaults()) }
    }

    static func read(from defaults: UserDefaults?) -> Bool {
        (defaults?.object(forKey: defaultsKey) as? Bool) ?? defaultValue
    }

    static func write(_ enabled: Bool, to defaults: UserDefaults?) {
        // The default is stored as nothing, so a later change of default reaches
        // everyone who never chose; a choice against it is stored explicitly.
        if enabled == defaultValue {
            defaults?.removeObject(forKey: defaultsKey)
        } else {
            defaults?.set(enabled, forKey: defaultsKey)
        }
    }
}
