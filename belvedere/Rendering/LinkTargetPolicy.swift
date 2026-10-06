//
//  LinkTargetPolicy.swift
//  belvedere
//

import Darwin
import Foundation
import UniformTypeIdentifiers

/// Decides whether a clicked link to a local file is opened or only shown in
/// Finder.
///
/// The document chose the path, not the reader, and `NSWorkspace.open` means
/// "run" for a surprising number of file types. The first version of this
/// check was a denylist (app bundles, Unix executables, installers, disk
/// images), and it missed three ways round it, each one click from a README:
///
/// - a **symlink** to an app. Its content type is `public.symlink`, which is
///   none of the above, and `NSWorkspace` follows it and launches the app;
/// - a **`.terminal`** settings file, which can carry a startup command that
///   Terminal runs when it opens the file, with no execute bit needed;
/// - **`.fileloc`**, **`.jar`**, **`.prefPane`**, **`.mobileconfig`** and
///   others that hand the click to something that runs or installs.
///
/// So this is an allowlist. A link opens directly only when its target, with
/// symlinks resolved, is a plain folder or a file of a kind that is only ever
/// displayed: an image, audio or video, a PDF, or plain text that is not a
/// script or a playlist. Everything else is shown in Finder, where the reader
/// decides.
///
/// The type comes from the extension, but `NSWorkspace.open` picks the app per
/// file: a file's own "Open With" choice, stored in the
/// `com.apple.LaunchServices.OpenWith` extended attribute, overrides the
/// type's default. It survives zips, disk images, AirDrop and USB drives, so a
/// downloaded `diagram.png` can name Installer or Terminal as its app. A file
/// that carries one is shown in Finder, whatever its type.
///
/// The resolved URL is the one handed back for opening, so the file that was
/// classified is the file that gets opened, not a link that could point
/// somewhere else by then.
nonisolated enum LinkTargetPolicy {

    enum Disposition: Equatable {
        /// Safe to hand to `NSWorkspace.open`.
        case open(URL)
        /// Show in Finder after telling the reader why.
        case reveal(URL)
        /// Nothing is there. Opening it would do nothing useful, and a path
        /// that is not there now could be by the time it is opened.
        case missing
    }

    /// Kinds of file the system only displays. `public.plain-text` takes in
    /// source code and shell scripts, so scripts are refused before this list
    /// is consulted.
    private static let displayOnly: [UTType] = [.image, .audiovisualContent, .pdf, .plainText]

    /// Refused even when they match `displayOnly`. `.script` covers shell,
    /// `.command`, Python, AppleScript and JavaScript sources. SVG is an image
    /// that a browser opens, and can carry script. A playlist is plain text
    /// that Music opens by fetching every address in it.
    private static let neverDirect: [UTType] = [.script, .executable, .svg, .playlist]

    static let openWithAttribute = "com.apple.LaunchServices.OpenWith"

    static func disposition(for url: URL) -> Disposition {
        let target = url.standardizedFileURL.resolvingSymlinksInPath()

        // `lstat`, not `fileExists`: only "no such file" means missing. A
        // permission error or a dangling symlink is something there that
        // could not be classified, and is shown rather than opened.
        var info = stat()
        guard lstat(target.path, &info) == 0 else {
            return errno == ENOENT ? .missing : .reveal(target)
        }
        if info.st_mode & S_IFMT == S_IFLNK { return .reveal(target) }

        if hasOpenWithOverride(target) { return .reveal(target) }

        let keys: Set<URLResourceKey> = [.isDirectoryKey, .isPackageKey, .contentTypeKey]
        guard let values = try? target.resourceValues(forKeys: keys) else { return .reveal(target) }

        if values.isDirectory == true {
            // Apps, preference panes, workflows and every other bundle are
            // directories the system treats as one runnable thing.
            return values.isPackage == true ? .reveal(target) : .open(target)
        }

        if FileManager.default.isExecutableFile(atPath: target.path) { return .reveal(target) }

        guard let type = values.contentType,
              !neverDirect.contains(where: type.conforms(to:)),
              displayOnly.contains(where: type.conforms(to:))
        else { return .reveal(target) }
        return .open(target)
    }

    /// Whether the file names its own app. Fails closed: only "no such
    /// attribute" and "this volume has none" count as no.
    private static func hasOpenWithOverride(_ url: URL) -> Bool {
        let size = getxattr(url.path, openWithAttribute, nil, 0, 0, XATTR_NOFOLLOW)
        if size >= 0 { return true }
        return errno != ENOATTR && errno != ENOTSUP
    }
}
