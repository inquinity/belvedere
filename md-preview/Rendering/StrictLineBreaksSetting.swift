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

/// How a single new line inside a paragraph is shown. The two choices, named
/// for the places readers already know them from: a README on GitHub, and a
/// comment or issue. The saved value is `StrictLineBreaksSetting`, true for
/// `reflow`; a document window can choose its own for the session.
nonisolated enum SingleNewLineStyle: CaseIterable {
    case reflow
    case breakAtLine

    init(joinsLines: Bool) {
        self = joinsLines ? .reflow : .breakAtLine
    }

    var joinsLines: Bool { self == .reflow }

    var title: String {
        switch self {
        case .reflow: return NSLocalizedString("Reflow (like a README)", comment: "Single new line style")
        case .breakAtLine: return NSLocalizedString("Break (like a comment)", comment: "Single new line style")
        }
    }

    var explanation: String {
        switch self {
        case .reflow:
            return NSLocalizedString("Lines run together until a blank line, the way a README is shown on GitHub.",
                                     comment: "Single new line style explanation")
        case .breakAtLine:
            return NSLocalizedString("Every new line is a line break, the way GitHub shows comments and issues.",
                                     comment: "Single new line style explanation")
        }
    }
}
