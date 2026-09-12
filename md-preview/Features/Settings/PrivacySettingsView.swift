//
//  PrivacySettingsView.swift
//  md-preview
//

import SwiftUI

// MARK: - Privacy

/// Upstream offers two toggles here: anonymous crash reports to Sentry, and
/// anonymous usage analytics to PostHog. This fork ships neither, and neither
/// does it ship Sparkle, so there is nothing to turn on or off — the pane
/// states the guarantee instead.
///
/// The pane is kept rather than removed so `SettingsWindowController`'s tab
/// list is untouched. See docs/FORK-NOTES.md.
struct PrivacySettingsView: View {

    var body: some View {
        Form {
            Section {
                LabeledContent(L("Network activity")) {
                    Text(L("Only when you ask")).foregroundStyle(.secondary)
                }
            } footer: {
                Text(L("Crash reporting, usage analytics and automatic updates have all been removed, so nothing in this app contacts a server on its own. The only outbound request it makes is one you ask for by clicking Load on a remote image. The sandbox entitlement that permits outbound connections is still present because WKWebView will not render without it — so the guarantee comes from the code that was removed, not from the sandbox."))
            }

            Section {
                LabeledContent(L("Remote images")) {
                    Text(L("Blocked until you load them")).foregroundStyle(.secondary)
                }
            } footer: {
                Text(L("A Markdown document that references an image by http or https URL shows a placeholder naming the host rather than fetching it, so opening or previewing a document never tells its author that you read it. In the document window you can click Load on a placeholder to fetch that one image: the request carries no cookies and is not remembered, so the next one asks again, and Load all covers local files only. Quick Look names these images without offering to load them."))
            }
        }
        .formStyle(.grouped)
    }
}
