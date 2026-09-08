import Foundation

/// Decides whether a blocked asset may be loaded after the reader asks for it,
/// and turns it into a `data:` URL the page can use.
///
/// Two different blocks land here. A remote image is refused by the
/// Content-Security-Policy so a document cannot beacon on mere open, and a
/// local file outside the document's folder is refused by `md-asset:`
/// containment. The reader's remedy is the same in both cases — click the
/// placeholder — so the mechanism is shared: the host reads or fetches the
/// bytes, checks them, and hands back a `data:` URL. `img-src` already permits
/// `data:`, so nothing about the policy is relaxed to make this work.
///
/// Everything here is deliberately narrow, because the click is the only thing
/// standing between document content and an arbitrary file read:
///
/// - **Only raster images are eligible.** Verified by magic bytes rather than
///   by file extension, so `passwd` renamed to `.png` is still refused. SVG is
///   excluded on purpose: it is a document format, and while an `<img>` will
///   not run its scripts, it is the one image type where that sentence needs a
///   caveat at all.
/// - **A size cap**, so a click cannot pull a multi-gigabyte file into memory
///   and base64 it.
/// - **No persistence.** The caller grants one asset at a time and forgets it
///   when the document closes; see `docs/FORK-NOTES.md` (F4). Durable grants
///   are trusted folders (F3), which are a different decision made about a
///   folder rather than about an image.
enum DeferredAssetLoader {

    static let defaultMaxBytes = 16 * 1024 * 1024

    /// The filesystem path a granted asset refers to, or nil when the request
    /// is not one this loader will serve.
    ///
    /// The page must send the URL **resolved** against its `<base href>`. An
    /// early version sent `img.getAttribute('src')`, which is whatever the
    /// document wrote — usually something like `../images/logo.png` — and a
    /// relative reference means nothing on this side, so every click came back
    /// unavailable. Refusing them here rather than guessing keeps that failure
    /// loud instead of turning it into a path relative to whatever the process
    /// working directory happens to be.
    static func localPath(for url: URL, scheme: String) -> String? {
        if url.scheme == scheme {
            // A host would make it someone else's file, not ours.
            guard url.host?.isEmpty ?? true else { return nil }
            guard url.path.count > 1 else { return nil }
            return url.path
        }
        if url.isFileURL { return url.path }
        // http/https are not fetched: doing so would send the reader's IP to
        // whoever authored the document, which is what the CSP prevents.
        return nil
    }

    enum Refusal: String, Equatable {
        case missing
        case notAnImage
        case tooLarge
        case unreadable
    }

    enum Outcome: Equatable {
        case loaded(dataURL: String)
        case refused(Refusal)
    }

    /// Wraps `data` as a `data:` URL when it is a raster image within budget.
    static func outcome(for data: Data, maxBytes: Int = defaultMaxBytes) -> Outcome {
        guard data.count <= maxBytes else { return .refused(.tooLarge) }
        guard let mime = imageMIMEType(of: data) else { return .refused(.notAnImage) }
        return .loaded(dataURL: "data:\(mime);base64,\(data.base64EncodedString())")
    }

    /// Reads a local file and applies the same checks.
    ///
    /// Absence is reported separately from unreadability. Collapsing both into
    /// one refusal told the reader "cannot read file" for a file that simply is
    /// not there, which sends them looking for a permissions problem that does
    /// not exist. The distinction costs one `stat`.
    static func outcome(forFileAt path: String,
                        maxBytes: Int = defaultMaxBytes,
                        exists: (String) -> Bool = { FileManager.default.fileExists(atPath: $0) },
                        reader: (URL) throws -> Data = { try Data(contentsOf: $0) }) -> Outcome {
        let url = URL(fileURLWithPath: path).standardizedFileURL
        guard exists(url.path) else { return .refused(.missing) }
        guard let data = try? reader(url) else { return .refused(.unreadable) }
        return outcome(for: data, maxBytes: maxBytes)
    }

    /// Why a reference inside the document's own folder failed to render.
    ///
    /// Safe to call without a grant, and only for in-folder references: the
    /// app already attempted that exact read while rendering the page, so
    /// asking why it failed reveals nothing it did not already learn and
    /// permits nothing new. The same call for an arbitrary path would be a
    /// filesystem probe on the document's behalf, which is why the caller
    /// restricts it.
    ///
    /// Returns nil when the file is present and would have loaded — WebKit
    /// declined it for some reason of its own, and inventing a cause would be
    /// worse than admitting there isn't one.
    static func reasonForInFolderFailure(
        atPath path: String,
        maxBytes: Int = defaultMaxBytes,
        exists: (String) -> Bool = { FileManager.default.fileExists(atPath: $0) },
        reader: (URL) throws -> Data = { try Data(contentsOf: $0) }
    ) -> Refusal? {
        switch outcome(forFileAt: path, maxBytes: maxBytes, exists: exists, reader: reader) {
        case .loaded: return nil
        case let .refused(reason): return reason
        }
    }

    /// Sniffs the leading bytes. Extensions are attacker-controlled; these are
    /// not. Returns nil for anything that is not a raster image this app is
    /// willing to render.
    static func imageMIMEType(of data: Data) -> String? {
        func starts(_ bytes: [UInt8], at offset: Int = 0) -> Bool {
            guard data.count >= offset + bytes.count else { return false }
            let start = data.index(data.startIndex, offsetBy: offset)
            return Array(data[start..<data.index(start, offsetBy: bytes.count)]) == bytes
        }

        if starts([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]) { return "image/png" }
        if starts([0xFF, 0xD8, 0xFF]) { return "image/jpeg" }
        if starts([0x47, 0x49, 0x46, 0x38]) { return "image/gif" }
        if starts([0x42, 0x4D]) { return "image/bmp" }
        if starts([0x49, 0x49, 0x2A, 0x00]) || starts([0x4D, 0x4D, 0x00, 0x2A]) { return "image/tiff" }
        // RIFF....WEBP — the size field sits between the two markers.
        if starts([0x52, 0x49, 0x46, 0x46]) && starts([0x57, 0x45, 0x42, 0x50], at: 8) {
            return "image/webp"
        }
        // ISO base media: ....ftyp then a HEIF/AVIF brand.
        if starts([0x66, 0x74, 0x79, 0x70], at: 4) {
            for brand in [[0x68, 0x65, 0x69, 0x63], [0x68, 0x65, 0x69, 0x78],
                          [0x6D, 0x69, 0x66, 0x31]] where starts(brand.map(UInt8.init), at: 8) {
                return "image/heic"
            }
            if starts([0x61, 0x76, 0x69, 0x66], at: 8) { return "image/avif" }
        }
        return nil
    }
}
