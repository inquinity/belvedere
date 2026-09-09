//
//  AboutCopy.swift
//  md-preview
//

import AppKit

/// The text shown in both About surfaces -- the standard panel from the app
/// menu (`AppDelegate.showAboutPanel`) and the in-app pane
/// (`AboutSettingsView`). They are kept identical on purpose, so the copy lives
/// here rather than in either one.
///
/// **These lines make claims about behaviour, so they are behaviour.** If the
/// app ever gains an outbound connection of its own, or stops blocking remote
/// content by default, `securitySummary` becomes false and must change in the
/// same commit. `ForkPostureTests` guards the code those claims rest on.
///
/// Fork-only: upstream's About box carries neither the tagline nor the
/// security line, and upstream is the thing being forked *from* in
/// `forkCredit`.
enum AboutCopy {

    /// Upstream's product name, which the .strings files map to "Belvedere".
    /// Localizing rather than hardcoding is how the whole rename works.
    static var applicationName: String { L("Markdown Preview") }

    /// Marketing version only. The build number is deliberately not shown:
    /// `bin/build.sh` bumps CURRENT_PROJECT_VERSION by exactly one whenever
    /// MARKETING_VERSION changes and never on its own, so it is a bijection
    /// with the version and carries no information the version does not.
    ///
    /// Bare, with no "Version" prefix: the standard About panel supplies that
    /// word itself, so a prefixed string there renders as "Version Version
    /// 1.1.0". The in-app pane has no such label and uses `versionSummary`.
    static var versionNumber: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
    }

    /// The version as its own complete line, for surfaces that do not add a
    /// label of their own.
    static var versionSummary: String {
        String(format: L("Version %@"), versionNumber)
    }

    static var tagline: String {
        L("A security-centric Markdown viewer, with editing and printing.")
    }

    /// The same sentence with an explicit break, for the standard About panel.
    ///
    /// The panel is narrow enough that the one-line form wraps mid-clause. The
    /// break is a separate localized string rather than surgery on `tagline`
    /// -- splitting at ", with" would work in English and do nothing in
    /// zh-Hans, which has no such comma -- so a translator places it where the
    /// sentence actually allows. The in-app pane is wide enough and keeps the
    /// unbroken form.
    static var taglineWrapped: String {
        L("A security-centric Markdown viewer,\nwith editing and printing.")
    }

    /// Two separate guarantees, deliberately not merged into one sentence.
    ///
    /// The first is about the app: the telemetry reporters are stubs and the
    /// updater is gone, so there is no request to approve. The second is about
    /// document content: a remote image or script is blocked by the content
    /// policy until you load it.
    ///
    /// Neither claim is "the sandbox forbids networking" -- it does not, and
    /// cannot. `com.apple.security.network.client` is required on both targets
    /// or WKWebView renders blank. See docs/FORK-NOTES.md.
    /// Named rather than starting "Never connects", so the claim is anchored to
    /// the app on first read. The break is in the string because the two
    /// sentences are two different guarantees and should not run together.
    static var securitySummary: String {
        L("Markdown Preview never connects on its own.\nRemote content stays blocked until you allow it.")
    }

    static let repositoryURL = URL(string: "https://github.com/inquinity/belvedere")!

    static var repositoryLabel: String { "github.com/inquinity/belvedere" }
    /// Attribution, deliberately not a link.
    ///
    /// The point of the line is credit and provenance, not navigation: this is
    /// our app, and a reader who wants upstream can reach it from our
    /// repository. Two equal-weight links would also imply equal standing
    /// between us and a different app's repository.
    ///
    /// "pluk-inc/markdown-preview" is a repository slug rather than a URL --
    /// no scheme, no host -- so the usual expectation that a URL on screen
    /// should be clickable does not apply to it.
    ///
    /// MIT attribution is satisfied by shipping LICENSE, not by this line.
    static var forkCredit: String { L("Forked from pluk-inc/markdown-preview") }

    /// The `.credits` value for the standard About panel, which renders it
    /// below the version. Links are live: the field is backed by a text view
    /// that honours `.link`.
    static func creditsAttributedString() -> NSAttributedString {
        let centred = NSMutableParagraphStyle()
        centred.alignment = .center
        centred.lineSpacing = 2

        let credits = NSMutableAttributedString()

        credits.append(NSAttributedString(
            string: taglineWrapped + "\n",
            attributes: [
                .font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize),
                .foregroundColor: NSColor.labelColor,
                .paragraphStyle: centred,
            ]
        ))

        credits.append(NSAttributedString(
            string: "\n" + securitySummary + "\n\n",
            attributes: [
                .font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize),
                .foregroundColor: NSColor.secondaryLabelColor,
                .paragraphStyle: centred,
            ]
        ))

        credits.append(NSAttributedString(
            string: repositoryLabel + "\n\n",
            attributes: [
                .font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize),
                .link: repositoryURL,
                .paragraphStyle: centred,
            ]
        ))

        credits.append(NSAttributedString(
            string: forkCredit,
            attributes: [
                .font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize),
                .foregroundColor: NSColor.secondaryLabelColor,
                .paragraphStyle: centred,
            ]
        ))

        return credits
    }
}
