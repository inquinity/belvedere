//
//  InfoPopoverButton.swift
//  md-preview
//
//  Fork-only. An ⓘ button for Settings that explains a choice in a popover.
//

import SwiftUI

/// An ⓘ button that opens an explanation in a popover when clicked.
///
/// A click rather than a `.help` tooltip: the explanation is several
/// sentences, a hover tooltip hides it behind a delay most readers never
/// wait out, and a popover can be reached from the keyboard and read by
/// VoiceOver. Its own file because it is the first such callout in
/// Settings; new files cost nothing when upstream changes the panes.
struct InfoPopoverButton<Content: View>: View {
    private let accessibilityLabel: String
    private let content: Content
    @State private var isPresented = false

    init(accessibilityLabel: String, @ViewBuilder content: () -> Content) {
        self.accessibilityLabel = accessibilityLabel
        self.content = content()
    }

    var body: some View {
        Button {
            isPresented.toggle()
        } label: {
            Image(systemName: "info.circle")
                .foregroundStyle(.secondary)
        }
        .buttonStyle(.borderless)
        .accessibilityLabel(accessibilityLabel)
        .popover(isPresented: $isPresented, arrowEdge: .bottom) {
            content
                .font(.callout)
                .frame(width: 320, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
                .padding(14)
        }
    }
}
