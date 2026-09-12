//
//  RemoteImageFetcher.swift
//  md-preview
//
//  App-only: the Quick Look extension does not compile this file, because it
//  offers no grants and so can never reach it. Networking code that cannot be
//  invoked still has to be explained, so it is simply not there.
//

import Foundation

/// Fetches one remote image, and only because the reader clicked **Load** on
/// that image.
///
/// Nothing here runs on its own. `MarkdownWebView` calls it from the grant
/// path, one image per click, and hands the page a `data:` URL — the page
/// itself still reaches nothing, since its policy allows only `md-asset:` and
/// `data:`. The request is as anonymous as an HTTP request can be: a fresh
/// ephemeral session per grant, no cookie storage, no cache, no credentials, no
/// referrer, and a name that says who is asking rather than pretending to be a
/// browser.
///
/// The session is per grant rather than per window on purpose. It costs a
/// handshake nobody will notice on a click, and it means two grants share no
/// connection, no TLS session and no state — which is what "not remembered"
/// ought to mean at the socket as well as in the UI.
nonisolated final class RemoteImageFetcher: Sendable {

    private let userAgent: String

    init(userAgent: String? = nil) {
        self.userAgent = userAgent ?? Self.defaultUserAgent
    }

    private static var defaultUserAgent: String {
        let info = Bundle.main.infoDictionary
        return RemoteImageRequestPolicy.userAgent(
            name: info?["CFBundleName"] as? String ?? "Markdown Preview",
            version: info?["CFBundleShortVersionString"] as? String ?? "0"
        )
    }

    /// The bytes as a `data:` URL, or why the reader is not getting them.
    func image(at url: URL) async -> DeferredAssetLoader.Outcome {
        guard RemoteImageRequestPolicy.isEligible(url) else { return .refused(.unreachable) }

        let download = BoundedImageDownload(maxBytes: RemoteImageRequestPolicy.maximumBytes)
        let session = URLSession(configuration: configuration(),
                                 delegate: download,
                                 delegateQueue: nil)
        // Releases the session's strong reference to the delegate. Without it
        // both leak for the life of the process, one per image ever loaded.
        defer { session.finishTasksAndInvalidate() }

        var request = URLRequest(url: url,
                                 cachePolicy: .reloadIgnoringLocalAndRemoteCacheData,
                                 timeoutInterval: RemoteImageRequestPolicy.timeout)
        request.httpShouldHandleCookies = false
        return await download.run(request, in: session)
    }

    private func configuration() -> URLSessionConfiguration {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieAcceptPolicy = .never
        configuration.httpShouldSetCookies = false
        configuration.httpCookieStorage = nil
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        configuration.timeoutIntervalForRequest = RemoteImageRequestPolicy.timeout
        configuration.timeoutIntervalForResource = RemoteImageRequestPolicy.timeout
        configuration.httpAdditionalHeaders = [
            "User-Agent": userAgent,
            "Accept": "image/*",
        ]
        return configuration
    }
}

/// One request, capped as it arrives.
///
/// The cap is enforced on the stream rather than on the finished body, because
/// `Content-Length` is a claim by the same server that would be lying. A hostile
/// host can promise a thumbnail and keep sending; here the transfer is dropped
/// the moment it passes the ceiling, so nothing larger than the cap is ever held
/// in memory. The stated length is still checked first, since refusing before
/// the body arrives is cheaper for everyone when it is honest.
///
/// The redirect delegate method is written in its completion-handler form on
/// purpose: the `async` spelling crashes the compiler. Swift 6.3.3 (Xcode 26.6)
/// hits a SILGen assertion emitting the Objective-C thunk for an `@objc` async
/// method that returns a bridged Foundation value type — `URLRequest` here, and
/// equally `URL` or `Date`, though `String` and `Data` are fine. The trigger is
/// `nonisolated(nonsending)` semantics, which this target gets from
/// `SWIFT_APPROACHABLE_CONCURRENCY = YES`; without that setting the same code
/// compiles. Reported as https://github.com/swiftlang/swift/issues/92207 — when
/// that closes, the `async` spelling becomes available again. The two are
/// equivalent, and today only one of them builds.
private final class BoundedImageDownload: NSObject, URLSessionDataDelegate, @unchecked Sendable {

    private let maxBytes: Int
    private let lock = NSLock()
    private var buffer = Data()
    private var redirects = 0
    private var refusal: DeferredAssetLoader.Refusal?
    private var continuation: CheckedContinuation<DeferredAssetLoader.Outcome, Never>?

    init(maxBytes: Int) {
        self.maxBytes = maxBytes
    }

    func run(_ request: URLRequest, in session: URLSession) async -> DeferredAssetLoader.Outcome {
        await withCheckedContinuation { continuation in
            lock.lock()
            self.continuation = continuation
            lock.unlock()
            session.dataTask(with: request).resume()
        }
    }

    private func finish(_ outcome: DeferredAssetLoader.Outcome) {
        lock.lock()
        let pending = continuation
        continuation = nil
        lock.unlock()
        pending?.resume(returning: outcome)
    }

    // MARK: - URLSessionDataDelegate

    func urlSession(_ session: URLSession,
                    dataTask: URLSessionDataTask,
                    didReceive response: URLResponse,
                    completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        guard let http = response as? HTTPURLResponse,
              (200..<300).contains(http.statusCode) else {
            record(.unreachable)
            return completionHandler(.cancel)
        }
        if response.expectedContentLength > Int64(maxBytes) {
            record(.tooLarge)
            return completionHandler(.cancel)
        }
        completionHandler(.allow)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        lock.lock()
        buffer.append(data)
        let overflowed = buffer.count > maxBytes
        if overflowed {
            buffer.removeAll(keepingCapacity: false)
            refusal = .tooLarge
        }
        lock.unlock()
        if overflowed { dataTask.cancel() }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        lock.lock()
        let recorded = refusal
        let bytes = buffer
        lock.unlock()

        if let recorded { return finish(.refused(recorded)) }
        if error != nil { return finish(.refused(.unreachable)) }
        finish(DeferredAssetLoader.outcome(for: bytes, maxBytes: maxBytes))
    }

    /// Follows a redirect only to somewhere the policy would have accepted in
    /// the first place, and only a few times. Handing back nil stops the chain,
    /// which arrives as the 3xx response and so as a refusal.
    func urlSession(_ session: URLSession,
                    task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) {
        lock.lock()
        redirects += 1
        let followed = redirects
        lock.unlock()

        guard followed <= RemoteImageRequestPolicy.maximumRedirects,
              let url = request.url,
              RemoteImageRequestPolicy.allowsRedirect(to: url) else {
            return completionHandler(nil)
        }
        var next = request
        next.httpShouldHandleCookies = false
        next.setValue(nil, forHTTPHeaderField: "Referer")
        completionHandler(next)
    }

    private func record(_ reason: DeferredAssetLoader.Refusal) {
        lock.lock()
        refusal = reason
        lock.unlock()
    }
}
