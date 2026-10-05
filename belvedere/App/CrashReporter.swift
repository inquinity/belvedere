import Foundation

/// Crash reporting, disabled in this fork.
///
/// Upstream starts the Sentry SDK here and uploads crash reports to
/// sentry.io. This fork makes no network connections, so the type keeps its
/// shape and does nothing.
///
/// Deliberately a stub rather than a deletion. `AppDelegate` and
/// `SettingsModel` call into this from seven places between them, and both are
/// files upstream edits constantly. Preserving the API surface keeps those call
/// sites identical to upstream, so they never appear in our diff and never
/// conflict on merge. See docs/FORK-NOTES.md.
enum CrashReporter {

    /// Always `false`. The setter is accepted and discarded so the Settings
    /// binding and the menu item still compile; there is nothing to enable.
    static var isEnabled: Bool {
        get { false }
        set { _ = newValue }
    }

    /// No-op. Upstream starts the Sentry SDK here.
    static func start(bundle: Bundle = .main) {
        _ = bundle
    }
}
