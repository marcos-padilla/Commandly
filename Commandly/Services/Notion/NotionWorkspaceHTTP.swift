import Foundation
import Infrastructure

nonisolated struct NotionHTTPResponse: Sendable {
    let data: Data
    let status: Int
    let retryAfter: Int?
}
nonisolated protocol NotionHTTPTransporting: Sendable {
    func send(_ request: URLRequest) async throws -> NotionHTTPResponse
}

/// Tokens stay on api.notion.com: redirects, cookies, caches and ambient credentials are disabled.
nonisolated struct NotionHTTPTransport: NotionHTTPTransporting {
    private let session: URLSession
    init() {
        let config = URLSessionConfiguration.ephemeral
        config.urlCache = nil; config.httpCookieStorage = nil; config.urlCredentialStorage = nil
        config.httpShouldSetCookies = false; config.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        config.timeoutIntervalForRequest = 20; config.timeoutIntervalForResource = 45
        session = URLSession(configuration: config, delegate: NotionNoRedirectDelegate(), delegateQueue: nil)
    }
    func send(_ request: URLRequest) async throws -> NotionHTTPResponse {
        do {
            let (bytes, response) = try await session.bytes(for: request)
            defer { bytes.task.cancel() }
            guard let response = response as? HTTPURLResponse, response.url == request.url else { throw NotionWorkspaceError.invalidResponse }
            var data = Data()
            if response.statusCode == 200 {
                guard response.mimeType == "application/json", response.expectedContentLength <= 4 * 1_024 * 1_024 else { throw NotionWorkspaceError.tooLarge }
                for try await byte in bytes {
                    if data.count.isMultiple(of: 4096) { try Task.checkCancellation() }
                    guard data.count < 4 * 1_024 * 1_024 else { throw NotionWorkspaceError.tooLarge }
                    data.append(byte)
                }
            }
            try Task.checkCancellation()
            return .init(data: data, status: response.statusCode,
                         retryAfter: response.value(forHTTPHeaderField: "Retry-After").flatMap(Int.init))
        } catch is CancellationError { throw CancellationError() }
        catch let error as NotionWorkspaceError { throw error }
        catch { if Task.isCancelled { throw CancellationError() }; throw NotionWorkspaceError.unavailable }
    }
}
nonisolated private final class NotionNoRedirectDelegate: NSObject, URLSessionTaskDelegate, Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void) { completionHandler(nil) }
}
