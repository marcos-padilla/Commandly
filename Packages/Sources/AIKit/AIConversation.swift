import Foundation

/// Provider-neutral role in an AI conversation.
public enum AIMessageRole: String, Sendable, Codable, Equatable {
    case system
    case user
    case assistant
    case tool
}

/// Content carried by a conversation message.
public enum AIMessageContent: Sendable, Codable, Equatable {
    case text(String)
    case json(AIJSONValue)
}

/// Provider-neutral conversation message.
public struct AIMessage: Sendable, Codable, Equatable {
    public let role: AIMessageRole
    public let content: [AIMessageContent]
    public let toolCalls: [AIToolCall]
    public let toolResults: [AIToolResult]

    public init(
        role: AIMessageRole,
        content: [AIMessageContent] = [],
        toolCalls: [AIToolCall] = [],
        toolResults: [AIToolResult] = []
    ) {
        self.role = role
        self.content = content
        self.toolCalls = toolCalls
        self.toolResults = toolResults
    }

    public static func system(_ text: String) -> AIMessage {
        AIMessage(role: .system, content: [.text(text)])
    }

    public static func user(_ text: String) -> AIMessage {
        AIMessage(role: .user, content: [.text(text)])
    }

    public static func assistant(
        _ text: String? = nil,
        toolCalls: [AIToolCall] = []
    ) -> AIMessage {
        AIMessage(
            role: .assistant,
            content: text.map { [.text($0)] } ?? [],
            toolCalls: toolCalls
        )
    }

    public static func tool(results: [AIToolResult]) -> AIMessage {
        AIMessage(role: .tool, toolResults: results)
    }
}

/// Opaque provider-owned continuation state.
///
/// Keep and pass this value back only to the same provider. Its representation is intentionally
/// inaccessible so application code cannot become coupled to a vendor response identifier.
public struct AIProviderState: Sendable, Equatable, CustomStringConvertible,
    CustomDebugStringConvertible, CustomReflectable
{
    public let providerID: AIProviderID
    private let payload: Data

    init(providerID: AIProviderID, payload: Data) {
        self.providerID = providerID
        self.payload = payload
    }

    func decodedString() -> String? {
        String(data: payload, encoding: .utf8)
    }

    var encodedByteCount: Int { payload.count }

    public var description: String {
        "AIProviderState(providerID: \(providerID.rawValue), payload: <redacted>)"
    }

    public var debugDescription: String { description }

    public var customMirror: Mirror {
        Mirror(
            self,
            children: [
                "providerID": providerID.rawValue,
                "payload": "<redacted>"
            ],
            displayStyle: .struct
        )
    }
}

/// A normalized request sent through a provider adapter.
public struct AICompletionRequest: Sendable, Equatable {
    public let modelID: String
    public let messages: [AIMessage]
    public let tools: [AIToolDefinition]
    public let toolChoice: AIToolChoice
    public let maximumOutputTokens: Int?
    public let temperature: Double?
    public let state: AIProviderState?

    public init(
        modelID: String,
        messages: [AIMessage],
        tools: [AIToolDefinition] = [],
        toolChoice: AIToolChoice = .automatic,
        maximumOutputTokens: Int? = nil,
        temperature: Double? = nil,
        state: AIProviderState? = nil
    ) {
        self.modelID = modelID
        self.messages = messages
        self.tools = tools
        self.toolChoice = toolChoice
        self.maximumOutputTokens = maximumOutputTokens
        self.temperature = temperature
        self.state = state
    }

    /// Validates provider-independent request invariants.
    public func validate(for providerID: AIProviderID) throws {
        guard !modelID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw AIProviderError.invalidRequest
        }
        guard !messages.isEmpty else { throw AIProviderError.invalidRequest }
        if let maximumOutputTokens, maximumOutputTokens <= 0 {
            throw AIProviderError.invalidRequest
        }
        if let temperature, !temperature.isFinite || !(0 ... 2).contains(temperature) {
            throw AIProviderError.invalidRequest
        }
        if case .none = toolChoice, !tools.isEmpty {
            // Valid: callers may explicitly disable otherwise available tools.
        } else if case let .tool(name) = toolChoice,
                  !tools.contains(where: { $0.name == name }) {
            throw AIProviderError.invalidRequest
        }
        guard Set(tools.map(\.name)).count == tools.count else {
            throw AIProviderError.invalidRequest
        }
        try tools.forEach { try $0.validate() }
        if let state, state.providerID != providerID {
            throw AIProviderError.configurationMismatch
        }

        for message in messages {
            try message.validate()
        }
    }
}

extension AIMessage {
    fileprivate func validate() throws {
        switch role {
        case .system, .user:
            guard toolCalls.isEmpty, toolResults.isEmpty, !content.isEmpty else {
                throw AIProviderError.invalidRequest
            }
        case .assistant:
            guard toolResults.isEmpty, !content.isEmpty || !toolCalls.isEmpty else {
                throw AIProviderError.invalidRequest
            }
        case .tool:
            guard content.isEmpty, toolCalls.isEmpty, !toolResults.isEmpty else {
                throw AIProviderError.invalidRequest
            }
        }
    }
}

/// Normalized reason a provider stopped generating.
public enum AIFinishReason: String, Sendable, Codable, Equatable {
    case completed
    case toolCalls
    case length
    case contentFiltered
    case refused
    case unknown
}

/// Provider-reported token accounting.
public struct AIUsage: Sendable, Codable, Equatable {
    public let inputTokens: Int?
    public let outputTokens: Int?
    public let totalTokens: Int?

    public init(inputTokens: Int?, outputTokens: Int?, totalTokens: Int?) {
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.totalTokens = totalTokens
    }
}

/// Normalized response returned by a provider adapter.
public struct AICompletionResponse: Sendable, Equatable {
    public let id: String?
    public let message: AIMessage
    public let finishReason: AIFinishReason
    public let usage: AIUsage?
    public let state: AIProviderState?

    public init(
        id: String?,
        message: AIMessage,
        finishReason: AIFinishReason,
        usage: AIUsage? = nil,
        state: AIProviderState? = nil
    ) {
        self.id = id
        self.message = message
        self.finishReason = finishReason
        self.usage = usage
        self.state = state
    }
}
