//
//  DocumentWindowController+FormattingBar.swift
//  belvedere
//
//  The formatting accessory bar shown while editing.
//

import Cocoa
import SwiftUI

extension DocumentWindowController {
    // MARK: Formatting bar

    /// Common Markdown actions shown while editing, as Xcode's top-right
    /// floating glass groups. They live in the content host rather than the
    /// titlebar, so toggling edit mode cannot move the native tab bar.
    func showEditAccessory() {
        guard editBar == nil else { return }
        showLiquidGlassEditAccessory()
    }

    /// Xcode's Markdown canvas uses compact, independently shaped glass
    /// groups floating over the document instead of a full-width formatting
    /// row.
    private func showLiquidGlassEditAccessory() {
        let symbolConfig = NSImage.SymbolConfiguration(pointSize: 13, weight: .medium)
            .applying(NSImage.SymbolConfiguration(paletteColors: [.textColor]))
        let chevronConfig = NSImage.SymbolConfiguration(pointSize: 8, weight: .semibold)
            .applying(NSImage.SymbolConfiguration(paletteColors: [.textColor]))

        func iconButton(_ symbol: String,
                        command: String,
                        tip: String,
                        width: CGFloat = 36) -> NSButton {
            let image = NSImage(systemSymbolName: symbol, accessibilityDescription: tip)?
                .withSymbolConfiguration(symbolConfig) ?? NSImage()
            let button = NSButton(image: image, target: self, action: #selector(formatCommand(_:)))
            button.identifier = NSUserInterfaceItemIdentifier(command)
            configureGlassButton(button, tip: tip, width: width)
            button.setButtonType(["bold", "italic", "strikethrough"].contains(command)
                ? .momentaryPushIn : .pushOnPushOff)
            return button
        }

        func menuButton(title: String? = nil,
                        symbol: String? = nil,
                        tip: String,
                        action: Selector,
                        width: CGFloat) -> NSButton {
            let button = NSButton(title: title ?? "", target: self, action: action)
            if #available(macOS 27.0, *), title != nil {
                button.cell = CenteredFormattingButtonCell(textCell: title ?? "")
                button.target = self
                button.action = action
            }
            let primaryImage = symbol.flatMap {
                NSImage(systemSymbolName: $0, accessibilityDescription: tip)?
                    .withSymbolConfiguration(symbolConfig)
            }
            let chevron = NSImage(systemSymbolName: "chevron.down", accessibilityDescription: nil)?
                .withSymbolConfiguration(chevronConfig) ?? NSImage()
            if let primaryImage {
                button.image = composedImage(primaryImage, chevron: chevron, gap: 5)
                button.imagePosition = .imageOnly
            } else {
                button.image = chevron
                button.imagePosition = .imageTrailing
                button.font = .systemFont(ofSize: 13, weight: .medium)
            }
            configureGlassButton(button, tip: tip, width: width)
            return button
        }

        let bodyTitle = NSLocalizedString("Body", comment: "Formatting toolbar body style button")
        let headings = menuButton(title: bodyTitle,
                                  tip: NSLocalizedString("Text Style", comment: "Formatting toolbar heading button"),
                                  action: #selector(showHeadingMenu(_:)),
                                  width: 70)
        headings.identifier = NSUserInterfaceItemIdentifier("heading")

        let emphasis = glassButtonGroup([
            iconButton("bold", command: "bold",
                       tip: NSLocalizedString("Bold", comment: "Formatting toolbar tooltip")),
            iconButton("italic", command: "italic",
                       tip: NSLocalizedString("Italic", comment: "Formatting toolbar tooltip")),
            iconButton("strikethrough", command: "strikethrough",
                       tip: NSLocalizedString("Strikethrough", comment: "Formatting toolbar tooltip")),
        ])
        let link = glassButtonGroup([
            iconButton("link", command: "link",
                       tip: NSLocalizedString("Link", comment: "Formatting toolbar tooltip"),
                       width: 28),
        ])
        let lists = menuButton(symbol: "list.bullet",
                               tip: NSLocalizedString("Lists", comment: "Formatting toolbar list menu"),
                               action: #selector(showListMenu(_:)),
                               width: 54)
        let add = menuButton(symbol: "plus",
                             tip: NSLocalizedString("More Formatting", comment: "Formatting toolbar more menu"),
                             action: #selector(showMoreFormattingMenu(_:)),
                             width: 52)

        let groupStack = NSStackView(views: [
            glassButtonGroup([headings]),
            emphasis,
            link,
            glassButtonGroup([lists]),
            glassButtonGroup([add]),
        ])
        groupStack.orientation = .horizontal
        groupStack.alignment = .centerY
        groupStack.spacing = 8
        groupStack.translatesAutoresizingMaskIntoConstraints = false
        groupStack.setHuggingPriority(.required, for: .horizontal)
        groupStack.setContentCompressionResistancePriority(.required, for: .horizontal)

        // The container batches the real glass descendants below; unlike an
        // NSGlassEffectView it does not render a surface of its own.
        let groups = NSGlassEffectContainerView()
        groups.spacing = 4
        groups.contentView = groupStack
        groups.translatesAutoresizingMaskIntoConstraints = false
        groups.setContentHuggingPriority(.required, for: .horizontal)
        groups.setContentCompressionResistancePriority(.required, for: .horizontal)
        NSLayoutConstraint.activate([
            groupStack.leadingAnchor.constraint(equalTo: groups.leadingAnchor),
            groupStack.trailingAnchor.constraint(equalTo: groups.trailingAnchor),
            groupStack.topAnchor.constraint(equalTo: groups.topAnchor),
            groupStack.bottomAnchor.constraint(equalTo: groups.bottomAnchor),
        ])

        let container = EditAccessoryContainerView(floatingGlass: true)
        container.addSubview(groups)
        container.cursorContentView = groups
        // macOS 27 supplies the native header edge; macOS 26 needs this.
        if #unavailable(macOS 27.0) {
            let headerSeparator = NSBox()
            headerSeparator.boxType = .separator
            headerSeparator.translatesAutoresizingMaskIntoConstraints = false
            container.addSubview(headerSeparator)
            NSLayoutConstraint.activate([
                headerSeparator.leadingAnchor.constraint(equalTo: container.leadingAnchor),
                headerSeparator.trailingAnchor.constraint(equalTo: container.trailingAnchor),
                headerSeparator.topAnchor.constraint(equalTo: container.topAnchor),
            ])
        }
        NSLayoutConstraint.activate([
            // Float at the editor's trailing edge, independent of the page's
            // text gutter or centered reading column.
            groups.leadingAnchor.constraint(greaterThanOrEqualTo: container.leadingAnchor, constant: 12),
            groups.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -20),
            groups.topAnchor.constraint(equalTo: container.topAnchor, constant: 8),
            groups.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])

        mainSplit?.installFormattingBar(container)
        editBar = container
    }

    private func glassButtonGroup(_ views: [NSView]) -> NSGlassEffectView {
        let stack = NSStackView(views: views)
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 0
        stack.translatesAutoresizingMaskIntoConstraints = false

        // One surface per group keeps B/I/S in a single capsule. On systems
        // with interactive glass, the material itself follows the pointer.
        let glass = FormattingGlassView()
        glass.style = .regular
        glass.cornerRadius = 14
        if #available(macOS 27.0, *) {
            glass.effectIsInteractive = true
        }
        glass.contentView = stack
        glass.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: glass.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: glass.trailingAnchor),
            stack.topAnchor.constraint(equalTo: glass.topAnchor),
            stack.bottomAnchor.constraint(equalTo: glass.bottomAnchor),
            glass.heightAnchor.constraint(equalToConstant: 28),
        ])
        glass.setContentHuggingPriority(.required, for: .horizontal)
        return glass
    }

    private func configureGlassButton(_ button: NSButton, tip: String, width: CGFloat) {
        // Use a capsule for the native per-button feedback.
        // Interactive glass owns the hover on newer systems, so don't draw
        // a second bezel over its pointer-following highlight.
        button.bezelStyle = .accessoryBarAction
        button.borderShape = .capsule
        button.controlSize = .regular
        button.showsBorderOnlyWhileMouseInside = true
        // Accessory controls otherwise inherit a muted foreground. Keep the
        // formatting glyphs prominent while adapting to light/dark appearance.
        button.contentTintColor = .textColor
        button.tintProminence = .none
        if #available(macOS 27.0, *) {
            button.isBordered = false
            button.showsBorderOnlyWhileMouseInside = false
        }
        button.toolTip = tip
        button.translatesAutoresizingMaskIntoConstraints = false
        button.widthAnchor.constraint(equalToConstant: width).isActive = true
        button.heightAnchor.constraint(equalToConstant: 28).isActive = true
    }

    private func composedImage(_ image: NSImage,
                               chevron: NSImage,
                               gap: CGFloat) -> NSImage {
        let size = NSSize(width: image.size.width + gap + chevron.size.width,
                          height: max(image.size.height, chevron.size.height))
        let face = NSImage(size: size, flipped: false) { _ in
            image.draw(at: NSPoint(x: 0, y: (size.height - image.size.height) / 2),
                       from: .zero, operation: .sourceOver, fraction: 1)
            chevron.draw(at: NSPoint(x: image.size.width + gap,
                                     y: (size.height - chevron.size.height) / 2),
                         from: .zero, operation: .sourceOver, fraction: 1)
            return true
        }
        // Preserve the symbols' semantic foreground instead of applying the
        // accessory button's muted template-image treatment a second time.
        face.isTemplate = false
        return face
    }

    private func hideEditAccessory() {
        formattingPopover?.close()
        formattingPopover = nil
        guard editBar != nil else { return }
        mainSplit?.removeFormattingBar()
        editBar = nil
    }

    /// Leaves edit-mode chrome as one operation: drops the formatting bar
    /// and refreshes the toolbar pencil state.
    func dismissEditChrome() {
        hideEditAccessory()
        updateEditToolbarItem()
    }

    @objc private func formatCommand(_ sender: NSButton) {
        guard let command = sender.identifier?.rawValue else { return }
        if command == "link" {
            showLinkPopover(sender)
            return
        }
        formatMarkdown(command)
    }

    private func showLinkPopover(_ sender: NSButton) {
        formattingPopover?.close()
        guard let editor = mainSplit?.editorViewController else { return }
        let popover = NSPopover()
        popover.behavior = .transient
        formattingPopover = popover
        editor.fetchLinkSelection { [weak self, weak sender, weak editor] selection in
            guard let self, let sender, let editor, let selection, sender.window != nil,
                  self.isEditing, self.formattingPopover === popover else { return }
            let host = NSHostingController(rootView: LinkFormatPopover(text: selection.text, cancel: { [weak self] in
                self?.formattingPopover?.close()
                self?.formattingPopover = nil
            }, save: { [weak self, weak editor] text, url in
                self?.formattingPopover?.close()
                self?.formattingPopover = nil
                editor?.insertLink(text: text, url: url, from: selection.from, to: selection.to)
            }))
            host.sizingOptions = .preferredContentSize
            popover.contentViewController = host
            popover.show(relativeTo: sender.bounds, of: sender, preferredEdge: .maxY)
        }
    }

    @objc private func showHeadingMenu(_ sender: NSButton) {
        showHeadingPopover(sender)
    }

    @objc private func showListMenu(_ sender: NSButton) {
        showListPopover(sender)
    }

    private func showListPopover(_ sender: NSButton) {
        formattingPopover?.close()
        guard let editor = mainSplit?.editorViewController else { return }
        let popover = NSPopover()
        popover.behavior = .transient
        formattingPopover = popover
        editor.fetchListStyle { [weak self, weak sender, weak editor] style in
            guard let self, let sender, let editor, sender.window != nil,
                  self.isEditing, self.formattingPopover === popover else { return }
            let host = NSHostingController(rootView: ListFormatPopover(selectedStyle: style) { [weak self, weak editor] style in
                self?.formattingPopover?.close()
                self?.formattingPopover = nil
                editor?.setListStyle(style)
            })
            host.sizingOptions = .preferredContentSize
            popover.contentViewController = host
            popover.show(relativeTo: sender.bounds, of: sender, preferredEdge: .maxY)
        }
    }

    private func showHeadingPopover(_ sender: NSButton) {
        if let formattingPopover, formattingPopover.isShown {
            formattingPopover.close()
            self.formattingPopover = nil
            return
        }
        guard let editor = mainSplit?.editorViewController else { return }
        let popover = NSPopover()
        popover.behavior = .transient
        formattingPopover = popover
        editor.fetchHeadingLevel { [weak self, weak sender] level in
            guard let self, let sender, sender.window != nil,
                  self.isEditing, self.formattingPopover === popover else { return }
            self.updateHeadingButton(sender, level: level)
            self.editBar?.layoutSubtreeIfNeeded()
            let selectedLevel = level
            let host = NSHostingController(rootView: HeadingFormatPopover(selectedLevel: level) { [weak self, weak sender] level in
                self?.formattingPopover?.close()
                self?.formattingPopover = nil
                guard level != selectedLevel else { return }
                if let sender { self?.updateHeadingButton(sender, level: level) }
                self?.formatMarkdown("h\(level)")
            })
            host.sizingOptions = .preferredContentSize
            popover.contentViewController = host
            popover.show(relativeTo: sender.bounds, of: sender, preferredEdge: .maxY)
        }
    }

    func updateFormattingSelection(heading: Int, commands: Set<String>) {
        guard isEditing, let editBar else { return }
        func update(_ view: NSView) {
            if let button = view as? NSButton, let id = button.identifier?.rawValue {
                if id == "heading" {
                    updateHeadingButton(button, level: heading)
                } else if ["bold", "italic", "strikethrough", "link"].contains(id) {
                    let active = commands.contains(id)
                    if id != "link" {
                        // Selection tints only the glyph. Keeping the native
                        // button off avoids its filled selected bezel.
                        button.state = .off
                        button.contentTintColor = active ? .systemBlue : .textColor
                        let configuration = NSImage.SymbolConfiguration(pointSize: 13, weight: .medium)
                            .applying(NSImage.SymbolConfiguration(paletteColors: [active ? .systemBlue : .textColor]))
                        let image = NSImage(systemSymbolName: id, accessibilityDescription: button.toolTip)?
                            .withSymbolConfiguration(configuration)
                        image?.isTemplate = false
                        button.image = image
                    } else {
                        button.state = active ? .on : .off
                    }
                }
            }
            view.subviews.forEach(update)
        }
        update(editBar)
    }

    private func updateHeadingButton(_ button: NSButton, level: Int) {
        button.title = level == 0
            ? NSLocalizedString("Body", comment: "Formatting toolbar body style")
            : String(format: NSLocalizedString("Heading %d", comment: "Formatting toolbar heading"), level)
        let padding: CGFloat
        if #available(macOS 27.0, *) {
            padding = 16
        } else {
            padding = 12
        }
        button.constraints.first {
            $0.firstAttribute == .width && $0.secondItem == nil
        }?.constant = max(70, ceil(button.intrinsicContentSize.width) + padding)
    }

    @objc private func showMoreFormattingMenu(_ sender: NSButton) {
        showStylingPopover(sender)
    }

    private func showStylingPopover(_ sender: NSButton) {
        formattingPopover?.close()
        guard let editor = mainSplit?.editorViewController else { return }
        let popover = NSPopover()
        popover.behavior = .transient
        formattingPopover = popover
        editor.fetchBlockStyle { [weak self, weak sender, weak editor] style in
            guard let self, let sender, let editor, sender.window != nil,
                  self.isEditing, self.formattingPopover === popover else { return }
            let host = NSHostingController(rootView: StylingFormatPopover(selectedStyle: style) { [weak self, weak editor] style, language in
                self?.formattingPopover?.close()
                self?.formattingPopover = nil
                editor?.setBlockStyle(style, language: language)
            })
            host.sizingOptions = .preferredContentSize
            popover.contentViewController = host
            popover.show(relativeTo: sender.bounds, of: sender, preferredEdge: .maxY)
        }
    }

    /// File > Save (⌘S): save pending edits in either mode without switching modes.
    /// Intercepts the responder chain ahead of MarkdownDocument, whose
    /// NSDocument save machinery stays disabled.
    @IBAction func saveDocument(_ sender: Any?) {
        guard isEditing || hasPendingEditorChanges else {
            NSSound.beep()
            return
        }
        commitEdits(exitAfter: false)
    }
}

private struct StylingFormatPopover: View {
    let selectedStyle: String
    let select: (String, String) -> Void
    @State private var hoveredStyle: String?
    @State private var showsLanguages = false
    private let rows = [
        ("none", "None", "paragraphsign"),
        ("quote", "Blockquote", "text.quote"),
        ("code", "Code", "curlybraces"),
        ("plain", "Plain Text Block", "text.alignleft"),
        ("fenced", "Code Block", "curlybraces.square"),
        ("table", "Table", "tablecells"),
    ]

    var body: some View {
        VStack(spacing: 2) {
            Text("Styling").font(.system(size: 11)).foregroundStyle(.secondary).padding(.bottom, 4)
            ForEach(rows, id: \.0) { row in
                Group {
                    if row.0 == "fenced" {
                        Button { showsLanguages.toggle() } label: { rowLabel(row) }
                        .buttonStyle(.plain)
                        .popover(isPresented: $showsLanguages, arrowEdge: .leading) {
                            CodeLanguagePopover { language in
                                CodeLanguageCatalog.remember(language)
                                select("fenced", language)
                            }
                        }
                    } else {
                        Button { select(row.0, "") } label: { rowLabel(row) }
                            .buttonStyle(.plain)
                    }
                }
                .accessibilityValue(selectedStyle == row.0 ? Text("Selected") : Text(""))
                .onHover { hoveredStyle = $0 ? row.0 : nil }
            }
        }
        .padding(8)
        .frame(width: 200)
    }

    private func rowLabel(_ row: (String, String, String)) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark").font(.system(size: 12, weight: .medium))
                .opacity(selectedStyle == row.0 ? 1 : 0).frame(width: 14)
            Image(systemName: row.2).foregroundStyle(.secondary).frame(width: 16)
            Text(LocalizedStringKey(row.1))
            Spacer(minLength: 0)
            if row.0 == "fenced" {
                Image(systemName: "chevron.right").font(.system(size: 9)).foregroundStyle(.secondary)
            }
        }
        .font(.system(size: 13))
        .foregroundStyle(.primary)
        .padding(.horizontal, 8)
        .frame(height: 26)
        .contentShape(Rectangle())
        .background(hoveredStyle == row.0 ? Color.primary.opacity(0.08) : .clear,
                    in: RoundedRectangle(cornerRadius: 5))
    }
}

private struct CodeLanguagePopover: View {
    let select: (String) -> Void
    @State private var query = ""
    @State private var hoveredLanguage: String?
    @FocusState private var filterFocused: Bool
    private let recent = CodeLanguageCatalog.recent()

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 4) {
                Image(systemName: "line.3.horizontal.decrease.circle")
                    .foregroundStyle(.secondary)
                TextField("Filter", text: $query)
                    .textFieldStyle(.plain)
                    .focused($filterFocused)
                    .accessibilityLabel("Filter code languages")
                    .onSubmit {
                        let matches = CodeLanguageCatalog.matching(query)
                        if !query.isEmpty, let first = matches.first { select(first.id) }
                    }
            }
            .font(.system(size: 12))
            .padding(.horizontal, 7)
            .frame(height: 24)
            .background(Color.primary.opacity(0.05), in: Capsule())

            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        if !recent.isEmpty { section("Recent", languages: recent, key: "recent") }
                        section("Common", languages: CodeLanguageCatalog.options(for: CodeLanguageCatalog.commonIDs), key: "common")
                        section("All Languages", languages: CodeLanguageCatalog.all, key: "all")
                    } else {
                        let matches = CodeLanguageCatalog.matching(query)
                        if matches.isEmpty {
                            Text("No matching languages")
                                .font(.system(size: 12)).foregroundStyle(.secondary)
                                .padding(8)
                        } else {
                            section("All Languages", languages: matches, key: "filter")
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(8)
        .frame(width: 220, height: 358)
        .onAppear { filterFocused = true }
    }

    private func section(_ title: LocalizedStringKey, languages: [CodeLanguageOption], key: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title).font(.system(size: 11)).foregroundStyle(.secondary)
                .padding(.horizontal, 4).padding(.top, 3)
            ForEach(languages) { language in
                let rowID = "\(key)-\(language.id)"
                Button { select(language.id) } label: {
                    HStack(spacing: 7) {
                        Group {
                            if language.id == "swift" { Image(systemName: "swift") }
                            else if language.id == "bash" { Image(systemName: "terminal") }
                            else { Text(language.glyph).font(.system(size: 11, design: .monospaced)) }
                        }
                        .foregroundStyle(.secondary)
                        .frame(width: 18)
                        Text(language.name).font(.system(size: 13))
                        Spacer(minLength: 0)
                    }
                    .foregroundStyle(.primary)
                    .padding(.leading, 18).padding(.trailing, 6)
                    .frame(height: 22)
                    .contentShape(Rectangle())
                    .background(hoveredLanguage == rowID ? Color.primary.opacity(0.08) : .clear,
                                in: RoundedRectangle(cornerRadius: 4))
                }
                .buttonStyle(.plain)
                .onHover { hoveredLanguage = $0 ? rowID : nil }
            }
        }
    }
}

private struct ListFormatPopover: View {
    let selectedStyle: String
    let select: (String) -> Void
    @State private var hoveredStyle: String?

    private let rows: [(id: String, title: String, symbol: String)] = [
        ("none", NSLocalizedString("None", comment: "List style"), "paragraphsign"),
        ("bullet", NSLocalizedString("Bulleted List", comment: "List style"), "list.bullet"),
        ("ordered", NSLocalizedString("Numbered List", comment: "List style"), "list.number"),
        ("task", NSLocalizedString("Task List", comment: "List style"), "checklist"),
    ]

    var body: some View {
        VStack(spacing: 2) {
            Text("List").font(.system(size: 11)).foregroundStyle(.secondary).padding(.bottom, 4)
            ForEach(rows, id: \.id) { row in
                Button { select(row.id) } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark")
                            .font(.system(size: 12, weight: .medium))
                            .opacity(selectedStyle == row.id ? 1 : 0)
                            .frame(width: 14)
                        Image(systemName: row.symbol).foregroundStyle(.secondary).frame(width: 16)
                        Text(row.title)
                        Spacer(minLength: 0)
                    }
                    .font(.system(size: 13))
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 8)
                    .frame(height: 26)
                    .contentShape(Rectangle())
                    .background(hoveredStyle == row.id ? Color.primary.opacity(0.08) : .clear,
                                in: RoundedRectangle(cornerRadius: 5))
                }
                .buttonStyle(.plain)
                .accessibilityValue(selectedStyle == row.id ? Text("Selected") : Text(""))
                .onHover { hoveredStyle = $0 ? row.id : nil }
            }
        }
        .padding(8)
        .frame(width: 200)
    }
}

private struct LinkFormatPopover: View {
    @State var text: String
    @State private var url = ""
    @FocusState private var textFocused: Bool
    let cancel: () -> Void
    let save: (String, String) -> Void

    private var destination: String { url.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var canSave: Bool { !destination.isEmpty && !destination.contains(where: \.isNewline) }

    var body: some View {
        VStack(spacing: 10) {
            Text("Link").font(.system(size: 11)).foregroundStyle(.secondary)
            Grid(horizontalSpacing: 8, verticalSpacing: 8) {
                GridRow {
                    Text("Text:").foregroundStyle(.secondary).frame(width: 34, alignment: .trailing)
                    TextField("Display text (optional)", text: $text)
                        .focused($textFocused)
                        .accessibilityLabel("Display text")
                }
                GridRow {
                    Text("URL:").foregroundStyle(.secondary).frame(width: 34, alignment: .trailing)
                    TextField("https://example.com", text: $url).accessibilityLabel("URL")
                }
            }
            .textFieldStyle(.plain)
            HStack(spacing: 8) {
                Spacer()
                Button("Cancel", action: cancel).keyboardShortcut(.cancelAction)
                Button("Save") { save(text, destination) }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canSave)
            }
        }
        .font(.system(size: 13))
        .padding(16)
        .frame(width: 320)
        .onAppear { textFocused = true }
    }
}

private struct HeadingFormatPopover: View {
    let selectedLevel: Int
    let select: (Int) -> Void
    @State private var hoveredLevel: Int?

    var body: some View {
        VStack(spacing: 2) {
            Text("Format")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .padding(.bottom, 4)
            ForEach(0...6, id: \.self) { level in
                Button { select(level) } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark")
                            .font(.system(size: 12, weight: .medium))
                            .opacity(selectedLevel == level ? 1 : 0)
                            .frame(width: 14)
                        Text(level == 0 ? NSLocalizedString("Body", comment: "Formatting style")
                             : String(format: NSLocalizedString("Heading %d", comment: "Formatting style"), level))
                            .font(.system(size: [13, 22, 20, 17, 15, 13, 12][level],
                                          weight: level == 0 ? .regular : .bold))
                        Spacer(minLength: 0)
                    }
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 8)
                    .frame(height: level == 1 ? 32 : 26)
                    .contentShape(Rectangle())
                    .background(hoveredLevel == level ? Color.primary.opacity(0.08) : .clear,
                                in: RoundedRectangle(cornerRadius: 5))
                }
                .buttonStyle(.plain)
                .accessibilityValue(selectedLevel == level ? Text("Selected") : Text(""))
                .onHover { hoveredLevel = $0 ? level : nil }
            }
        }
        .padding(8)
        .frame(width: 200)
    }
}

/// Center the label and chevron as one face, independently of AppKit's
/// borderless trailing-image baseline. The entire capsule remains clickable.
@available(macOS 27.0, *)
private final class CenteredFormattingButtonCell: NSButtonCell {
    override func drawInterior(withFrame cellFrame: NSRect, in controlView: NSView) {
        let label = NSAttributedString(string: title, attributes: [
            .font: font ?? NSFont.systemFont(ofSize: 13, weight: .medium),
            .foregroundColor: isEnabled ? NSColor.textColor : NSColor.disabledControlTextColor,
        ])
        let labelSize = label.size()
        let imageSize = image?.size ?? .zero
        let gap: CGFloat = 5
        let contentWidth = labelSize.width + gap + imageSize.width
        let leadingX = cellFrame.midX - contentWidth / 2
        label.draw(at: NSPoint(x: leadingX, y: cellFrame.midY - labelSize.height / 2))
        image?.draw(in: NSRect(x: leadingX + labelSize.width + gap,
                              y: cellFrame.midY - imageSize.height / 2,
                              width: imageSize.width, height: imageSize.height),
                    from: .zero, operation: .sourceOver,
                    fraction: isEnabled ? 1 : 0.5, respectFlipped: true, hints: nil)
    }
}

/// Cursor ownership belongs to the visible glass surface. Tracking a cached
/// child frame from the full-width host misses changes made by Auto Layout.
private final class FormattingGlassView: NSGlassEffectView {
    private var pointerTrackingArea: NSTrackingArea?

    override func resetCursorRects() {
        super.resetCursorRects()
        addCursorRect(bounds, cursor: .arrow)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let pointerTrackingArea {
            removeTrackingArea(pointerTrackingArea)
        }
        let area = NSTrackingArea(
            rect: .zero,
            options: [.cursorUpdate, .mouseEnteredAndExited, .mouseMoved,
                      .activeInKeyWindow, .inVisibleRect, .enabledDuringMouseDrag],
            owner: self
        )
        addTrackingArea(area)
        pointerTrackingArea = area
    }

    override func cursorUpdate(with event: NSEvent) {
        super.cursorUpdate(with: event)
        NSCursor.arrow.set()
    }

    override func mouseEntered(with event: NSEvent) {
        super.mouseEntered(with: event)
        NSCursor.arrow.set()
    }

    override func mouseMoved(with event: NSEvent) {
        super.mouseMoved(with: event)
        NSCursor.arrow.set()
    }
}
