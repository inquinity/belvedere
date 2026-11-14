import Foundation

/// Which Markdown extensions documents are read with, beyond CommonMark and
/// the GitHub extensions every flavor shares (tables, task lists, footnotes,
/// strikethrough). For now it decides callouts only; a later difference
/// between GitHub and the wider Markdown world belongs here too.
///
/// - `extended`: every `> [!type]` blockquote is a callout, with Obsidian's
///   kinds and aliases, a title on the tag line, and `-` / `+` folding.
/// - `github`: only GitHub's five alerts (`NOTE`, `TIP`, `IMPORTANT`,
///   `WARNING`, `CAUTION`), with the tag alone on its line, as GitHub shows
///   them; anything else stays a plain blockquote. Choosing it previews a
///   file as GitHub will show it.
nonisolated enum MarkdownFlavor: String, CaseIterable, Sendable {
    case extended
    case github

    var title: String {
        switch self {
        case .extended: return NSLocalizedString("Extended (GitHub and Obsidian)", comment: "Markdown flavor")
        case .github: return NSLocalizedString("GitHub", comment: "Markdown flavor")
        }
    }

    var explanation: String {
        switch self {
        case .extended:
            return NSLocalizedString("Every callout type, such as [!tip] or [!faq], with a title after the tag and folding with - or +.",
                                     comment: "Markdown flavor explanation")
        case .github:
            return NSLocalizedString("Only GitHub's five alerts, NOTE, TIP, IMPORTANT, WARNING and CAUTION, with the tag alone on its line. Anything else stays a quotation, as on GitHub.",
                                     comment: "Markdown flavor explanation")
        }
    }
}

/// Storage for `MarkdownFlavor`, in the shared defaults so Quick Look reads it.
nonisolated enum MarkdownFlavorSetting {
    static let defaultsKey = "belvedere.markdownFlavor"
    /// What a reader gets when nothing is saved.
    static let defaultValue = MarkdownFlavor.extended

    static var current: MarkdownFlavor {
        get { read(from: AppearanceMode.sharedDefaults()) }
        set { write(newValue, to: AppearanceMode.sharedDefaults()) }
    }

    /// An unknown stored value (from a later version, say) reads as the default.
    static func read(from defaults: UserDefaults?) -> MarkdownFlavor {
        (defaults?.string(forKey: defaultsKey)).flatMap(MarkdownFlavor.init(rawValue:)) ?? defaultValue
    }

    static func write(_ flavor: MarkdownFlavor, to defaults: UserDefaults?) {
        // The default is stored as nothing, so a later change of default
        // reaches everyone who never chose.
        if flavor == defaultValue {
            defaults?.removeObject(forKey: defaultsKey)
        } else {
            defaults?.set(flavor.rawValue, forKey: defaultsKey)
        }
    }
}
