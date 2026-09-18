import Foundation
import Infrastructure

nonisolated protocol GIFHTTPTransporting: Sendable {
    func get(_ request: URLRequest, maximumBytes: Int, allowedContentTypes: Set<String>) async throws -> Data
}
/// Ephemeral client-only requests. No cache, cookies, stored credentials, redirects, or diagnostics payloads.
nonisolated struct GIPHYHTTPTransport: GIFHTTPTransporting {
    private let session: URLSession
    init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil; configuration.httpCookieStorage = nil; configuration.httpShouldSetCookies = false
        configuration.urlCredentialStorage = nil; configuration.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        configuration.timeoutIntervalForRequest = 20; configuration.timeoutIntervalForResource = 45
        session = URLSession(configuration: configuration, delegate: GIFNoRedirectDelegate(), delegateQueue: nil)
    }
    /// Injected URLProtocol sessions are deterministic test seams and must supply their own redirect policy.
    init(session: URLSession) { self.session = session }
    func get(_ request: URLRequest, maximumBytes: Int, allowedContentTypes: Set<String>) async throws -> Data {
        try Task.checkCancellation()
        do {
            let (bytes, response) = try await session.bytes(for: request)
            defer { bytes.task.cancel() } // Also stop oversized/rejected bodies before consuming their remainder.
            guard let response = response as? HTTPURLResponse else { throw GIFSearchError.invalidResponse }
            switch response.statusCode {
            case 200: break
            case 300..<400: throw GIFSearchError.unsafeURL
            case 401, 403: throw GIFSearchError.unauthorized
            case 429: throw GIFSearchError.rateLimited
            default: throw GIFSearchError.unavailable
            }
            guard response.url == request.url,
                  allowedContentTypes.contains(response.mimeType?.lowercased() ?? "") else { throw GIFSearchError.invalidResponse }
            guard response.expectedContentLength <= Int64(maximumBytes) else { throw GIFSearchError.responseTooLarge }
            var data = Data(); data.reserveCapacity(min(maximumBytes, 64 * 1_024))
            for try await byte in bytes {
                if data.count.isMultiple(of: 4_096) { try Task.checkCancellation() }
                guard data.count < maximumBytes else { throw GIFSearchError.responseTooLarge }
                data.append(byte)
            }
            try Task.checkCancellation(); return data
        } catch is CancellationError { throw CancellationError() }
        catch let error as GIFSearchError { throw error }
        catch { if Task.isCancelled { throw CancellationError() }; throw GIFSearchError.unavailable }
    }
}
/// Immutable delegate: refusing redirects prevents keys from being forwarded and media host drift.
nonisolated final class GIFNoRedirectDelegate: NSObject, URLSessionTaskDelegate, Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}
nonisolated enum GIPHYURLPolicy {
    static func media(_ url: URL) -> Bool {
        guard base(url), let host = url.host?.lowercased(),
              ["media.giphy.com", "media0.giphy.com", "media1.giphy.com", "media2.giphy.com", "media3.giphy.com", "media4.giphy.com", "i.giphy.com"].contains(host),
              url.pathExtension.lowercased() == "gif" else { return false }
        return true
    }
    static func page(_ url: URL) -> Bool { base(url) && ["giphy.com", "www.giphy.com"].contains(url.host?.lowercased() ?? "") }
    static func externalSource(_ url: URL) -> Bool { base(url) && url.host != nil }
    private static func base(_ url: URL) -> Bool {
        url.scheme?.lowercased() == "https" && url.user == nil && url.password == nil && (url.port == nil || url.port == 443)
            && url.fragment == nil && url.absoluteString.utf8.count <= 4_096
    }
}
