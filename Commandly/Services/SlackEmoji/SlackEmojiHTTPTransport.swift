import Foundation
import Infrastructure

nonisolated struct SlackEmojiHTTPResponse: Sendable {
    let data: Data
    let status: Int
    let contentType: String?
    let scopes: String?
    let retryAfter: Int?
    let location: String?
}
nonisolated protocol SlackEmojiHTTPTransporting: Sendable {
    func send(_ request: URLRequest, maximumBytes: Int) async throws -> SlackEmojiHTTPResponse
}
/// Ephemeral transport refuses automatic redirects. Its caller validates each public media hop.
nonisolated struct SlackEmojiHTTPTransport: SlackEmojiHTTPTransporting {
    private let session: URLSession
    init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil; configuration.httpCookieStorage = nil; configuration.httpShouldSetCookies = false
        configuration.urlCredentialStorage = nil; configuration.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        configuration.timeoutIntervalForRequest = 20; configuration.timeoutIntervalForResource = 45
        session = URLSession(configuration: configuration, delegate: SlackEmojiNoRedirectDelegate(), delegateQueue: nil)
    }
    init(session: URLSession) { self.session = session }
    func send(_ request: URLRequest, maximumBytes: Int) async throws -> SlackEmojiHTTPResponse {
        try Task.checkCancellation()
        do {
            let (bytes, response) = try await session.bytes(for: request)
            defer { bytes.task.cancel() }
            guard let response = response as? HTTPURLResponse, response.url == request.url else { throw SlackEmojiError.invalidResponse }
            let retry = response.value(forHTTPHeaderField: "Retry-After").flatMap(Int.init).flatMap { (1...604_800).contains($0) ? $0 : nil }
            var data = Data()
            if response.statusCode == 200 {
                guard response.expectedContentLength <= Int64(maximumBytes) else { throw SlackEmojiError.responseTooLarge }
                data.reserveCapacity(min(maximumBytes, 64 * 1_024))
                for try await byte in bytes {
                    if data.count.isMultiple(of: 4_096) { try Task.checkCancellation() }
                    guard data.count < maximumBytes else { throw SlackEmojiError.responseTooLarge }
                    data.append(byte)
                }
            }
            try Task.checkCancellation()
            return .init(data: data, status: response.statusCode, contentType: response.mimeType?.lowercased(),
                         scopes: response.value(forHTTPHeaderField: "X-OAuth-Scopes"), retryAfter: retry,
                         location: response.value(forHTTPHeaderField: "Location"))
        } catch is CancellationError { throw CancellationError() }
        catch let error as SlackEmojiError { throw error }
        catch { if Task.isCancelled { throw CancellationError() }; throw SlackEmojiError.unavailable }
    }
}
nonisolated final class SlackEmojiNoRedirectDelegate: NSObject, URLSessionTaskDelegate, Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void) { completionHandler(nil) }
}
