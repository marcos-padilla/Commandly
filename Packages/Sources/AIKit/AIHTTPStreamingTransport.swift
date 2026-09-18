import Foundation

/// Incremental HTTP boundary. Each callback receives one bounded UTF-8 line, never a log entry.
public protocol AIHTTPStreamingTransport: Sendable {
    /// Reads a response with backpressure. Throwing from the callback cancels the request.
    func send(
        _ request: AIHTTPRequest,
        onLine: @escaping @Sendable (String) async throws -> Void
    ) async throws -> AIHTTPResponse
}

/// Ephemeral, same-origin URLSession transport for SSE and newline-delimited JSON responses.
public struct URLSessionAIHTTPStreamingTransport: AIHTTPStreamingTransport {
    private let session: URLSession
    private static let maximumWireBytes = 4 * 1_024 * 1_024
    private static let maximumLineBytes = 512 * 1_024

    /// Creates a transport with no cookie, credential, or URL cache.
    public init() {
        session = URLSession(configuration: URLSessionAIHTTPTransport.productionConfiguration(),
            delegate: AISameOriginRedirectDelegate(), delegateQueue: nil)
    }

    /// Supplies an isolated test session; the caller owns its redirect policy.
    public init(session: URLSession) { self.session = session }

    /// Streams bounded lines. Provider errors are sanitized before the body reaches a consumer.
    public func send(
        _ request: AIHTTPRequest,
        onLine: @escaping @Sendable (String) async throws -> Void
    ) async throws -> AIHTTPResponse {
        try AIHTTPPayloadSizePolicy.validateRequestBodySize(request.body?.count ?? 0)
        var wire = URLRequest(url: request.url)
        wire.httpMethod = request.method.rawValue
        wire.httpBody = request.body
        wire.timeoutInterval = request.timeout
        for (key, value) in request.headers { wire.setValue(value, forHTTPHeaderField: key) }
        do {
            let (bytes, response) = try await session.bytes(for: wire)
            defer { bytes.task.cancel() }
            guard let http = response as? HTTPURLResponse else { throw AIProviderError.invalidProviderResponse }
            let headers = http.allHeaderFields.reduce(into: [String: String]()) { result, field in
                if let key = field.key as? String { result[key] = String(describing: field.value) }
            }
            if (200..<300).contains(http.statusCode) == false {
                var body = Data()
                for try await byte in bytes {
                    try Task.checkCancellation()
                    guard body.count < 64 * 1_024 else { break }
                    body.append(byte)
                }
                throw AIHTTPStatusMapper.error(for: .init(statusCode: http.statusCode, headers: headers, body: body))
                    ?? AIProviderError.serviceUnavailable
            }
            guard http.expectedContentLength <= Self.maximumWireBytes else {
                throw AIProviderError.invalidProviderResponse
            }
            var count = 0
            var line = Data()
            for try await byte in bytes {
                try Task.checkCancellation()
                count += 1
                guard count <= Self.maximumWireBytes else { throw AIProviderError.invalidProviderResponse }
                if byte == 10 {
                    if line.last == 13 { line.removeLast() }
                    guard let text = String(data: line, encoding: .utf8) else { throw AIProviderError.invalidProviderResponse }
                    try await onLine(text)
                    line.removeAll(keepingCapacity: true)
                } else {
                    guard line.count < Self.maximumLineBytes else { throw AIProviderError.invalidProviderResponse }
                    line.append(byte)
                }
            }
            if line.isEmpty == false {
                if line.last == 13 { line.removeLast() }
                guard let text = String(data: line, encoding: .utf8) else { throw AIProviderError.invalidProviderResponse }
                try await onLine(text)
            }
            try Task.checkCancellation()
            return AIHTTPResponse(statusCode: http.statusCode, headers: headers)
        } catch is CancellationError {
            throw AIProviderError.cancelled
        } catch let error as AIProviderError {
            throw error
        } catch let error as URLError where error.code == .cancelled {
            throw AIProviderError.cancelled
        } catch is URLError {
            throw AIProviderError.networkUnavailable
        } catch {
            // Consumer errors contain the caller's own typed cancellation/configuration state.
            // Preserve them; never expose a raw HTTP body or URLSession error description.
            throw error
        }
    }
}
