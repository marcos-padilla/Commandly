import Foundation

/// HTTP methods needed by provider adapters.
public enum AIHTTPMethod: String, Sendable, Codable, Equatable {
    case get = "GET"
    case post = "POST"
}

/// Transport request whose textual representation is safe by construction.
public struct AIHTTPRequest: Sendable, CustomStringConvertible, CustomDebugStringConvertible,
    CustomReflectable
{
    public let method: AIHTTPMethod
    public let url: URL
    public let headers: [String: String]
    public let body: Data?
    public let timeout: TimeInterval

    public init(
        method: AIHTTPMethod,
        url: URL,
        headers: [String: String] = [:],
        body: Data? = nil,
        timeout: TimeInterval = 60
    ) {
        self.method = method
        self.url = url
        self.headers = headers
        self.body = body
        self.timeout = timeout
    }

    public var description: String {
        "AIHTTPRequest(method: \(method.rawValue), endpoint: \(sanitizedEndpoint), headers: <redacted>, body: <redacted>)"
    }

    public var debugDescription: String { description }

    public var customMirror: Mirror {
        Mirror(
            self,
            children: [
                "method": method.rawValue,
                "endpoint": sanitizedEndpoint,
                "headers": "<redacted>",
                "body": "<redacted>",
                "timeout": String(timeout)
            ],
            displayStyle: .struct
        )
    }

    private var sanitizedEndpoint: String {
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        components?.query = nil
        components?.fragment = nil
        return components?.url?.absoluteString ?? "<invalid-url>"
    }
}

/// Response returned by the injected HTTP transport.
public struct AIHTTPResponse: Sendable, Equatable, CustomStringConvertible,
    CustomDebugStringConvertible, CustomReflectable
{
    public let statusCode: Int
    public let headers: [String: String]
    public let body: Data

    public init(statusCode: Int, headers: [String: String] = [:], body: Data = Data()) {
        self.statusCode = statusCode
        self.headers = headers
        self.body = body
    }

    /// Looks up a header without depending on its casing.
    public func header(named name: String) -> String? {
        headers.first { $0.key.caseInsensitiveCompare(name) == .orderedSame }?.value
    }

    public var description: String {
        "AIHTTPResponse(statusCode: \(statusCode), headers: <redacted>, body: <redacted>)"
    }

    public var debugDescription: String { description }

    public var customMirror: Mirror {
        Mirror(
            self,
            children: [
                "statusCode": String(statusCode),
                "headers": "<redacted>",
                "body": "<redacted>"
            ],
            displayStyle: .struct
        )
    }
}

/// Injectable HTTP boundary used by every provider adapter.
public protocol AIHTTPTransport: Sendable {
    func send(_ request: AIHTTPRequest) async throws -> AIHTTPResponse
}

/// URLSession implementation used in production.
public struct URLSessionAIHTTPTransport: AIHTTPTransport {
    private let session: URLSession

    /// Creates the production transport with a same-origin-only redirect policy.
    public init() {
        let configuration = Self.productionConfiguration()
        self.session = URLSession(
            configuration: configuration,
            delegate: AISameOriginRedirectDelegate(),
            delegateQueue: nil
        )
    }

    static func productionConfiguration() -> URLSessionConfiguration {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpShouldSetCookies = false
        configuration.httpCookieStorage = nil
        configuration.urlCache = nil
        configuration.urlCredentialStorage = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        return configuration
    }

    /// Creates a transport around a caller-owned session.
    ///
    /// The caller owns that session's redirect policy. This initializer exists for deterministic
    /// tests and specialized integrations; production composition uses ``init()``.
    public init(session: URLSession) {
        self.session = session
    }

    public func send(_ request: AIHTTPRequest) async throws -> AIHTTPResponse {
        try AIHTTPPayloadSizePolicy.validateRequestBodySize(request.body?.count ?? 0)
        var urlRequest = URLRequest(url: request.url)
        urlRequest.httpMethod = request.method.rawValue
        urlRequest.httpBody = request.body
        urlRequest.timeoutInterval = request.timeout
        for (name, value) in request.headers {
            urlRequest.setValue(value, forHTTPHeaderField: name)
        }

        do {
            let (bytes, response) = try await session.bytes(for: urlRequest)
            guard let httpResponse = response as? HTTPURLResponse else {
                bytes.task.cancel()
                throw AIProviderError.invalidProviderResponse
            }
            let headers = httpResponse.allHeaderFields.reduce(into: [String: String]()) { result, entry in
                guard let name = entry.key as? String else { return }
                result[name] = String(describing: entry.value)
            }
            do {
                var accumulator = try AIHTTPResponseBodyAccumulator(
                    declaredByteCount: httpResponse.expectedContentLength
                )
                for try await byte in bytes {
                    try accumulator.append(byte)
                }
                return AIHTTPResponse(
                    statusCode: httpResponse.statusCode,
                    headers: headers,
                    body: accumulator.body
                )
            } catch {
                bytes.task.cancel()
                throw error
            }
        } catch is CancellationError {
            throw AIProviderError.cancelled
        } catch let error as AIProviderError {
            throw error
        } catch let error as URLError where error.code == .cancelled {
            throw AIProviderError.cancelled
        } catch {
            throw AIProviderError.networkUnavailable
        }
    }
}

/// Bounded response-body builder used with `URLSession.AsyncBytes` so data is rejected while it is
/// received rather than after an unbounded `Data` value has already been materialized.
struct AIHTTPResponseBodyAccumulator {
    private let maximumBytes: Int
    private(set) var body: Data

    init(
        declaredByteCount: Int64,
        maximumBytes: Int = AIHTTPPayloadSizePolicy.maximumResponseBodyBytes
    ) throws {
        guard maximumBytes >= 0 else {
            throw AIProviderError.invalidProviderResponse
        }
        if declaredByteCount >= 0 {
            guard declaredByteCount <= Int64(maximumBytes) else {
                throw AIProviderError.invalidProviderResponse
            }
        }
        self.maximumBytes = maximumBytes
        self.body = Data()
        if declaredByteCount > 0, let capacity = Int(exactly: declaredByteCount) {
            body.reserveCapacity(capacity)
        }
    }

    mutating func append(_ byte: UInt8) throws {
        guard body.count < maximumBytes else {
            throw AIProviderError.invalidProviderResponse
        }
        body.append(byte)
    }
}

enum AIHTTPPayloadSizePolicy {
    static let maximumRequestBodyBytes = 4 * 1_024 * 1_024
    static let maximumResponseBodyBytes = 32 * 1_024 * 1_024

    static func validateRequestBodySize(_ byteCount: Int) throws {
        guard byteCount >= 0, byteCount <= maximumRequestBodyBytes else {
            throw AIProviderError.invalidRequest
        }
    }

    static func validateResponseBodySize(_ byteCount: Int) throws {
        guard byteCount >= 0, byteCount <= maximumResponseBodyBytes else {
            throw AIProviderError.invalidProviderResponse
        }
    }
}

/// URLSession's delegate protocols inherit from Objective-C classes whose thread-safety is not
/// expressible to Swift's compiler. This delegate has no mutable stored state, reads only callback
/// arguments, and delegates all decisions to a pure value function. It is therefore safe for
/// URLSession to call concurrently, which is the complete justification for `@unchecked Sendable`.
final class AISameOriginRedirectDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping @Sendable (URLRequest?) -> Void
    ) {
        guard
            let originURL = response.url,
            let destinationURL = request.url,
            AIHTTPRedirectPolicy.isSameOrigin(originURL, destinationURL)
        else {
            completionHandler(nil)
            return
        }
        completionHandler(request)
    }
}

enum AIHTTPRedirectPolicy {
    static func isSameOrigin(_ origin: URL, _ destination: URL) -> Bool {
        guard
            let source = Origin(url: origin),
            let target = Origin(url: destination)
        else {
            return false
        }
        return source == target
    }

    private struct Origin: Equatable {
        let scheme: String
        let host: String
        let port: Int

        init?(url: URL) {
            guard
                let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
                let rawScheme = components.scheme?.lowercased(),
                let rawHost = components.host?.lowercased(),
                components.user == nil,
                components.password == nil,
                rawScheme == "https" || rawScheme == "http"
            else {
                return nil
            }
            let defaultPort = rawScheme == "https" ? 443 : 80
            self.scheme = rawScheme
            self.host = rawHost
            self.port = components.port ?? defaultPort
        }
    }
}

enum AIHTTPStatusMapper {
    static func error(for response: AIHTTPResponse) -> AIProviderError? {
        switch response.statusCode {
        case 200 ..< 300:
            nil
        case 400, 409, 413, 415, 422:
            .invalidRequest
        case 401:
            .invalidCredential
        case 402:
            .billingUnavailable
        case 403:
            .insufficientPermission
        case 404:
            .modelUnavailable
        case 429:
            .rateLimited(retryAfterSeconds: retryAfter(from: response))
        case 408:
            .serviceUnavailable
        case 500 ... 599:
            .serviceUnavailable
        default:
            .serviceUnavailable
        }
    }

    private static func retryAfter(from response: AIHTTPResponse) -> Double? {
        guard let value = response.header(named: "Retry-After") else { return nil }
        return Double(value)
    }
}
