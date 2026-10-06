//
//  ContentViewController.swift
//  belvedere
//

import Cocoa
import WebKit

/// Where the preview should land after the next document render — a link
/// fragment or a restored history scroll offset.
enum NavigationScrollTarget {
    case anchor(String)
    case position(CGFloat)
}

final class ContentViewController: NSViewController {

    private static let pageZoomDefaultsKey = TextSizeSetting.defaultsKey

    private var webView: MarkdownWebView!
    private var toolbarGutterView: PreviewToolbarGutterView!
    private var toolbarGutterHeightConstraint: NSLayoutConstraint?
    private var webViewCenteredLeadingConstraint: NSLayoutConstraint?
    private var webViewCenteredConstraints: [NSLayoutConstraint] = []
    private var webViewFullWidthConstraints: [NSLayoutConstraint] = []
    private var pendingFlashWork: DispatchWorkItem?
    private var pendingPreviewScrollAnchor: SourceScrollAnchor?
    /// This window's width. It is the saved default as it was when the window
    /// opened, and only View ▸ Content Width changes it afterwards: a later
    /// change of the saved default reaches new windows and tabs, not this one.
    /// Never saved itself.
    private(set) var contentWidth: ContentWidthSetting = .current
    /// Whether this window joins single new lines. Same rule as the width: the
    /// saved default as it was when the window opened, changed afterwards only
    /// by View ▸ Single New Lines, and never saved itself.
    private(set) var strictLineBreaks: Bool = StrictLineBreaksSetting.current
    private var shouldApplyPendingAnchorOnHeight = false
    private var pendingNavigationScrollTarget: NavigationScrollTarget?
    private var shouldApplyNavigationTargetOnHeight = false
    private var exportSource: ExportSource?
    /// Early attempts run against the blanked page shown during a file
    /// switch, where the target can't resolve yet — retry on a short timer
    /// (height events accelerate it), giving up after ~2s.
    private var navigationTargetRetriesLeft = 0
    private static let navigationTargetMaxRetries = 25
    private static let navigationTargetRetryInterval: TimeInterval = 0.08

    private struct ExportSource {
        let markdown: String
        let sourceURL: URL?
        let assetBaseURL: URL?
    }

    // Heading top offsets in CSS pixels, indexed by heading id. Compared in
    // CSS units so page zoom doesn't invalidate them.
    private var headingOffsetsCSS: [CGFloat] = []
    /// Where the reader was before a re-render, as a place in a section rather
    /// than a pixel or a source position. See `captureSectionAnchor`.
    private var pendingSectionAnchor: SectionAnchor?
    private var sectionAnchorRetries = 0
    private var lastActiveHeadingID: Int?
    /// Names where the link under the pointer goes. See `LinkStatusBar`.
    private let linkStatusBar = LinkStatusBar()
    private var pendingHeadingOffsetsRefresh: DispatchWorkItem?

    // Sidebar-click pin. Bounds events are ignored until `holdUntil`
    // (covers our own animation), then we measure scroll distance from
    // `anchor` (the click's target scroll position). Tiny moves —
    // rubber-band, small scrolls on near-fitting docs — stay below the
    // release threshold so the pin survives them. A doc that can't scroll
    // at all never even fires bounds events, so the pin sits forever.
    private var sticky: StickyPin?
    private struct StickyPin {
        let headingID: Int
        let holdUntil: DispatchTime
        let anchor: CGFloat
    }
    /// Covers `scrollDocument`'s 0.25s animation plus JS round-trip.
    private static let stickyHoldDuration: DispatchTimeInterval = .milliseconds(350)
    /// Viewport fraction the user must scroll past the pin's anchor to
    /// release it. ⅓ feels sticky enough for incidental moves but lets
    /// genuine page-scrolls take over.
    private static let stickyReleaseFraction: CGFloat = 1.0 / 3.0

    var activeHeadingDidChange: ((Int?) -> Void)?
    var zoomDidChange: ((CGFloat) -> Void)?
    var localMarkdownLinkActivated: ((URL) -> Void)?
    /// Fires once after a pending source scroll anchor (prepared via
    /// `prepareToRestoreSourceScrollAnchor`) has been applied to a fresh
    /// render. The edit-mode overlay uses it to hold its visibility swap until
    /// the preview underneath is positioned.
    var pendingAnchorRestored: (() -> Void)?

    override func loadView() {
        let container = DocumentBackgroundView(frame: .zero)
        container.translatesAutoresizingMaskIntoConstraints = false
        view = container

        webView = SpareReaderPool.shared.takeReader()
        webView.translatesAutoresizingMaskIntoConstraints = false
        webView.heightDidChange = { [weak self] _ in
            guard let self else { return }
            // Image load / font reflow shifted layout — re-measure offsets.
            self.scheduleHeadingOffsetsRefresh()
            self.applyPendingScrollAnchorIfNeeded()
            if self.shouldApplyNavigationTargetOnHeight,
               let target = self.pendingNavigationScrollTarget {
                self.shouldApplyNavigationTargetOnHeight = false
                self.attemptNavigationScrollTarget(target)
            }
        }
        webView.contentDidReplace = { [weak self] in
            // The fresh article is in the DOM; a same-height render never
            // fires heightDidChange, so this is the reliable signal.
            self?.applyPendingScrollAnchorIfNeeded()
            self?.updatePointerTracking()
            self?.linkStatusBar.show(nil)
            guard let self, self.webView.hasRequestedDocument else { return }
            SpareReaderPool.shared.documentDidPaint()
        }
        NotificationCenter.default.addObserver(self, selector: #selector(updatePointerTracking),
                                               name: UserDefaults.didChangeNotification, object: nil)
        webView.fragmentLinkActivated = { [weak self] fragment in
            self?.scrollToElement(id: fragment)
        }
        webView.pointerDocumentYDidChange = { [weak self] y in
            guard let self,
                  UserDefaults.standard.bool(forKey: "belvedere.outlineFollowsPointer") else { return }
            self.pointerHeadingID = self.headingOffsetsCSS.lastIndex(where: { $0 <= y })
            self.sticky = nil
            self.notifyActiveHeading(self.pointerHeadingID)
        }
        webView.localMarkdownLinkActivated = { [weak self] url in
            self?.localMarkdownLinkActivated?(url)
        }
        webView.linkHoverDidChange = { [weak self] text in
            self?.linkStatusBar.show(text)
        }
        webView.zoomDidChange = { [weak self] zoom in
            self?.webViewCenteredLeadingConstraint?.constant =
                -MarkdownHTML.preferredPageWidth * zoom / 2
            self?.zoomDidChange?(zoom)
        }
        webView.scrollDidChange = { [weak self] in
            self?.evaluateActiveHeading()
        }
        webView.enablePersistentZoom(defaultsKey: Self.pageZoomDefaultsKey)

        // The WKWebView paints its obscured toolbar strip with
        // underPageBackgroundColor. In centered mode the native gutter to
        // its left would otherwise expose the document background there,
        // producing a sharp color change at the web view's leading edge.
        toolbarGutterView = PreviewToolbarGutterView()
        toolbarGutterView.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(toolbarGutterView)
        container.addSubview(webView)
        // Above the page, so it can name a link's destination over the text.
        linkStatusBar.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(linkStatusBar, positioned: .above, relativeTo: webView)
        NSLayoutConstraint.activate([
            linkStatusBar.leadingAnchor.constraint(equalTo: webView.leadingAnchor),
            linkStatusBar.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            linkStatusBar.trailingAnchor.constraint(lessThanOrEqualTo: container.trailingAnchor, constant: -24),
        ])
        // In normal-width mode the web view starts at the centered article's
        // leading edge, leaving a native gutter between it and the split-view
        // divider. Keep that gutter part of the page's scrolling surface.
        container.scrollWheelTarget = webView.webView


        // Normal (centered) mode positions the web view in AppKit rather
        // than letting CSS auto-margins center the column inside the web
        // view. A sidebar/inspector reveal then *moves* the column —
        // applied synchronously with each animation frame — instead of
        // re-centering it, which forces the web process to re-run layout
        // asynchronously and made the column jitter for the duration of
        // the animation (#162). Only the leading edge is placed at the
        // centered column's position; the trailing edge always reaches the
        // container so WebKit's native overlay scrollbar sits at the
        // preview edge. The rendered article is leading-anchored
        // (ContentWidth.hostCentered), so the width the web view gains on
        // the trailing side is inert gutter and mid-animation width
        // changes cannot move the text. The leading constant tracks
        // pageZoom (zoomDidChange above) so the column keeps its 820
        // CSS-px measure at every zoom level.
        let centeredLeading = webView.leadingAnchor.constraint(
            equalTo: container.centerXAnchor,
            constant: -MarkdownHTML.preferredPageWidth * webView.pageZoom / 2)
        // Stay below the split items' holding priorities (content 250,
        // sidebar 260) so window resizing breaks this page-width preference
        // before AppKit changes the user's chosen sidebar width.
        centeredLeading.priority = .init(249)
        webViewCenteredLeadingConstraint = centeredLeading
        webViewCenteredConstraints = [
            centeredLeading,
            webView.leadingAnchor.constraint(greaterThanOrEqualTo: container.leadingAnchor)
        ]
        webViewFullWidthConstraints = [
            webView.leadingAnchor.constraint(equalTo: container.leadingAnchor)
        ]

        let toolbarGutterHeight = toolbarGutterView.heightAnchor.constraint(equalToConstant: 0)
        toolbarGutterHeightConstraint = toolbarGutterHeight
        NSLayoutConstraint.activate([
            toolbarGutterView.topAnchor.constraint(equalTo: container.topAnchor),
            toolbarGutterView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            toolbarGutterView.trailingAnchor.constraint(equalTo: webView.leadingAnchor),
            toolbarGutterHeight,
        ])

        // Keep the WKWebView viewport-sized and let WebKit own vertical
        // scrolling. Expanding it to the full document height creates an
        // enormous backing surface that loses Retina resolution on long docs.
        // Pinned to the container's top so content scrolls under the frosted
        // titlebar.
        let webViewTop = webView.topAnchor.constraint(equalTo: container.topAnchor)
        NSLayoutConstraint.activate([

            webViewTop,
            webView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            webView.trailingAnchor.constraint(equalTo: container.trailingAnchor)
        ])
        syncWebViewRenderSettings()
        applyContentWidthMode()
        container.appearanceDidChange = { [weak self] in
            self?.updateUnderPageBackgroundColor()
        }
        updateUnderPageBackgroundColor()
    }

    func display(
        markdown: String,
        sourceURL: URL?,
        assetBaseURL: URL?,
        containmentRoot: URL?
    ) {
        exportSource = ExportSource(
            markdown: markdown,
            sourceURL: sourceURL,
            assetBaseURL: assetBaseURL
        )
        if pendingPreviewScrollAnchor != nil {
            shouldApplyPendingAnchorOnHeight = true
        }
        if pendingNavigationScrollTarget != nil {
            shouldApplyNavigationTargetOnHeight = true
            // Height events don't re-fire when the new document lays out at
            // the same height — the timer guarantees an attempt.
            scheduleNavigationTargetAttempt()
        }
        resetScrollspy()
        webView.display(markdown: markdown, assetBaseURL: assetBaseURL, containmentRoot: containmentRoot)
        scheduleHeadingOffsetsRefresh()
    }

    func clearContent() {
        exportSource = nil
        resetScrollspy()
        webView.clearContent()
    }

    func sourceFileURLDidChange(_ sourceURL: URL) {
        guard let source = exportSource else { return }
        exportSource = ExportSource(
            markdown: source.markdown,
            sourceURL: sourceURL,
            assetBaseURL: sourceURL.deletingLastPathComponent()
        )
    }

    /// Drops scrollspy state before a doc swap so the previous doc's
    /// heading doesn't briefly stay marked.
    @objc private func updatePointerTracking() {
        let enabled = UserDefaults.standard.bool(forKey: "belvedere.outlineFollowsPointer")
        webView.webView.evaluateJavaScript("window.mdPreviewPointerTracking = \(enabled ? "true" : "false");", completionHandler: nil)
        if !enabled {
            pointerHeadingID = nil
            evaluateActiveHeading()
        }
    }

    private var pointerHeadingID: Int?

    private func resetScrollspy() {
        pointerHeadingID = nil
        headingOffsetsCSS = []
        sticky = nil
        notifyActiveHeading(nil)
    }

    private func notifyActiveHeading(_ headingID: Int?) {
        guard headingID != lastActiveHeadingID else { return }
        lastActiveHeadingID = headingID
        activeHeadingDidChange?(headingID)
    }

    func find(_ query: String,
              backwards: Bool = false,
              mode: SearchMode = .contains,
              completion: ((FindResult) -> Void)? = nil) {
        let pasteboard = NSPasteboard(name: .find)
        pasteboard.declareTypes([.string], owner: nil)
        pasteboard.setString(query, forType: .string)
        pendingFlashWork?.cancel()
        webView.find(query, backwards: backwards, mode: mode) { [weak self] result in
            guard let self else {
                completion?(result)
                return
            }
            if let top = result.top, let bottom = result.bottom {
                let needsScroll = !self.isMatchVisible(top: top, bottom: bottom)
                if needsScroll {
                    self.webView.scrollDocument(to: top)
                }
                let delay: TimeInterval = needsScroll ? 0.18 : 0
                let work = DispatchWorkItem { [weak self] in
                    self?.webView.flashCurrentMatch()
                }
                self.pendingFlashWork = work
                DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
            }
            completion?(result)
        }
    }

    private func isMatchVisible(top: CGFloat, bottom: CGFloat) -> Bool {
        let metrics = webView.scrollMetrics
        let visibleTop = metrics.position
        let visibleBottom = metrics.position + metrics.viewportHeight
        return top >= visibleTop && bottom <= visibleBottom
    }

    func printDocument() {
        guard let window = view.window, hasExportableDocument else { return }
        webView.printDocument(from: window)
    }

    var hasExportableDocument: Bool {
        exportSource != nil
    }

    func exportDocument() {
        guard let window = view.window, let source = exportSource else { return }
        webView.exportDocument(
            markdown: source.markdown,
            sourceURL: source.sourceURL,
            assetBaseURL: source.assetBaseURL,
            from: window
        )
    }

    func exportPDF() {
        guard let window = view.window, let source = exportSource else { return }
        webView.exportPDF(
            markdown: source.markdown,
            sourceURL: source.sourceURL,
            assetBaseURL: source.assetBaseURL,
            from: window
        )
    }

    func zoomIn() { webView.zoomIn() }
    func zoomOut() { webView.zoomOut() }
    func resetZoom() { webView.resetZoom() }
    var pageZoom: CGFloat { webView.pageZoom }

    /// Normalized top-of-viewport position used when handing the document to
    /// the editor, whose content height differs slightly from the preview.
    var scrollProgress: CGFloat {
        let metrics = webView.scrollMetrics
        let maxY = max(metrics.documentHeight - metrics.viewportHeight, 0)
        guard maxY > 0 else { return 0 }
        return min(max(metrics.position / maxY, 0), 1)
    }

    func sourceScrollAnchor(completion: @escaping (SourceScrollAnchor?) -> Void) {
        let visibleTop = webView.scrollMetrics.position
        webView.sourceAnchor(atDocumentY: visibleTop / webView.pageZoom, completion: completion)
    }

    func prepareToRestoreSourceScrollAnchor(_ anchor: SourceScrollAnchor?) {
        pendingPreviewScrollAnchor = anchor
    }

    func restoreSourceScrollAnchor(_ anchor: SourceScrollAnchor,
                                   completion: (() -> Void)? = nil) {
        webView.sourceOffset(forPosition: anchor.sourcePosition) { [weak self] sourceTop in
            guard let self, let sourceTop else {
                completion?()
                return
            }
            // topGap re-creates a viewport that sat inside the page padding
            // above the anchor's rendered top (document-top case).
            let target = max((sourceTop - anchor.topGap) * self.webView.pageZoom, 0)
            // A mode switch is a position hand-off, not a navigation: land
            // instantly. An animated scroll here reads as jitter when the
            // editor overlay is hidden.
            self.webView.scrollDocument(to: target, topMargin: 0, duration: 0)
            completion?()
        }
    }

    /// Applies the scroll anchor captured from the editor once the fresh
    /// article is in place, then reports it so the views can swap visibility.
    private func applyPendingScrollAnchorIfNeeded() {
        guard shouldApplyPendingAnchorOnHeight,
              let anchor = pendingPreviewScrollAnchor else { return }
        shouldApplyPendingAnchorOnHeight = false
        pendingPreviewScrollAnchor = nil
        restoreSourceScrollAnchor(anchor) { [weak self] in
            guard let self else { return }
            self.pendingAnchorRestored?()
            self.pendingAnchorRestored = nil
        }
    }

    /// Hands the web view this window's own width and single-new-line style,
    /// which its next render uses.
    private func syncWebViewRenderSettings() {
        webView.contentWidthSetting = contentWidth
        webView.strictLineBreaks = strictLineBreaks
    }

    /// Sets how this window shows single new lines, for the session.
    func setStrictLineBreaks(_ joins: Bool) {
        guard joins != strictLineBreaks else { return }
        strictLineBreaks = joins
        reloadPreviewForSettingChange()
    }

    /// Sets this window's width for the session.
    func setContentWidth(_ setting: ContentWidthSetting) {
        // Picking the width already shown changes nothing, so do not re-render.
        guard setting != contentWidth else { return }
        contentWidth = setting
        reloadPreviewForSettingChange()
    }

    /// Re-renders the page for a setting baked into it (width, font, line
    /// breaks). A new page starts at the top, so the reader's place is captured
    /// first, as the section they are in and how far through it they are, and
    /// put back once the new page has laid out. Headings are stable across a
    /// re-flow where pixels and source positions are not.
    func reloadPreviewForSettingChange() {
        // A reload already waiting to restore a place: the live page is the new,
        // still-loading one, so reading a place from it would give the top and
        // replace the right one. Keep the pending place and just reload.
        if pendingSectionAnchor != nil {
            applyContentWidthMode()
            view.layoutSubtreeIfNeeded()
            syncWebViewRenderSettings()
            webView.reloadPreviewForSettingChange()
            return
        }
        // Captured before anything changes, from the layout the reader was
        // looking at and not the one about to replace it.
        captureSectionAnchor { [weak self] anchor in
            guard let self else { return }
            self.applyContentWidthMode()
            // Switching width resizes the web view itself. Let that layout finish
            // before the page reloads.
            self.view.layoutSubtreeIfNeeded()
            self.syncWebViewRenderSettings()
            self.pendingSectionAnchor = anchor
            self.sectionAnchorRetries = 0
            self.webView.reloadPreviewForSettingChange()
            // The restore happens when the new page reports its headings.
            self.scheduleHeadingOffsetsRefresh()
        }
    }

    /// A place in a document: the heading above the top of the window and the
    /// fraction of the way from it to the next heading (or the end). With no
    /// heading above, the fraction is of the way to the first one.
    private struct SectionAnchor {
        let headingIndex: Int?
        let fraction: CGFloat
    }

    private func captureSectionAnchor(completion: @escaping (SectionAnchor) -> Void) {
        let metrics = webView.scrollMetrics
        let zoom = max(pageZoom, 0.001)
        let top = metrics.position / zoom
        let documentHeight = metrics.documentHeight / zoom
        webView.collectHeadingOffsets { offsets in
            func fraction(_ y: CGFloat, from start: CGFloat, to end: CGFloat) -> CGFloat {
                end > start ? min(max((y - start) / (end - start), 0), 1) : 0
            }
            guard let index = offsets.lastIndex(where: { $0 <= top + 1 }) else {
                completion(SectionAnchor(headingIndex: nil,
                                         fraction: fraction(top, from: 0, to: offsets.first ?? documentHeight)))
                return
            }
            let end = index + 1 < offsets.count ? offsets[index + 1] : documentHeight
            completion(SectionAnchor(headingIndex: index,
                                     fraction: fraction(top, from: offsets[index], to: end)))
        }
    }

    /// Scrolls to a captured place using freshly measured heading offsets.
    /// Returns false when the new page has not reported its headings yet.
    private func restoreSectionAnchor(_ anchor: SectionAnchor, offsets: [CGFloat]) -> Bool {
        let zoom = max(pageZoom, 0.001)
        let documentHeight = webView.scrollMetrics.documentHeight / zoom
        let start: CGFloat
        let end: CGFloat
        if let index = anchor.headingIndex {
            guard index < offsets.count else { return false }
            start = offsets[index]
            end = index + 1 < offsets.count ? offsets[index + 1] : documentHeight
        } else {
            start = 0
            end = offsets.first ?? documentHeight
        }
        guard documentHeight > 0 else { return false }
        let target = (start + anchor.fraction * max(end - start, 0)) * zoom
        webView.scrollDocument(to: target, topMargin: 0, duration: 0)
        return true
    }

    /// Repaints the native page background and restyles the loaded preview
    /// page after a theme color change in Settings.

    func applyReaderLayout() {
        webView.applyReaderLayout()
    }

    func applyThemeColors() {
        view.needsDisplay = true
        toolbarGutterView.needsDisplay = true
        updateUnderPageBackgroundColor()
        updateObscuredContentInsets()
        webView.applyThemeColors()
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        updateObscuredContentInsets()
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        // The chrome (toolbar, accessories) is final here; layout passes
        // before it attaches see a smaller contentLayoutRect.
        updateObscuredContentInsets()
        observeWindowChrome()
    }

    private var contentLayoutObservation: NSKeyValueObservation?

    /// Showing or hiding the native tab bar can change the content area
    /// without laying out this full-height view. Follow the window's chrome
    /// directly, as the editor does, without forcing a nested layout pass.
    private func observeWindowChrome() {
        contentLayoutObservation = view.window?.observe(\.contentLayoutRect) { [weak self] _, _ in
            MainActor.assumeIsolated {
                self?.updateObscuredContentInsets()
            }
        }
    }

    /// The search row sits in the content host beneath the native toolbar.
    weak var findOverlay: NSView?

    func chromeOverlaysDidChange() {
        updateObscuredContentInsets()
    }

    /// The whole obscured strip, including the native tab bar. AppKit
    /// exposes the tab bar as a bottom titlebar accessory; subtracting its
    /// height would let it consume the page's top padding.
    private var fullChromeTopInset: CGFloat {
        guard let window = view.window, let contentView = window.contentView else {
            return view.safeAreaInsets.top
        }
        var inset = contentView.bounds.height - window.contentLayoutRect.maxY
        if let find = findOverlay, find.window === window, !find.isHidden {
            inset += find.fittingSize.height - MainSplitViewController.tabBarOverlap(for: window)
        }
        return max(0, inset)
    }

    private func updateObscuredContentInsets() {
        // Theme-independent, and never 0: WebKit adopts the titlebar inset
        // automatically and an explicit 0 stomps that for the
        // web view's lifetime — the page then collides with the toolbar
        // until the window is recreated. Keeping the explicit value equal
        // to the chrome strip matches the automatic behavior exactly.
        let inset = fullChromeTopInset
        if toolbarGutterHeightConstraint?.constant != inset {
            toolbarGutterHeightConstraint?.constant = inset
        }
        guard view.window != nil, inset > 0 else { return }
        if webView.webView.obscuredContentInsets.top != inset {
            webView.webView.obscuredContentInsets = NSEdgeInsets(
                top: inset, left: 0, bottom: 0, right: 0
            )
        }
    }

    /// The scroll pocket WebKit draws for the obscured strip takes its color
    /// from underPageBackgroundColor, not from the page CSS. Set on theme
    /// and appearance changes only — a system appearance change need not
    /// trigger layout, and assigning every layout pass repaints transitions.
    private func updateUnderPageBackgroundColor() {
        // WebKit snapshots a CGColor in the setter. Resolve even the system
        // fallback against this view's appearance, then reassign when it changes.
        let isDark = view.effectiveAppearance
            .bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        let color = ThemeColorsSetting.current.color(
            .windowBackground, isDark ? .dark : .light
        ) ?? .clear
        view.effectiveAppearance.performAsCurrentDrawingAppearance {
            webView.webView.underPageBackgroundColor = color.usingColorSpace(.sRGB) ?? color
        }
    }

    func applyTextSizeSetting() {
        webView.applyPersistedZoom()
    }

    /// Swaps the web view between the AppKit-centered page column and a
    /// full-bleed layout. See the loadView comment for why centering lives
    /// at the constraint layer instead of CSS.
    private func applyContentWidthMode() {
        switch contentWidth {
        case .quickLook:
            NSLayoutConstraint.deactivate(webViewFullWidthConstraints)
            NSLayoutConstraint.activate(webViewCenteredConstraints)
        case .fullWidth:
            NSLayoutConstraint.deactivate(webViewCenteredConstraints)
            NSLayoutConstraint.activate(webViewFullWidthConstraints)
        }
    }

    func scrollToHeading(index: Int) {
        webView.headingOffset(index: index) { [weak self] offset in
            guard let self, let offset else { return }
            self.webView.scrollDocument(to: offset)
        }
    }

    /// Pin a heading active immediately so even a no-op scroll (last
    /// heading on a short doc) gives feedback. The pin survives small
    /// scroll movements; only a viewport-fraction scroll away from where
    /// the click landed releases it.
    func markHeadingActiveFromClick(_ headingID: Int) {
        let anchor = expectedScrollPosition(forHeading: headingID)
            ?? webView.scrollMetrics.position
        sticky = StickyPin(headingID: headingID,
                           holdUntil: .now() + Self.stickyHoldDuration,
                           anchor: anchor)
        notifyActiveHeading(headingID)
    }

    /// Where `scrollDocument` would land for `headingID` — the same
    /// clamped target the click animation aims at. Used as the pin's
    /// distance reference.
    private func expectedScrollPosition(forHeading headingID: Int) -> CGFloat? {
        guard headingID >= 0,
              headingID < headingOffsetsCSS.count else { return nil }
        let metrics = webView.scrollMetrics
        let zoom = max(webView.pageZoom, 0.001)
        let topMargin: CGFloat = 12
        let y = headingOffsetsCSS[headingID] * zoom
        let maxY = max(metrics.documentHeight - metrics.viewportHeight, 0)
        return max(0, min(y - topMargin, maxY))
    }

    /// Scroll target applied once the next `display()` has rendered;
    /// `nil` drops a stale target.
    func prepareToScrollAfterNavigation(to target: NavigationScrollTarget?) {
        pendingNavigationScrollTarget = target
        shouldApplyNavigationTargetOnHeight = false
        navigationTargetRetriesLeft = target == nil ? 0 : Self.navigationTargetMaxRetries
    }

    /// Document opening can finish after display() has already started.
    /// Arm the target immediately and retry until the new page has geometry.
    func scrollToAnchorWhenReady(_ fragment: String) {
        prepareToScrollAfterNavigation(to: .anchor(fragment))
        shouldApplyNavigationTargetOnHeight = true
        scheduleNavigationTargetAttempt()
    }

    /// Immediate fragment scroll within the already-rendered document.
    func scrollToAnchor(_ fragment: String) {
        scrollToElement(id: fragment)
    }

    var currentScrollPosition: CGFloat {
        webView.scrollMetrics.position
    }

    private func attemptNavigationScrollTarget(_ target: NavigationScrollTarget) {
        guard webView.isScrollGeometrySynced else {
            retryNavigationTarget()
            return
        }
        switch target {
        case .anchor(let fragment):
            webView.elementOffset(id: fragment) { [weak self] offset in
                guard let self,
                      self.pendingNavigationScrollTarget != nil else { return }
                guard let offset else {
                    self.retryNavigationTarget()
                    return
                }
                self.pendingNavigationScrollTarget = nil
                self.webView.scrollDocument(to: offset)
            }
        case .position(let y):
            // Synced geometry can still be the blank page — hold out until
            // the offset is reachable, clamping only as a last resort.
            let metrics = webView.scrollMetrics
            let reachable = max(metrics.documentHeight - metrics.viewportHeight, 0)
            guard y <= reachable || navigationTargetRetriesLeft <= 0 else {
                retryNavigationTarget()
                return
            }
            pendingNavigationScrollTarget = nil
            // Exact restore: no top margin, no animation.
            webView.scrollDocument(to: y, topMargin: 0, duration: 0)
        }
    }

    private func retryNavigationTarget() {
        guard navigationTargetRetriesLeft > 0 else {
            pendingNavigationScrollTarget = nil
            return
        }
        navigationTargetRetriesLeft -= 1
        shouldApplyNavigationTargetOnHeight = true
        scheduleNavigationTargetAttempt()
    }

    private func scheduleNavigationTargetAttempt() {
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.navigationTargetRetryInterval) { [weak self] in
            guard let self, let target = self.pendingNavigationScrollTarget else { return }
            self.attemptNavigationScrollTarget(target)
        }
    }

    private func scrollToElement(id: String) {
        webView.elementOffset(id: id) { [weak self] offset in
            guard let self, let offset else { return }
            self.webView.scrollDocument(to: offset)
        }
    }

    // MARK: - Scrollspy

    private static let headingOffsetsRefreshDelay: TimeInterval = 0.05
    /// CSS-px window from the doc top in which a heading counts as the
    /// "lead" — close enough that body padding alone is what kept it
    /// below the activation line at scroll-top. Past this, the heading
    /// must earn its highlight by being scrolled past.
    private static let leadHeadingThreshold: CGFloat = 80

    private func scheduleHeadingOffsetsRefresh() {
        pendingHeadingOffsetsRefresh?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.refreshHeadingOffsets()
        }
        pendingHeadingOffsetsRefresh = work
        DispatchQueue.main.asyncAfter(
            deadline: .now() + Self.headingOffsetsRefreshDelay, execute: work
        )
    }

    private func refreshHeadingOffsets() {
        webView.collectHeadingOffsets { [weak self] offsets in
            guard let self else { return }
            self.headingOffsetsCSS = offsets
            if let anchor = self.pendingSectionAnchor {
                // Not while the old page is still the live one: headings read from
                // it would restore the place into a page that is about to go.
                if self.webView.isPageReady,
                   self.restoreSectionAnchor(anchor, offsets: offsets) {
                    self.pendingSectionAnchor = nil
                } else if self.sectionAnchorRetries < 60 {
                    // The new page has not loaded or laid out its headings yet.
                    self.sectionAnchorRetries += 1
                    self.scheduleHeadingOffsetsRefresh()
                } else {
                    self.pendingSectionAnchor = nil
                }
            }
            self.evaluateActiveHeading()
        }
    }

    private func evaluateActiveHeading() {
        if UserDefaults.standard.bool(forKey: "belvedere.outlineFollowsPointer"),
           let pointerHeadingID, sticky == nil {
            notifyActiveHeading(pointerHeadingID)
            return
        }
        if let pin = sticky {
            if DispatchTime.now() < pin.holdUntil { return }
            if !hasMovedFar(from: pin.anchor) { return }
            sticky = nil
        }
        notifyActiveHeading(computeActiveHeadingID())
    }

    private func hasMovedFar(from anchor: CGFloat) -> Bool {
        let metrics = webView.scrollMetrics
        let delta = abs(metrics.position - anchor)
        return delta >= metrics.viewportHeight * Self.stickyReleaseFraction
    }

    /// Last heading whose top has scrolled above the activation line.
    /// Lead-heading bump handles the doc-starts-with-a-heading case;
    /// short-doc-last-heading is handled by `markHeadingActiveFromClick`.
    private func computeActiveHeadingID() -> Int? {
        guard !headingOffsetsCSS.isEmpty else { return nil }
        let metrics = webView.scrollMetrics
        let zoom = max(webView.pageZoom, 0.001)
        let topMargin: CGFloat = 12
        var activationLine = (metrics.position + topMargin + 8) / zoom

        if let firstOffset = headingOffsetsCSS.first,
           firstOffset <= Self.leadHeadingThreshold,
           activationLine < firstOffset + 1 {
            activationLine = firstOffset + 1
        }

        var active: Int?
        for (index, offset) in headingOffsetsCSS.enumerated() {
            if offset <= activationLine { active = index } else { break }
        }
        return active
    }
}

/// Continues WebKit's obscured toolbar backing across the native gutter that
/// centered mode leaves to the web view's left. Its height is kept in sync
/// with `WKWebView.obscuredContentInsets`; full-width mode naturally reduces
/// its width to zero.
private final class PreviewToolbarGutterView: NSView {

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        wantsLayer = true
    }

    override var wantsUpdateLayer: Bool { true }

    /// Purely visual: keep native toolbar hit-testing and window dragging
    /// unchanged in the strip this view paints beneath.
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func updateLayer() {
        let isDark = effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        let scheme: ThemeColorScheme = isDark ? .dark : .light
        let color = ThemeColorsSetting.current.color(
            .windowBackground, scheme
        )
        layer?.backgroundColor = color?.cgColor
    }
}

/// The light-mode page white. The preview web view is non-opaque and the
/// rendered page paints no background of its own, so the whole reading surface
/// composites onto whatever sits behind it — and that used to be the window,
/// whose `windowBackgroundColor` is grey on macOS 15 and white on 26, leaving
/// code blocks barely distinguishable from the page on the older systems
/// (#251). Painting it here covers the page and, in centered mode, the gutter
/// the web view's leading edge leaves beside the column.
///
/// Original dark mode leaves the native window background visible, including
/// the centered-layout margin. Custom themes explicitly paint both surfaces.
private final class DocumentBackgroundView: NSView {

    weak var scrollWheelTarget: NSView?
    var appearanceDidChange: (() -> Void)?

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        appearanceDidChange?()
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        wantsLayer = true
    }

    /// Layer-backed so the fill costs a compositor rect rather than a
    /// full-window CPU redraw on every resize frame. AppKit re-invokes
    /// `updateLayer` when the effective appearance changes.
    override var wantsUpdateLayer: Bool { true }

    override func updateLayer() {
        let isDark = effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        // A user theme color wins over both stock fills; it covers the page
        // and the centered-mode gutters, so the whole content area follows.
        if let custom = ThemeColorsSetting.current.color(
            .windowBackground, isDark ? .dark : .light
        ) {
            layer?.backgroundColor = custom.cgColor
            return
        }
        layer?.backgroundColor = isDark ? nil : NSColor.white.cgColor
    }

    override func scrollWheel(with event: NSEvent) {
        guard let scrollWheelTarget else {
            super.scrollWheel(with: event)
            return
        }
        scrollWheelTarget.scrollWheel(with: event)
    }
}
