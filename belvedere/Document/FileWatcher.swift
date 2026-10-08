//
//  FileWatcher.swift
//  belvedere
//
//  Watches an open document's file for changes, renames, and deletion.
//

import Cocoa

final class FileWatcher {
    private static let moveResolutionDelay: TimeInterval = 0.20

    private let url: URL
    private let onChange: () -> Void
    /// Fired when the watched file is renamed or moved (in Finder, by an
    /// editor, etc.). Detected via `F_GETPATH` on the still-open FD —
    /// the inode follows the file, so the descriptor resolves to the
    /// new path. Plain deletes don't fire this (path unchanged).
    var onRename: ((URL) -> Void)?
    private var source: DispatchSourceFileSystemObject?
    private var fileDescriptor: Int32 = -1
    private var debounce: DispatchWorkItem?
    private var moveResolution: DispatchWorkItem?
    private var reopenRetry: DispatchWorkItem?
    private var isCancelled = false
    /// How long to wait before looking again for a file that is not there, and
    /// the longest wait. A file can be missing for a while: a tool that
    /// replaces it by deleting, then writing, or a sync that is still copying.
    private static let firstRetryDelay: TimeInterval = 0.25
    private static let longestRetryDelay: TimeInterval = 5

    init(url: URL, onChange: @escaping () -> Void) {
        self.url = url
        self.onChange = onChange
        open()
    }

    private func open() {
        guard !isCancelled else { return }
        let fd = Darwin.open(url.path, O_EVTONLY)
        guard fd >= 0 else {
            // Not there (yet). Keep looking, rather than going deaf for good:
            // an app that deletes the file and writes it again a moment later
            // would otherwise leave the window showing the old text forever.
            reopenWhenAvailable(after: Self.firstRetryDelay)
            return
        }
        reopenRetry?.cancel()
        reopenRetry = nil
        fileDescriptor = fd

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .extend, .delete, .rename, .revoke],
            queue: .main
        )
        source.setEventHandler { [weak self] in
            guard let self, let source = self.source else { return }
            let event = source.data
            // Atomic-rename saves (Vim, VS Code, etc.) replace the inode;
            // re-open the watcher against the path so we keep tracking.
            // For an actual user-visible rename, the FD's resolved path
            // differs from the watcher's URL — surface that to the host.
            if !event.intersection([.delete, .rename, .revoke]).isEmpty {
                self.resolveMove(afterSettlingAt: self.currentPath())
                return
            }
            self.scheduleChange()
        }
        source.setCancelHandler { [weak self] in
            guard let self else { return }
            if self.fileDescriptor >= 0 {
                Darwin.close(self.fileDescriptor)
                self.fileDescriptor = -1
            }
        }
        self.source = source
        source.resume()
    }

    private func resolveMove(afterSettlingAt movedURL: URL?) {
        moveResolution?.cancel()
        debounce?.cancel()
        source?.cancel()
        source = nil

        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.moveResolution = nil
            let resolution = FileWatcherMoveResolution.resolve(
                originalURL: self.url,
                movedURL: movedURL,
                fileExists: { FileManager.default.fileExists(atPath: $0.path) }
            )
            switch resolution {
            case .reloadOriginal:
                self.open()
                self.scheduleChange()
            case .followRename(let newURL):
                self.onRename?(newURL)
            case .unavailable:
                self.reopenWhenAvailable(after: Self.firstRetryDelay)
            }
        }
        moveResolution = work
        DispatchQueue.main.asyncAfter(
            deadline: .now() + Self.moveResolutionDelay,
            execute: work
        )
    }

    /// Looks for the file again after `delay`, backing off up to a few seconds,
    /// until it is back. Then watches it again and reports a change, because
    /// whatever is there now is not what the window last read.
    private func reopenWhenAvailable(after delay: TimeInterval) {
        guard !isCancelled else { return }
        reopenRetry?.cancel()
        source?.cancel()
        source = nil
        let work = DispatchWorkItem { [weak self] in
            guard let self, !self.isCancelled else { return }
            if FileManager.default.fileExists(atPath: self.url.path) {
                self.open()
                if self.source != nil { self.scheduleChange() }
            } else {
                self.reopenWhenAvailable(after: min(delay * 2, Self.longestRetryDelay))
            }
        }
        reopenRetry = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private func currentPath() -> URL? {
        guard fileDescriptor >= 0 else { return nil }
        var buffer = [CChar](repeating: 0, count: Int(MAXPATHLEN))
        guard fcntl(fileDescriptor, F_GETPATH, &buffer) == 0 else { return nil }
        return URL(fileURLWithFileSystemRepresentation: buffer,
                   isDirectory: false,
                   relativeTo: nil)
    }

    private func scheduleChange() {
        debounce?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.onChange() }
        debounce = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08, execute: work)
    }

    func cancel() {
        isCancelled = true
        debounce?.cancel()
        moveResolution?.cancel()
        reopenRetry?.cancel()
        source?.cancel()
        source = nil
    }
}
