//
//  DiskChangePolicy.swift
//  belvedere
//
//  What to do when the open file changes on disk. Foundation only, so the
//  helper tests can pin the rule down.
//

import Foundation

/// The rule: a file that changed on disk is reloaded without asking, unless the
/// window holds edits that are not saved. Then the reader decides, because
/// either version can be lost.
nonisolated enum DiskChangePolicy {

    enum Action: Equatable {
        /// Nothing to do: the file is unreadable for now, or already what the
        /// window shows (this app's own save, a touch, a tool writing the
        /// same text again).
        case ignore
        /// Show the file as it is now. No edit session is open.
        case reloadPreview
        /// An edit session is open with nothing unsaved: put the new text in
        /// the editor.
        case reloadEditor
        /// There are unsaved edits and the file differs from the version they
        /// were made on: ask whether to overwrite, discard or save elsewhere.
        case askWhatToDo
    }

    /// - Parameters:
    ///   - disk: The file's text now, or nil if it cannot be read at the moment.
    ///   - lastSaved: The text the window last read from, or wrote to, the file.
    ///   - local: The text the reader is working on: the editor's contents, or a
    ///     kept draft after leaving edit mode. Nil when there is none.
    ///   - isEditing: Whether the editor is open.
    static func action(disk: String?, lastSaved: String?, local: String?, isEditing: Bool) -> Action {
        guard let disk else { return .ignore }
        // The window's own text already matches, or no baseline exists to compare with.
        if let local, local == disk, local != lastSaved {
            // The edits happen to equal what is on disk now: nothing is at risk.
            return isEditing ? .reloadEditor : .reloadPreview
        }
        guard disk != lastSaved else { return .ignore }
        if let local, local != lastSaved { return .askWhatToDo }
        return isEditing ? .reloadEditor : .reloadPreview
    }
}
