//
//  LinkDestinationLabel.swift
//  belvedere
//
//  Fork-only. What the link-destination bar shows when the pointer is over a
//  link in the reading view. Foundation only, so the SPM tests cover it.
//
//  The bar shows where a link *actually* goes, not what the document says
//  it goes to: link text can read `github.com/...` while the target is
//  somewhere else, and Belvedere exists to read documents someone else sent.
//  So this works from the link's resolved `href` and never from its text.
//

import Foundation

nonisolated enum LinkDestinationLabel {

    /// Longest string the bar shows. A web address longer than this loses the
    /// middle of its path, never any of its host.
    static let maxLength = 100

    /// The text to show for a hovered link, or nil when there is nothing
    /// worth showing: a malformed address, or the reserved `md-asset:` vendor
    /// namespace that no document link can legitimately name.
    ///
    /// `sameDocumentFragment` is set by the caller when the link only moves
    /// within the document that is already open.
    static func text(for href: URL, sameDocumentFragment: String? = nil) -> String? {
        if let sameDocumentFragment {
            return sanitized("#" + sameDocumentFragment)
        }
        switch href.scheme?.lowercased() {
        case MarkdownAssetResolution.scheme:
            // A relative link resolves against the document's folder; show
            // the file it would open, not the internal scheme.
            guard !href.path.hasPrefix(MarkdownAssetResolution.vendorPathPrefix),
                  let file = MarkdownAssetResolution.candidateFileURL(for: href) else { return nil }
            return shortened(path: file.path + fragmentSuffix(of: href))
        case "file":
            guard href.host?.isEmpty ?? true, href.path.count > 1 else { return nil }
            return shortened(path: href.standardizedFileURL.path + fragmentSuffix(of: href))
        case nil:
            return nil
        default:
            // The full address, user-info and all: `https://paypal.com@evil.test/`
            // must read as exactly that. A web view's `href` already carries an
            // internationalised host in punycode, so a look-alike domain shows
            // as `xn--...` and cannot pass for the real one.
            return shortened(address: href.absoluteString)
        }
    }

    private static func fragmentSuffix(of url: URL) -> String {
        guard let fragment = url.fragment, !fragment.isEmpty else { return "" }
        return "#" + fragment
    }

    // MARK: - Shortening

    /// A file path loses the middle, so the folder it starts in and the file it
    /// ends in both stay visible.
    private static func shortened(path: String) -> String {
        sanitized(truncatedMiddle(path, to: maxLength))
    }

    /// Keeps everything up to and including the host whole and shortens only
    /// what follows it. If the host alone is longer than the limit it is still
    /// shown in full: the host is the part a reader needs to judge.
    private static func shortened(address: String) -> String {
        guard address.count > maxLength else { return sanitized(address) }
        let authorityEnd = authorityEndIndex(in: address)
        let head = String(address[..<authorityEnd])
        let rest = String(address[authorityEnd...])
        let room = maxLength - head.count
        guard room > 8 else { return sanitized(head + "…") }
        return sanitized(head + truncatedMiddle(rest, to: room))
    }

    /// Index just past `scheme://user@host:port`, or past `scheme:` for an
    /// address with no authority such as `mailto:`.
    private static func authorityEndIndex(in address: String) -> String.Index {
        guard let schemeEnd = address.range(of: "://") else {
            return address.index(address.startIndex, offsetBy: min(address.count, 7))
        }
        let afterAuthority = address[schemeEnd.upperBound...]
        if let slash = afterAuthority.firstIndex(where: { $0 == "/" || $0 == "?" || $0 == "#" }) {
            return slash
        }
        return address.endIndex
    }

    private static func truncatedMiddle(_ text: String, to limit: Int) -> String {
        guard text.count > limit, limit > 3 else { return text }
        let keep = limit - 1
        let head = keep / 2 + keep % 2
        let tail = keep / 2
        return String(text.prefix(head)) + "…" + String(text.suffix(tail))
    }

    /// Replaces control and invisible formatting characters, bidirectional
    /// overrides included, so the bar cannot be made to read differently from
    /// what it holds. A well-formed `href` has none of these; this is for one
    /// that is not.
    private static func sanitized(_ text: String) -> String {
        var result = String.UnicodeScalarView()
        for scalar in text.unicodeScalars {
            switch scalar.properties.generalCategory {
            case .control, .format, .lineSeparator, .paragraphSeparator:
                result.append("\u{FFFD}")
            default:
                result.append(scalar)
            }
        }
        return String(result)
    }
}
