import Foundation

/// Adds genuine incremental text delivery to existing reviewed adapter request/response codecs.
/// Authentication, model validation, endpoints, and final finish-reason normalization stay adapter-owned.
public struct AITextStreamingTransport: AIHTTPTransport {
    private let providerID: AIProviderID
    private let transport: any AIHTTPStreamingTransport
    private let onTextDelta: @Sendable (String) async throws -> Void

    /// Creates a single-request text-only bridge. It does not initiate network traffic.
    public init(providerID: AIProviderID, transport: any AIHTTPStreamingTransport,
                onTextDelta: @escaping @Sendable (String) async throws -> Void) {
        self.providerID = providerID
        self.transport = transport
        self.onTextDelta = onTextDelta
    }

    /// Only the explicitly reviewed provider streaming formats are available.
    public static func supports(_ providerID: AIProviderID) -> Bool {
        [.openAI, .anthropic, .googleGemini, .mistral, .groq, .xAI, .openRouter, .ollama].contains(providerID)
    }

    /// Converts the existing adapter's generation request to streaming and reconstructs its final JSON.
    public func send(_ request: AIHTTPRequest) async throws -> AIHTTPResponse {
        let wire = try streamingRequest(request)
        let accumulator = AITextStreamAccumulator(providerID: providerID, onTextDelta: onTextDelta)
        let response = try await transport.send(wire) { try await accumulator.consume(line: $0) }
        try Task.checkCancellation()
        let body = try await accumulator.finish()
        return AIHTTPResponse(statusCode: response.statusCode, headers: response.headers, body: body)
    }

    private func streamingRequest(_ request: AIHTTPRequest) throws -> AIHTTPRequest {
        guard Self.supports(providerID), request.method == .post, let data = request.body,
              var object = try AIJSONValue(data: data).objectValue else { throw AIProviderError.unsupportedCapability }
        if let tools = object["tools"]?.arrayValue, tools.isEmpty == false { throw AIProviderError.unsupportedCapability }
        var url = request.url
        if providerID == .googleGemini {
            guard var parts = URLComponents(url: url, resolvingAgainstBaseURL: false),
                  parts.path.hasSuffix(":generateContent") else { throw AIProviderError.invalidRequest }
            parts.path = String(parts.path.dropLast(":generateContent".count)) + ":streamGenerateContent"
            parts.queryItems = (parts.queryItems ?? []).filter { $0.name != "alt" } + [URLQueryItem(name: "alt", value: "sse")]
            guard let changed = parts.url else { throw AIProviderError.invalidRequest }
            url = changed
        } else {
            object["stream"] = .boolean(true)
        }
        var headers = request.headers
        headers["Accept"] = providerID == .ollama ? "application/x-ndjson" : "text/event-stream"
        return AIHTTPRequest(method: request.method, url: url, headers: headers,
            body: try AIJSONValue.object(object).encodedData(), timeout: request.timeout)
    }
}

/// Confines mutable parser state and provides backpressure without an unbounded AsyncStream buffer.
private actor AITextStreamAccumulator {
    private var codec: AITextStreamCodec
    private var frameLines: [String] = []
    private var frameBytes = 0
    private let providerID: AIProviderID
    private let onTextDelta: @Sendable (String) async throws -> Void

    init(providerID: AIProviderID, onTextDelta: @escaping @Sendable (String) async throws -> Void) {
        self.providerID = providerID
        self.codec = AITextStreamCodec(providerID: providerID)
        self.onTextDelta = onTextDelta
    }

    func consume(line: String) async throws {
        try Task.checkCancellation()
        if providerID == .ollama {
            if line.isEmpty == false { try await consumePayload(line) }
            return
        }
        if line.isEmpty {
            guard frameLines.isEmpty == false else { return }
            let payload = frameLines.joined(separator: "\n")
            frameLines = []
            frameBytes = 0
            try await consumePayload(payload)
        } else if line.hasPrefix("data:") {
            var value = String(line.dropFirst(5))
            if value.hasPrefix(" ") { value.removeFirst() }
            frameBytes += value.utf8.count + 1
            guard frameBytes <= 512 * 1_024 else { throw AIProviderError.invalidProviderResponse }
            frameLines.append(value)
        }
        // SSE event/id/retry fields and keepalive comments carry no answer text.
    }

    func finish() throws -> Data {
        guard frameLines.isEmpty else { throw AIProviderError.invalidProviderResponse }
        return try codec.finalJSON().encodedData()
    }

    private func consumePayload(_ payload: String) async throws {
        let delta = try codec.consume(payload)
        if delta.isEmpty == false { try await onTextDelta(delta) }
    }
}
