//
//  RemoteImageRequestPolicy.swift
//  md-preview
//

import Foundation

/// What a click on **Load** for a remote image is allowed to send, and to
/// where.
///
/// The fork blocks remote content so that opening a document never tells its
/// author that you read it. Click-to-load hands that decision back to the
/// reader for one image at a time — so the request has to carry as little as
/// possible about them, and must not become a doorway to anything but an
/// image.
///
/// **One image per click, and no per-host memory.** "Trust this host" sounds
/// convenient and is the wrong unit: a host like a large code-hosting site
/// speaks for thousands of unrelated authors, so allowing it once would allow
/// them all, in every document, for ever. Trust belongs to a folder the reader
/// chose (F3), never to a hostname a document named.
///
/// Pure Foundation, so the helper test package covers it.
nonisolated enum RemoteImageRequestPolicy {

    /// A redirect chain long enough to be a CDN, short enough not to be a tour.
    static let maximumRedirects = 3

    /// Long enough for a slow image, short enough that a click does not hang.
    static let timeout: TimeInterval = 10

    /// The same ceiling the local grant uses: a click cannot pull an unbounded
    /// download into memory.
    static let maximumBytes = DeferredAssetLoader.defaultMaxBytes

    /// Only `http` and `https`, and only with a host. Everything else — a
    /// `file:` URL smuggled through, a custom scheme registered by some other
    /// app — is refused before a request exists.
    static func isEligible(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              let host = url.host, !host.isEmpty
        else { return false }
        return true
    }

    /// A redirect is followed only to another eligible URL. Without this a
    /// 302 could hand the fetch to a scheme the policy would never have
    /// accepted to begin with.
    static func allowsRedirect(to url: URL) -> Bool { isEligible(url) }

    /// Named honestly. Pretending to be a browser would be a second kind of
    /// disclosure — a claim about who is asking — and the version is already
    /// public in every release.
    static func userAgent(name: String, version: String) -> String {
        "\(name)/\(version)"
    }
}
