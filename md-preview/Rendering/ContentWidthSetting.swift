//
//  ContentWidthSetting.swift
//  md-preview
//
//  Compiled into both targets (MarkdownWebView.swift reads it at render time),
//  and into the test package, so the saved default can be tested.
//

import Foundation

/// Article layout. `current` is the saved default for every document window;
/// a window can override it for itself without saving (View ▸ Content Width).
/// Quick Look always renders the centered column; this only drives the app.
/// A file of its own, compiled into both targets, because MarkdownWebView.swift
/// (which both targets build) reads it when it renders a page.
enum ContentWidthSetting: String, CaseIterable {
    /// Capped at the column Quick Look uses (820 px) and centered, so a
    /// document wraps in the same places in the app and in a Quick Look
    /// preview. Stored as "normal", its name before the rename, so nothing
    /// saved needs migrating.
    case quickLook = "normal"
    /// The text uses the whole window and follows it as it is resized.
    case fullWidth

    /// What a window gets when nothing is saved. It was the capped column
    /// until 1.4, which left a wide window mostly margin.
    static let defaultSetting: ContentWidthSetting = .fullWidth

    private static let defaultsKey = "MarkdownPreview.contentWidth"

    static var current: ContentWidthSetting {
        get {
            UserDefaults.standard.string(forKey: defaultsKey)
                .flatMap(ContentWidthSetting.init(rawValue:)) ?? defaultSetting
        }
        set {
            if newValue == defaultSetting {
                UserDefaults.standard.removeObject(forKey: defaultsKey)
            } else {
                UserDefaults.standard.set(newValue.rawValue, forKey: defaultsKey)
            }
        }
    }

    var title: String {
        switch self {
        case .quickLook: return NSLocalizedString("Quick Look Width", comment: "Content width")
        case .fullWidth: return NSLocalizedString("Full Width", comment: "Content width")
        }
    }

    var explanation: String {
        switch self {
        case .quickLook:
            return NSLocalizedString("Wraps lines in the same places as a Quick Look preview.",
                                     comment: "Content width explanation")
        case .fullWidth:
            return NSLocalizedString("Uses the whole window and follows it as you resize.",
                                     comment: "Content width explanation")
        }
    }

    var renderWidth: MarkdownHTML.ContentWidth {
        switch self {
        case .quickLook: return .hostCentered
        case .fullWidth: return .full
        }
    }
}
