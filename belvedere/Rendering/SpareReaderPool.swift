import AppKit
import os

/// Keeps one reader web view with its empty page already loaded, so the
/// second and later document windows skip WKWebView creation and the
/// WebContent process launch. The first document of a cold launch never
/// waits for a spare: the pool only fills after a real document has painted,
/// because preparing a reader during launch competes with that document.
@MainActor
final class SpareReaderPool {
    static let shared = SpareReaderPool()

    /// Gives the painted document's lazy renderers the main thread first.
    private static let replenishDelay: DispatchTimeInterval = .seconds(1)

    private var spare: MarkdownWebView?
    private var spareSettings: ReaderRenderSettings?
    private var replenishScheduled = false

    /// Settings ▸ General ▸ "Optimize renderer performance", also
    /// settable as a launch argument for timing runs.
    private var isEnabled: Bool {
        SpareReaderSetting.isEnabled(in: .standard)
    }

    /// Hands over the spare, or a fresh reader when there is none. A spare
    /// whose empty page predates a settings change still has a running
    /// WebContent process, so it is kept but made to load the full page.
    func takeReader() -> MarkdownWebView {
        guard let spare else {
            logTake("fresh")
            return MarkdownWebView()
        }
        self.spare = nil
        if spareSettings != ReaderRenderSettings.current {
            spare.discardLoadedPage()
            logTake("stale-spare")
        } else {
            logTake(spare.isReadyAsSpare ? "spare" : "loading-spare")
        }
        spareSettings = nil
        return spare
    }

    /// Call once a document's content is on screen. Prepares a spare after a
    /// short idle delay, if there is none yet.
    func documentDidPaint() {
        guard isEnabled, spare == nil, !replenishScheduled else { return }
        replenishScheduled = true
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.replenishDelay) { [weak self] in
            guard let self else { return }
            replenishScheduled = false
            guard isEnabled, spare == nil, Self.appIsShowingDocuments else { return }
            spareSettings = ReaderRenderSettings.current
            spare = MarkdownWebView(spare: true)
        }
    }

    /// Called by the Settings toggle after it writes the setting. Applies it
    /// at once: turning it off frees a spare that is
    /// already prepared, and its WebContent process, instead of keeping it
    /// until a window takes it; turning it on prepares one if documents are
    /// on screen, after the usual idle delay.
    func settingDidChange() {
        if isEnabled {
            documentDidPaint()
        } else {
            spare = nil
            spareSettings = nil
        }
    }

    /// Frees the spare and its WebContent process once the last document
    /// window has closed, so an app left running without windows does not
    /// hold that memory.
    func releaseSpareIfNoDocumentsShown() {
        guard !Self.appIsShowingDocuments else { return }
        spare = nil
        spareSettings = nil
    }

    private static var appIsShowingDocuments: Bool {
        NSApp.windows.contains { $0.isVisible && $0.windowController is DocumentWindowController }
    }

    private func logTake(_ kind: String) {
        #if DEBUG
        Logger.perf.debug(
            "[mdp-perf-open] reader \(kind, privacy: .public) t=\(DispatchTime.now().uptimeNanoseconds, privacy: .public)"
        )
        #endif
    }
}
