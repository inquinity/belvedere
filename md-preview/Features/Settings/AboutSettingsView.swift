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
                HStack(spacing: 16) {
                    if let appIcon = NSApplication.shared.applicationIconImage {
                        Image(nsImage: appIcon)
                            .resizable()
                            .frame(width: 64, height: 64)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text(L("Markdown Preview"))
                            .font(.title)
                            .fontWeight(.medium)

                        Text(versionSummary)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                }
                .padding(.vertical, 8)

            }

            Section {
                Link(L("GitHub Project"), destination: URL(string: "https://github.com/inquinity/belvedere")!)
            }
        }
        .formStyle(.grouped)
        .onAppear {
            model.refreshFromExternalSources()
        }
    }

    private var versionSummary: String {
        let info = Bundle.main.infoDictionary
        let marketing = info?["CFBundleShortVersionString"] as? String ?? "—"
        let build = info?["CFBundleVersion"] as? String ?? "—"
        return String(format: L("Version %@ (%@)"), marketing, build)
    }
}
