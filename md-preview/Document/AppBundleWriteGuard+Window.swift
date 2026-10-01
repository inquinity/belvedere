//
//  AppBundleWriteGuard+Window.swift
//  md-preview
//
//  Fork-only. The window-facing half of `AppBundleWriteGuard`, kept apart so
//  the path logic compiles in the test package without the window controller.
//

import AppKit

extension DocumentWindowController {

    /// Whether the open document may be edited. A document inside the app
    /// bundle never may: no edit mode, so no Save. Save As… to somewhere else
    /// is still allowed, and the window then follows the new copy.
    func allowsEditingCurrentFile() -> Bool {
        guard let url = currentFileURL, AppBundleWriteGuard.isInsideAppBundle(url) else { return true }
        presentBundleWriteRefusal(AppBundleWriteGuard.WriteRefused())
        return false
    }

    /// Tells the reader why nothing was written. Safe to call with no window.
    func presentBundleWriteRefusal(_ error: AppBundleWriteGuard.WriteRefused) {
        let alert = NSAlert(error: error)
        alert.informativeText = [
            NSLocalizedString("This document is part of Belvedere, and changing it would break the application.",
                              comment: "Refusal to edit a document inside the app bundle"),
            error.recoverySuggestion,
        ].compactMap { $0 }.joined(separator: " ")
        alert.beginSheetModal(for: documentWindow)
    }
}
