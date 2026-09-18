import AIKit
import CommandKit
import Foundation
import ModuleKit

/// Runtime eligibility for exposing one reviewed command to AI.
///
/// Review is a build-time decision recorded in a module's ``ModuleCommandPolicy``. Eligibility is a
/// runtime decision that additionally considers module enablement, capabilities, connection state,
/// and the caller's own grants.
@MainActor
public protocol AICommandEligibilityEvaluating: AnyObject, Sendable {
    /// Whether the command may be offered to the model right now.
    func isEligible(_ definition: ModuleCommandDefinition) -> Bool
}

/// Eligibility evaluator that only enforces the build-time review decision.
///
/// Suitable for tests and for a host that has not wired capability state yet. A production host
/// supplies an evaluator that also checks module availability and caller grants.
@MainActor
public final class ReviewOnlyEligibilityEvaluator: AICommandEligibilityEvaluating {
    public init() {}

    public func isEligible(_ definition: ModuleCommandDefinition) -> Bool {
        definition.policy.aiExposure == .reviewed
    }
}

/// Failures raised while adapting a model tool call.
public enum AICommandBridgeError: Error, Equatable, Sendable {
    /// The provider tool name does not map to any exposed command.
    case unknownTool(name: String)
    /// Arguments were not a JSON object.
    case argumentsNotAnObject
    /// An argument is not declared by the command schema.
    case unknownArgument(name: String)
    /// A required argument was absent.
    case missingRequiredArgument(name: String)
    /// An argument's JSON type does not match the declared schema type.
    case argumentTypeMismatch(name: String)
    /// The arguments payload exceeded the accepted size.
    case argumentsTooLarge
    /// The command declares an argument type the bridge does not expose to providers.
    case unsupportedArgumentType(name: String)
}

/// Adapts module commands to the existing `AIKit` tool contracts.
///
/// The bridge is deliberately narrow:
///
/// - It **never** imports a feature target. It sees only ``ModuleCommandDefinition`` metadata.
/// - It **never** calls a feature service. Every accepted call is routed through
///   ``ModuleCommandDispatching``, the application's one authoritative execution path.
/// - Exposure is **default-deny**: a command is offered only when its module authored
///   ``ModuleCommandAIExposure/reviewed`` *and* the runtime evaluator agrees.
/// - Model-supplied arguments cannot create authority. Grants come from the host, not the call.
@MainActor
public final class AICommandBridge {
    /// Largest accepted serialized argument payload, in bytes.
    public static let maximumArgumentBytes = 16 * 1024

    private let dispatcher: any ModuleCommandDispatching
    private let eligibility: any AICommandEligibilityEvaluating
    private let definitionsProvider: @MainActor () -> [ModuleCommandDefinition]

    /// Creates a bridge.
    ///
    /// - Parameters:
    ///   - definitions: supplies the current canonical command catalog. Reading it must not
    ///     activate modules.
    ///   - dispatcher: the shared execution path every accepted call is routed through.
    ///   - eligibility: runtime exposure policy applied on top of the build-time review.
    public init(
        definitions: @escaping @MainActor () -> [ModuleCommandDefinition],
        dispatcher: any ModuleCommandDispatching,
        eligibility: any AICommandEligibilityEvaluating = ReviewOnlyEligibilityEvaluator()
    ) {
        self.definitionsProvider = definitions
        self.dispatcher = dispatcher
        self.eligibility = eligibility
    }

    /// Commands currently eligible for AI exposure, in deterministic order.
    public func exposedDefinitions() -> [ModuleCommandDefinition] {
        definitionsProvider()
            .filter { $0.policy.aiExposure == .reviewed }
            .filter { eligibility.isEligible($0) }
            .sorted { $0.id.rawValue < $1.id.rawValue }
    }

    /// Provider-neutral tool definitions for the currently exposed commands.
    ///
    /// The schema is generated from the same canonical definition the executor validates against,
    /// so exported schemas and runtime validation cannot drift apart.
    public func availableTools() throws -> [AIToolDefinition] {
        let definitions = exposedDefinitions()
        let map = try AICommandToolNameMap(commandIDs: definitions.map(\.id))
        return try definitions.compactMap { definition in
            guard let name = map.name(for: definition.id) else { return nil }
            let tool = AIToolDefinition(
                name: name,
                description: definition.summary,
                inputSchema: try Self.inputSchema(for: definition),
                effect: Self.effect(for: definition.policy),
                confirmation: definition.policy.requiresExactApproval ? .always : .never
            )
            try tool.validate()
            return tool
        }
    }

    /// Executes a model tool call through the shared executor.
    ///
    /// Malformed, unknown, oversized, and unsupported inputs are rejected **before** dispatch, so a
    /// rejected call has no effect. Denied, unavailable, and interaction-required outcomes are
    /// reported truthfully rather than as success.
    public func invoke(
        _ call: AIToolCall,
        context: CommandInvocationContext,
        grants: ModuleCallerGrants = [.automation]
    ) async -> AIToolResult {
        let definitions = exposedDefinitions()
        guard let map = try? AICommandToolNameMap(commandIDs: definitions.map(\.id)),
              let commandID = map.commandID(forToolName: call.name),
              let definition = definitions.first(where: { $0.id == commandID }) else {
            return Self.errorResult(call, message: "Unknown tool.")
        }

        let arguments: CommandArguments
        do {
            arguments = try Self.arguments(from: call.arguments, definition: definition)
        } catch let error as AICommandBridgeError {
            return Self.errorResult(call, message: Self.message(for: error))
        } catch {
            return Self.errorResult(call, message: "Tool input is invalid.")
        }

        let outcome = await dispatcher.dispatch(
            reference: CommandReference(commandID: commandID, arguments: arguments),
            grants: grants,
            context: context
        )
        return Self.result(for: outcome, call: call)
    }

    // MARK: - Schema generation

    private static func effect(for policy: ModuleCommandPolicy) -> AIToolEffect {
        switch policy.effect {
        case .readOnly:
            return .readOnly
        case .localMutation, .externalAction:
            return .mutating
        case .filesystemMutation:
            return .destructive
        }
    }

    static func inputSchema(for definition: ModuleCommandDefinition) throws -> AIJSONSchema {
        var properties: [String: AIJSONSchema] = [:]
        var required: [String] = []
        for argument in definition.manifest.arguments.sorted(by: { $0.name < $1.name }) {
            properties[argument.name] = try schema(for: argument)
            if argument.isRequired, argument.defaultValue == nil {
                required.append(argument.name)
            }
        }
        return .closedObject(
            properties: properties,
            required: required,
            description: definition.summary
        )
    }

    private static func schema(for argument: CommandArgument) throws -> AIJSONSchema {
        switch argument.valueType {
        case .string, .url:
            return .string(allowedValues: nil, description: argument.description)
        case .boolean:
            return .boolean(description: argument.description)
        case .integer:
            return .integer(minimum: nil, maximum: nil, description: argument.description)
        case .decimal:
            return .number(minimum: nil, maximum: nil, description: argument.description)
        case .stringList:
            return .array(
                items: .string(allowedValues: nil, description: nil),
                description: argument.description
            )
        }
    }

    // MARK: - Argument validation

    static func arguments(
        from value: AIJSONValue,
        definition: ModuleCommandDefinition
    ) throws -> CommandArguments {
        guard case .object(let object) = value else {
            throw AICommandBridgeError.argumentsNotAnObject
        }
        let encoded = try JSONEncoder().encode(value)
        guard encoded.count <= maximumArgumentBytes else {
            throw AICommandBridgeError.argumentsTooLarge
        }

        let schemaByName = Dictionary(
            uniqueKeysWithValues: definition.manifest.arguments.map { ($0.name, $0) }
        )
        for name in object.keys.sorted() where schemaByName[name] == nil {
            throw AICommandBridgeError.unknownArgument(name: name)
        }

        var values: [String: CommandArgumentValue] = [:]
        for argument in definition.manifest.arguments {
            guard let raw = object[argument.name] else {
                if argument.isRequired, argument.defaultValue == nil {
                    throw AICommandBridgeError.missingRequiredArgument(name: argument.name)
                }
                continue
            }
            values[argument.name] = try convert(raw, to: argument)
        }
        return CommandArguments(values)
    }

    private static func convert(
        _ value: AIJSONValue,
        to argument: CommandArgument
    ) throws -> CommandArgumentValue {
        switch (argument.valueType, value) {
        case (.string, .string(let text)):
            return .string(text)
        case (.boolean, .boolean(let flag)):
            return .boolean(flag)
        case (.integer, .number(let number)):
            // JSON has one numeric type. A whole-number argument must receive a whole number:
            // 5.5 is rejected rather than silently truncated.
            guard number.isFinite,
                  number.rounded() == number,
                  number >= Double(Int.min),
                  number <= Double(Int.max) else {
                throw AICommandBridgeError.argumentTypeMismatch(name: argument.name)
            }
            return .integer(Int(number))
        case (.decimal, .number(let number)):
            guard number.isFinite else {
                throw AICommandBridgeError.argumentTypeMismatch(name: argument.name)
            }
            return .decimal(number)
        case (.url, .string(let text)):
            guard let url = URL(string: text) else {
                throw AICommandBridgeError.argumentTypeMismatch(name: argument.name)
            }
            return .url(url)
        case (.stringList, .array(let items)):
            var texts: [String] = []
            for item in items {
                guard case .string(let text) = item else {
                    throw AICommandBridgeError.argumentTypeMismatch(name: argument.name)
                }
                texts.append(text)
            }
            return .stringList(texts)
        default:
            throw AICommandBridgeError.argumentTypeMismatch(name: argument.name)
        }
    }

    // MARK: - Results

    private static func message(for error: AICommandBridgeError) -> String {
        switch error {
        case .unknownTool:
            return "Unknown tool."
        case .argumentsNotAnObject:
            return "Tool input must be an object."
        case .unknownArgument(let name):
            return "Unknown argument “\(name)”."
        case .missingRequiredArgument(let name):
            return "Missing required argument “\(name)”."
        case .argumentTypeMismatch(let name):
            return "Argument “\(name)” has the wrong type."
        case .argumentsTooLarge:
            return "Tool input is too large."
        case .unsupportedArgumentType(let name):
            return "Argument “\(name)” is not supported."
        }
    }

    private static func errorResult(_ call: AIToolCall, message: String) -> AIToolResult {
        AIToolResult(
            callID: call.id,
            toolName: call.name,
            content: .object(["status": .string("error"), "message": .string(message)]),
            isError: true
        )
    }

    static func result(for outcome: ModuleCommandOutcome, call: AIToolCall) -> AIToolResult {
        var payload: [String: AIJSONValue] = [:]
        var isError = false

        switch outcome {
        case .succeeded(let message, let output):
            payload["status"] = .string("succeeded")
            if let message { payload["message"] = .string(message) }
            if output.values.isEmpty == false {
                payload["output"] = .object(output.values.mapValues(jsonValue(for:)))
            }
        case .failed(let message):
            payload["status"] = .string("failed")
            payload["message"] = .string(message)
            isError = true
        case .cancelled:
            payload["status"] = .string("cancelled")
            isError = true
        case .denied(let reason, let message):
            payload["status"] = .string("denied")
            payload["reason"] = .string(reason.rawValue)
            payload["message"] = .string(message)
            isError = true
        case .unavailable(_, let message):
            payload["status"] = .string("unavailable")
            payload["message"] = .string(message)
            isError = true
        case .interactionRequired(let message):
            payload["status"] = .string("interaction_required")
            payload["message"] = .string(message)
            isError = true
        case .accepted(let operationID, let message):
            payload["status"] = .string("accepted")
            payload["operationID"] = .string(operationID.rawValue)
            if let message { payload["message"] = .string(message) }
        }

        return AIToolResult(
            callID: call.id,
            toolName: call.name,
            content: .object(payload),
            isError: isError
        )
    }

    private static func jsonValue(for value: CommandArgumentValue) -> AIJSONValue {
        switch value {
        case .string(let text): return .string(text)
        case .boolean(let flag): return .boolean(flag)
        case .integer(let number): return .number(Double(number))
        case .decimal(let number): return .number(number)
        case .url(let url): return .string(url.absoluteString)
        case .stringList(let items): return .array(items.map(AIJSONValue.string))
        }
    }
}
