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
/// - **Only images are eligible.** Verified by the leading bytes rather than by
///   file extension, so `passwd` renamed to `.png` is still refused. SVG is
///   admitted (badges from shields.io and the like are SVG, and a click that
///   fetched one only to discard it had already told the host) on two
///   conditions. Its prologue is checked lexically here, never parsed: a full
///   XML parse of untrusted bytes would put libxml2 in the app process, which
///   is more privileged than the WebKit process that renders it. And the page
///   shows a granted asset only as an `<img src="data:…">`, where WebKit runs
///   none of its scripts and loads nothing it names. That is the treatment an
///   SVG inside the document's folder already gets from `md-asset:`. Inlining
///   one into the DOM, or opening it in an `<object>`, `<iframe>` or a window
///   of its own, would run its scripts.
/// - **A size cap**, so a click cannot pull a multi-gigabyte file into memory
///   and base64 it.
/// - **No persistence.** The caller grants one asset at a time and forgets it
///   when the document closes; see `docs/FORK-NOTES.md`, click-to-load. Durable
///   grants are trusted folders, which are a different decision made about a
///   folder rather than about an image.
nonisolated enum DeferredAssetLoader {

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
        // http/https are not files. A granted remote image is fetched by
        // RemoteImageFetcher instead, which the caller reaches first.
        return nil
    }

    enum Refusal: String, Equatable {
        case missing
        case notAnImage
        case tooLarge
        case unreadable
        /// A granted remote image whose host did not answer, answered with an
        /// error, or redirected somewhere the request policy refused.
        case unreachable
    }

    enum Outcome: Equatable {
        case loaded(dataURL: String)
        case refused(Refusal)
    }

    /// Wraps `data` as a `data:` URL when it is an image within budget.
    ///
    /// Always base64. The URL is spliced into a single-quoted JavaScript string
    /// to reach the page, and base64's alphabet cannot close the quote; SVG
    /// text written into the URL as-is could.
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
    ///
    /// Without a `reader`, the file is read by `readRegularFile`, which refuses
    /// anything but a regular file within `maxBytes` before reading a byte.
    static func outcome(forFileAt path: String,
                        maxBytes: Int = defaultMaxBytes,
                        exists: (String) -> Bool = { FileManager.default.fileExists(atPath: $0) },
                        reader: ((URL) throws -> Data)? = nil) -> Outcome {
        let url = URL(fileURLWithPath: path).standardizedFileURL
        guard exists(url.path) else { return .refused(.missing) }
        let read = reader ?? { try readRegularFile(at: $0, maxBytes: maxBytes) }
        let data: Data
        do {
            data = try read(url)
        } catch ReadRefusal.tooLarge {
            return .refused(.tooLarge)
        } catch {
            return .refused(.unreadable)
        }
        return outcome(for: data, maxBytes: maxBytes)
    }

    /// Why `readRegularFile` declined before reading anything.
    enum ReadRefusal: Error {
        case notARegularFile
        case tooLarge
    }

    /// Reads a whole file, but only a regular file no larger than `maxBytes`,
    /// judged on the open descriptor before any bytes are read.
    ///
    /// `Data(contentsOf:)` reads whatever the path names, to the end: a
    /// multi-gigabyte file is pulled into memory before the size cap can
    /// refuse it, and a FIFO or `/dev/urandom` never ends. Both reads here run
    /// on the main thread, so either would hang the app. Opening non-blocking
    /// keeps a FIFO from blocking in `open` itself.
    static func readRegularFile(at url: URL, maxBytes: Int) throws -> Data {
        let fd = url.path.withCString { open($0, O_RDONLY | O_NONBLOCK | O_CLOEXEC) }
        guard fd >= 0 else { throw CocoaError(.fileReadNoPermission) }
        defer { close(fd) }
        var info = stat()
        guard fstat(fd, &info) == 0, info.st_mode & S_IFMT == S_IFREG else {
            throw ReadRefusal.notARegularFile
        }
        guard info.st_size <= maxBytes else { throw ReadRefusal.tooLarge }
        return try FileHandle(fileDescriptor: fd, closeOnDealloc: false).readToEnd() ?? Data()
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
        reader: ((URL) throws -> Data)? = nil
    ) -> Refusal? {
        switch outcome(forFileAt: path, maxBytes: maxBytes, exists: exists, reader: reader) {
        case .loaded: return nil
        case let .refused(reason): return reason
        }
    }

    /// Sniffs the leading bytes. Extensions are attacker-controlled; these are
    /// not. Returns nil for anything that is not an image this app is willing
    /// to render.
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
        if isSVGDocument(data) { return "image/svg+xml" }
        return nil
    }

    /// How far into the bytes `isSVGDocument` looks for the root element.
    /// A real prologue (declaration, a licence comment, a DOCTYPE) fits
    /// easily; one that does not is refused rather than scanned further.
    static let svgPrologueLimit = 4096

    /// Whether `data` starts the way an SVG document does: an optional UTF-8
    /// byte-order mark, then any whitespace, processing instructions
    /// (`<?xml …?>`), comments and a DOCTYPE, then `<svg` as the first element.
    ///
    /// A lexical check on purpose; nothing is parsed. Everything it does not
    /// recognise is a refusal: a DOCTYPE with an internal subset (`[`, where
    /// entity declarations live), a namespace-prefixed root, UTF-16, an HTML
    /// page that merely contains an `<svg>`, and a prologue longer than
    /// `svgPrologueLimit`. Whether the rest is well-formed is WebKit's
    /// business, in its own sandbox; a malformed SVG just fails to draw.
    static func isSVGDocument(_ data: Data) -> Bool {
        let bytes = [UInt8](data.prefix(svgPrologueLimit))
        var index = 0

        func hasPrefix(_ text: String) -> Bool {
            let pattern = Array(text.utf8)
            guard bytes.count - index >= pattern.count else { return false }
            return Array(bytes[index..<index + pattern.count]) == pattern
        }
        /// Moves past the next `terminator`, or reports that it is not there.
        func skip(past terminator: String) -> Bool {
            let pattern = Array(terminator.utf8)
            while index + pattern.count <= bytes.count {
                if Array(bytes[index..<index + pattern.count]) == pattern {
                    index += pattern.count
                    return true
                }
                index += 1
            }
            return false
        }
        func isSpace(_ byte: UInt8) -> Bool {
            byte == 0x20 || byte == 0x09 || byte == 0x0A || byte == 0x0D
        }

        if hasPrefix("\u{FEFF}") { index += 3 }
        while index < bytes.count {
            if isSpace(bytes[index]) {
                index += 1
            } else if hasPrefix("<?") {
                guard skip(past: "?>") else { return false }
            } else if hasPrefix("<!--") {
                guard skip(past: "-->") else { return false }
            } else if hasPrefix("<!DOCTYPE") {
                while index < bytes.count, bytes[index] != UInt8(ascii: ">") {
                    if bytes[index] == UInt8(ascii: "[") { return false }
                    index += 1
                }
                guard index < bytes.count else { return false }
                index += 1
            } else if hasPrefix("<svg") {
                index += 4
                guard index < bytes.count else { return false }
                let next = bytes[index]
                return isSpace(next) || next == UInt8(ascii: ">") || next == UInt8(ascii: "/")
            } else {
                return false
            }
        }
        return false
    }
}
