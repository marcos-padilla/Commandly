import Foundation

/// High-level effect of an AI tool on user data.
public enum AIToolEffect: String, Sendable, Codable, Equatable {
    case readOnly
    case mutating
    case destructive
}

/// Whether the runtime must obtain user confirmation before executing a tool.
public enum AIToolConfirmationRequirement: String, Sendable, Codable, Equatable {
    case never
    case always
}

/// Provider-neutral tool definition presented to an AI model.
public struct AIToolDefinition: Sendable, Codable, Equatable, Identifiable {
    public var id: String { name }
    public let name: String
    public let description: String
    public let inputSchema: AIJSONSchema
    public let effect: AIToolEffect
    public let confirmation: AIToolConfirmationRequirement

    /// Creates a tool definition.
    ///
    /// `effect` and `confirmation` are local policy metadata. Provider adapters intentionally omit
    /// them from outbound requests; the execution layer must enforce them before invoking a tool.
    public init(
        name: String,
        description: String,
        inputSchema: AIJSONSchema,
        effect: AIToolEffect,
        confirmation: AIToolConfirmationRequirement
    ) {
        self.name = name
        self.description = description
        self.inputSchema = inputSchema
        self.effect = effect
        self.confirmation = confirmation
    }

    /// Validates portable provider constraints for this tool.
    public func validate() throws {
        guard !name.isEmpty, name.count <= 64 else {
            throw AIToolDefinitionError.invalidName
        }
        let isPortableASCIIName = name.utf8.allSatisfy { byte in
            (byte >= 48 && byte <= 57)
                || (byte >= 65 && byte <= 90)
                || (byte >= 97 && byte <= 122)
                || byte == 95
                || byte == 45
        }
        guard isPortableASCIIName else {
            throw AIToolDefinitionError.invalidName
        }
        guard !description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw AIToolDefinitionError.emptyDescription
        }
        guard case .object = inputSchema else {
            throw AIToolDefinitionError.inputSchemaMustBeObject
        }
        try inputSchema.validate()
    }
}

/// A tool invocation requested by a model.
public struct AIToolCall: Sendable, Codable, Equatable, Identifiable {
    public let id: String
    public let name: String
    public let arguments: AIJSONValue

    public init(id: String, name: String, arguments: AIJSONValue) {
        self.id = id
        self.name = name
        self.arguments = arguments
    }
}

/// Result supplied to a model after local tool execution.
public struct AIToolResult: Sendable, Codable, Equatable {
    public let callID: String
    public let toolName: String
    public let content: AIJSONValue
    public let isError: Bool

    public init(
        callID: String,
        toolName: String,
        content: AIJSONValue,
        isError: Bool = false
    ) {
        self.callID = callID
        self.toolName = toolName
        self.content = content
        self.isError = isError
    }
}

/// Tool-selection preference for a completion request.
public enum AIToolChoice: Sendable, Codable, Equatable {
    case automatic
    case none
    case required
    case tool(named: String)
}

public enum AIToolDefinitionError: Error, Sendable, Equatable {
    case invalidName
    case emptyDescription
    case inputSchemaMustBeObject
}
