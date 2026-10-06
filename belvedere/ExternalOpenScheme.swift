//
//  ExternalOpenScheme.swift
//  belvedere
//
//  Resolves belvedere:// URLs — the custom scheme browsers and other apps
//  use to hand the app a file or folder to open, mirroring the shape of
//  cursor://file/<absolute path>. Kept free of AppKit so the SPM helper
//  tests can exercise it without a GUI host.
//

import Foundation

nonisolated enum ExternalOpenScheme {

    static let scheme = "belvedere"

    /// Whether an incoming open request came through the app's own scheme, as
    /// opposed to Finder, the Dock or Open With. A `belvedere://` link can be
    /// followed from a web page or another document, so the person did not
    /// necessarily choose it; those get a confirmation before a folder opens.
    static func isOwnScheme(_ url: URL) -> Bool {
        url.scheme?.caseInsensitiveCompare(scheme) == .orderedSame
    }

    /// Translates an incoming open request into the URL to actually open.
    /// URLs of other schemes (file URLs, mostly) pass through untouched.
    /// The app's own scheme accepts
    ///
    ///     belvedere://file/Users/me/README.md
    ///     belvedere:///Users/me/README.md
    ///
    /// and resolves to the file the percent-decoded path names
    /// (`My%20Notes` → `My Notes`). Returns nil only for a malformed
    /// belvedere:// link — another host, an empty path — so the caller
    /// can tell one apart from a URL it can open.
    static func resolvedURL(opening url: URL) -> URL? {
        guard url.scheme?.caseInsensitiveCompare(scheme) == .orderedSame else {
            return url
        }

        let host = url.host ?? ""
        guard host.isEmpty || host.caseInsensitiveCompare("file") == .orderedSame
        else { return nil }

        let path = url.path
        guard path.count > 1, path.hasPrefix("/") else { return nil }
        return URL(fileURLWithPath: path).standardizedFileURL
    }
}
