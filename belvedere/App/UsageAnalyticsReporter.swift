import Foundation

/// Usage analytics, disabled in this fork.
///
/// Upstream POSTs an anonymous "app became active" event to PostHog once per
/// UTC day, enabled by default. This fork makes no network connections, so the
/// type keeps its shape and does nothing.
///
/// Deliberately a stub rather than a deletion, for the same reason as
/// `CrashReporter`: the call sites live in files upstream edits constantly, and
/// leaving them untouched keeps merges cheap. See docs/FORK-NOTES.md.
enum UsageAnalyticsReporter {

    /// Always `false`. Note that upstream's getter returns `true` when the
    /// preference has never been set — analytics there is opt-out, not opt-in.
    /// The setter is accepted and discarded.
    static var isEnabled: Bool {
        get { false }
        set { _ = newValue }
    }

    /// No-op. Upstream builds and sends the PostHog capture request here.
    static func recordAppBecameActive() {}
}
