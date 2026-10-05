//
//  GeneralSettingsView.swift
//  md-preview
//

import SwiftUI

// MARK: - General

struct GeneralSettingsView: View {
    @AppStorage("MarkdownPreview.outlineFollowsPointer") private var outlineFollowsPointer = false
    @Bindable private var model = SettingsModel.shared

    var body: some View {
        Form {
            Section {
                LabeledContent {
                    TextSizePicker(selection: $model.textSize)
                } label: {
                    Text(L("Text size"))
                    Text(L("Size of rendered Markdown in document windows."))
                }

                // Upstream's "Strict line breaks" toggle, as a choice between two
                // named behaviours: "strict" read as the opposite of what it did.
                // Same stored Bool, so no migration and Quick Look is unchanged.
                LabeledContent {
                    HStack(spacing: 6) {
                        Picker(L("Line breaks"), selection: $model.strictLineBreaks) {
                            Text(L("Keep as typed")).tag(false)
                            Text(L("Join into paragraphs")).tag(true)
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .fixedSize()

                        InfoPopoverButton(accessibilityLabel: L("About line breaks")) {
                            VStack(alignment: .leading, spacing: 8) {
                                Text(L("Keep as typed")).bold()
                                    + Text(": ")
                                    + Text(L("each new line starts a new line, the way GitHub shows comments and issues."))
                                Text(L("Join into paragraphs")).bold()
                                    + Text(": ")
                                    + Text(L("lines run together until a blank line, the way standard Markdown and GitHub README files work."))
                                Text(L("Either way, a blank line starts a new paragraph, and two trailing spaces or a backslash at the end of a line force a break. Applies to the reading view and Quick Look."))
                            }
                        }
                    }
                } label: {
                    Text(L("Line breaks"))
                    Text(L("How a single new line in the source is shown."))
                }

                Toggle(L("Highlight outline section under the pointer"), isOn: $outlineFollowsPointer)

                Picker(L("Default content width"), selection: $model.contentWidth) {
                    ForEach(ContentWidthSetting.allCases, id: \.self) { setting in
                        Text(setting.title).tag(setting)
                    }
                }
                Text(model.contentWidth.explanation + " "
                     + L("New windows and tabs open with this width. Open windows keep theirs; change one from View ▸ Content Width, which is not saved."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text(L("Reading"))
            } footer: {
                Text(L("Text size also applies to Quick Look previews. Zooming a document window with ⌘+ and ⌘− changes it too. Fonts and reading layout live in Appearance settings."))
            }

            Section {
                Toggle(isOn: $model.isAlwaysOnTop) {
                    Text(L("Always on Top"))
                    Text(L("Keeps every Markdown Preview window in front of other apps, including windows you open later. A window in full screen is left alone until it comes back out."))
                }

                Toggle(isOn: $model.opensMarkdownLinksInNewWindows) {
                    Text(L("Open Markdown links in new windows"))
                    Text(L("Clicking a link to another Markdown file opens it in a separate window. Turn this off to open it in the current window."))
                }

                Toggle(isOn: $model.opensDocumentsInTabs) {
                    Text(L("Open documents in tabs"))
                    Text(L("A file opened from Finder joins the front window as a tab instead of getting one of its own — Open in New Window still opens a window."))
                }
            } header: {
                Text(L("Windows"))
            }

            Section {
                LabeledContent {
                    Picker("", selection: $model.autoSaveIntervalMinutes) {
                        Text(L("Never")).tag(AutoSaveSetting.disabledMinutes)
                        Text(L("30 seconds")).tag(AutoSaveSetting.thirtySeconds)
                        Text(L("1 minute")).tag(1)
                        ForEach([5, 10, 15, 30, 60], id: \.self) { minutes in
                            Text(String(format: L("%d minutes"), minutes))
                                .tag(minutes)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                } label: {
                    Text(L("Automatic saving"))
                    Text(L("Save edited documents periodically."))
                }
                Toggle(isOn: $model.exitsEditModeSilently) {
                    Text(L("Leave edit mode without asking to save"))
                    Text(L("Unsaved changes stay in the window until you save or close it."))
                }
            } header: {
                Text(L("Editing"))
            } footer: {
                Text(L("Automatic saving runs while a document has unsaved edits."))
            }

            Section {
                if model.openTargets.isEmpty {
                    LabeledContent(L("Open documents in")) {
                        Text(L("No apps available")).foregroundStyle(.secondary)
                    }
                } else {
                    Picker(L("Open documents in"), selection: $model.openTargetID) {
                        aiAppItems
                        editorItems
                    }
                }
            } header: {
                Text(L("Hand-off"))
            } footer: {
                Text(L("The app the Open button in the document toolbar uses first. Its menu still offers every other installed app."))
            }

            // The "Command line tools -> Install..." section is removed in this
            // fork. M3 orphaned the CLI installer: the menu item and the
            // apple-events entitlement went, and the `markdown-preview` binary
            // is no longer bundled -- but this button survived and still called
            // into the installer. It could not succeed, and its only failure
            // path is an NSLog, so the button did nothing at all, silently,
            // while its footer promised three commands on the user's PATH.
            //
            // The installer code itself stays (see docs/FORK-NOTES.md, "There
            // is deliberately dead code in this fork") -- this removes the last
            // reachable caller, not the code behind it.
        }
        .formStyle(.grouped)
        .onAppear {
            model.refreshFromExternalSources()
            model.reloadOpenTargets()
        }
    }

    @ViewBuilder
    private var aiAppItems: some View {
        let apps = model.openTargets.filter(\.isAIApp)
        if !apps.isEmpty {
            Section(L("AI apps")) {
                ForEach(apps) { choice in
                    openTargetRow(choice)
                }
            }
        }
    }

    @ViewBuilder
    private var editorItems: some View {
        let editors = model.openTargets.filter { !$0.isAIApp }
        if !editors.isEmpty {
            Section(L("Editors")) {
                ForEach(editors) { choice in
                    openTargetRow(choice)
                }
            }
        }
    }

    private func openTargetRow(_ choice: OpenTargetChoice) -> some View {
        HStack {
            Image(nsImage: choice.icon)
            Text(choice.title)
        }
        .tag(choice.id)
    }
}
