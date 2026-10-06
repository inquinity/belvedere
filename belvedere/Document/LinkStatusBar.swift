//
//  LinkStatusBar.swift
//  belvedere
//
//  Fork-only. A small bar at the bottom-left of the reading view that names
//  where the link under the pointer goes, as a browser's status bar does.
//
//  It is native, drawn by the window and not by the page, so document content
//  can neither style it nor spoof it. The text comes from
//  `LinkDestinationLabel`, which works from the resolved address.
//

import Cocoa

final class LinkStatusBar: NSVisualEffectView {

    private let label = NSTextField(labelWithString: "")

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        material = .menu
        blendingMode = .withinWindow
        state = .active
        wantsLayer = true
        layer?.cornerRadius = 6
        layer?.maskedCorners = [.layerMaxXMaxYCorner]
        layer?.borderWidth = 0.5
        layer?.borderColor = NSColor.separatorColor.cgColor
        isHidden = true
        alphaValue = 0

        label.font = .systemFont(ofSize: 11)
        label.textColor = .labelColor
        // Tail, never middle: the start of an address is its host, and that is
        // the part that must stay visible when the window is narrow.
        label.lineBreakMode = .byTruncatingTail
        label.maximumNumberOfLines = 1
        label.allowsDefaultTighteningForTruncation = false
        label.translatesAutoresizingMaskIntoConstraints = false
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            label.topAnchor.constraint(equalTo: topAnchor, constant: 3),
            label.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -3),
        ])

        // Not part of the document for assistive technology to read through:
        // the destination is the link's own accessibility value.
        setAccessibilityElement(false)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    /// Never takes a click: the bar sits over the page, and a click on it must
    /// reach the document underneath.
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    /// Shows `text`, or hides the bar when it is nil.
    func show(_ text: String?) {
        guard let text, !text.isEmpty else {
            guard !isHidden else { return }
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = 0.1
                animator().alphaValue = 0
            }, completionHandler: { [weak self] in
                guard let self, self.alphaValue == 0 else { return }
                self.isHidden = true
            })
            return
        }
        label.stringValue = text
        toolTip = nil
        if isHidden { isHidden = false }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.1
            animator().alphaValue = 1
        }
    }
}
