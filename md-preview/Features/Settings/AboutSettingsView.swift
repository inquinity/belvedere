//
//  AboutSettingsView.swift
//  md-preview
//

import SwiftUI

// MARK: - About

struct AboutSettingsView: View {
    @Bindable private var model = SettingsModel.shared

    var body: some View {
        Form {
            Section {
                HStack(alignment: .top, spacing: 16) {
                    if let appIcon = NSApplication.shared.applicationIconImage {
                        Image(nsImage: appIcon)
                            .resizable()
                            .frame(width: 64, height: 64)
                    }

                    // Copy is shared with the standard About panel
                    // (AppDelegate.showAboutPanel) via AboutCopy, so the two
                    // surfaces cannot drift apart.
                    VStack(alignment: .leading, spacing: 4) {
                        Text(AboutCopy.applicationName)
                            .font(.title)
                            .fontWeight(.medium)

                        Text(AboutCopy.versionSummary)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)

                        Text(AboutCopy.tagline)
                            .font(.subheadline)
                            .padding(.top, 4)

                        Text(AboutCopy.securitySummary)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.vertical, 8)

            }

            // The fork credit is a section footer rather than a second row:
            // it is attribution, not somewhere to go. See AboutCopy.forkCredit.
            Section {
                Link(AboutCopy.repositoryLabel, destination: AboutCopy.repositoryURL)
            } footer: {
                Text(AboutCopy.forkCredit)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .onAppear {
            model.refreshFromExternalSources()
        }
    }
}
