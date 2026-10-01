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
/// security line.
enum AboutCopy {

    /// Upstream's product name, which the .strings files map to "Belvedere".
    /// Localizing rather than hardcoding is how the whole rename works.
    static var applicationName: String { L("Markdown Preview") }

    /// Marketing version, plus a marker on anything that is not a release.
    /// The build number is deliberately not shown: `bin/build.sh` bumps
    /// CURRENT_PROJECT_VERSION by exactly one whenever MARKETING_VERSION
    /// changes and never on its own, so it is a bijection with the version
    /// and carries no information the version does not.
    ///
    /// That is true of releases only. Every build from a branch carries the
    /// version of the release it started from, so `bin/build.sh` stamps the
    /// commit into `BelvedereBuildStamp`, and `--release` stamps "release".
    /// A build with no stamp -- one run from Xcode -- still says it is a dev
    /// build, rather than passing for a release.
    ///
    /// Bare, with no "Version" prefix: the standard About panel supplies that
    /// word itself, so a prefixed string there renders as "Version Version
    /// 1.1.0". The in-app pane has no such label and uses `versionSummary`.
    static var versionNumber: String {
        versionLabel(
            version: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—",
            stamp: Bundle.main.infoDictionary?["BelvedereBuildStamp"] as? String
        )
    }

    static func versionLabel(version: String, stamp: String?) -> String {
        switch stamp {
        case "release": version
        case let stamp? where !stamp.isEmpty: "\(version) (dev \(stamp))"
        default: "\(version) (dev build)"
        }
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

    /// A short Markdown page, built by `bin/make-acknowledgements.sh`, naming
    /// each open-source component and the license it is used under, linked to
    /// that license in the component's repository. The license texts ship
    /// beside it in Resources. It opens in the reader's default Markdown app.
    ///
    /// A file rather than an in-app window because the standard About panel
    /// opens its links itself, through NSWorkspace: a file is the one target
    /// both About surfaces can share. Nil only if the resource is missing,
    /// which `ForkPostureTests` guards against.
    static var acknowledgementsURL: URL? {
        Bundle.main.url(forResource: "Acknowledgements", withExtension: "md")
    }

    static var acknowledgementsLabel: String { L("Acknowledgements") }

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
            string: repositoryLabel,
            attributes: [
                .font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize),
                .link: repositoryURL,
                .paragraphStyle: centred,
            ]
        ))

        if let acknowledgementsURL {
            // Spacing, not a blank line: set flush under the repository link,
            // the two links read as one, but a whole blank line would space
            // them as far apart as the unrelated paragraphs above.
            let spacedBelowRepository = NSMutableParagraphStyle()
            spacedBelowRepository.setParagraphStyle(centred)
            spacedBelowRepository.paragraphSpacingBefore = 6

            // The break is its own run so it is not part of either link.
            credits.append(NSAttributedString(
                string: "\n",
                attributes: [
                    .font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize),
                    .paragraphStyle: centred,
                ]
            ))
            credits.append(NSAttributedString(
                string: acknowledgementsLabel,
                attributes: [
                    .font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize),
                    .link: acknowledgementsURL,
                    .paragraphStyle: spacedBelowRepository,
                ]
            ))
        }

        return credits
    }
}
