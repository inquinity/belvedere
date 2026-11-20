//
//  DocumentLoadingOverlayView.swift
//  belvedere
//
//  "Loading…" and a spinner on a glass panel, centered over the reader
//  while a slow file read is in flight — typically a cloud file macOS is
//  still downloading. Shown for reads that go through the window's file
//  loader: the navigator, links, Back/Forward and reloads. A document opened
//  from Finder or File > Open is read before its window exists.
//

import Cocoa

final class DocumentLoadingOverlayView: NSView {
    private let spinner = NSProgressIndicator()

    init() {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false

        let label = NSTextField(labelWithString: NSLocalizedString("Loading…", comment: "Reader overlay while a file loads"))
        label.font = .systemFont(ofSize: NSFont.systemFontSize + 1, weight: .medium)
        label.textColor = .secondaryLabelColor

        spinner.style = .spinning
        spinner.controlSize = .small
        spinner.isIndeterminate = true
        // The label already says what's happening; one VoiceOver stop.
        spinner.setAccessibilityElement(false)

        let stack = NSStackView(views: [label, spinner])
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false

        // Padding as explicit constraints: a horizontal stack view drops
        // its top and bottom edgeInsets when nothing else sets its height.
        let content = NSView()
        content.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(stack)

        // The same Liquid Glass surface as the Search for Document palette.
        let panel = NSGlassEffectView()
        panel.style = .regular
        panel.cornerRadius = 14
        panel.contentView = content
        panel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(panel)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -16),
            stack.topAnchor.constraint(equalTo: content.topAnchor, constant: 10),
            stack.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -10),
            content.leadingAnchor.constraint(equalTo: panel.leadingAnchor),
            content.trailingAnchor.constraint(equalTo: panel.trailingAnchor),
            content.topAnchor.constraint(equalTo: panel.topAnchor),
            content.bottomAnchor.constraint(equalTo: panel.bottomAnchor),
            panel.leadingAnchor.constraint(equalTo: leadingAnchor),
            panel.trailingAnchor.constraint(equalTo: trailingAnchor),
            panel.topAnchor.constraint(equalTo: topAnchor),
            panel.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil {
            spinner.stopAnimation(nil)
        } else {
            spinner.startAnimation(nil)
        }
    }

    /// Clicks pass through to the page underneath.
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}
