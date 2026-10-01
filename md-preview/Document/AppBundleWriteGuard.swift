//
//  AppBundleWriteGuard.swift
//  md-preview
//
//  Fork-only. Belvedere may save any file it is asked to open, because it
//  holds `files.user-selected.read-write`. That includes a file inside its own
//  app bundle, and writing there breaks the app's code seal. macOS's App
//  Management protection stops other developers' apps from changing the
//  bundle, but not the app itself, so the app has to refuse for itself.
//

import AppKit

/// Decides whether a path is inside the running app's bundle.
///
/// Symlinks are followed and the comparison ignores case, because the default
/// volume format does: `/applications/belvedere.app/...` is the same place. A
/// file that does not exist yet (Save As, an export) is judged by the nearest
/// folder that does. Hard links are not followed; a second name for a bundled
/// file outside the bundle is not detected.
nonisolated enum AppBundleWriteGuard {

    struct WriteRefused: LocalizedError {
        var errorDescription: String? {
            NSLocalizedString("Belvedere cannot write inside its own application.",
                              comment: "Refusal to write into the app bundle")
        }
        var recoverySuggestion: String? {
            NSLocalizedString("Choose a location outside the application, such as your Documents folder.",
                              comment: "Refusal to write into the app bundle, what to do")
        }
    }

    static func isInside(_ url: URL, bundle: URL) -> Bool {
        let target = resolved(url)
        let root = resolved(bundle)
        guard target.count >= root.count else { return false }
        return zip(root, target).allSatisfy {
            $0.compare($1, options: .caseInsensitive) == .orderedSame
        }
    }

    static func isInsideAppBundle(_ url: URL) -> Bool {
        isInside(url, bundle: Bundle.main.bundleURL)
    }

    /// Throws `WriteRefused` for a destination inside the app bundle.
    static func requireOutsideAppBundle(_ url: URL) throws {
        if isInsideAppBundle(url) { throw WriteRefused() }
    }

    /// Path components with every symlink followed, for a path that may not
    /// exist: the nearest existing ancestor is resolved, then the rest added.
    private static func resolved(_ url: URL) -> [String] {
        var existing = url.standardizedFileURL
        var rest: [String] = []
        while !FileManager.default.fileExists(atPath: existing.path), existing.path != "/" {
            rest.insert(existing.lastPathComponent, at: 0)
            existing = existing.deletingLastPathComponent()
        }
        let real = existing.resolvingSymlinksInPath().standardizedFileURL
        return real.pathComponents + rest
    }
}
