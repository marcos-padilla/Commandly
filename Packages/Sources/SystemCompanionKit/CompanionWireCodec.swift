import Foundation
import Infrastructure

/// Canonical JSON disallows extra/duplicate keys and alternate enum shapes, before any native dispatch.
public enum CompanionWireCodec {
    public static func encode(_ request: CompanionRequest) throws -> Data {
        try validate(request)
        return try encodeValue(request, maximum: CompanionLimits.requestBytes)
    }
    public static func decodeRequest(_ data: Data) throws -> CompanionRequest {
        let request: CompanionRequest = try decodeValue(data, maximum: CompanionLimits.requestBytes)
        try validate(request)
        return request
    }
    public static func encode(_ reply: CompanionReply) throws -> Data {
        try validate(reply)
        return try encodeValue(reply, maximum: CompanionLimits.replyBytes)
    }
    public static func decodeReply(_ data: Data) throws -> CompanionReply {
        let reply: CompanionReply = try decodeValue(data, maximum: CompanionLimits.replyBytes)
        try validate(reply)
        return reply
    }
    private static func encodeValue<T: Encodable>(_ value: T, maximum: Int) throws -> Data {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(value)
        guard data.count <= maximum else { throw CompanionError.oversizedMessage }
        return data
    }
    private static func decodeValue<T: Codable>(_ data: Data, maximum: Int) throws -> T {
        guard data.count <= maximum else { throw CompanionError.oversizedMessage }
        try checkNesting(data)
        do {
            let value = try JSONDecoder().decode(T.self, from: data)
            guard try encodeValue(value, maximum: maximum) == data else { throw CompanionError.malformedMessage }
            return value
        } catch let error as CompanionError { throw error }
        catch { throw CompanionError.malformedMessage }
    }
    private static func checkNesting(_ data: Data) throws {
        var depth = 0; var inString = false; var escaped = false
        for byte in data {
            if inString {
                if escaped { escaped = false }
                else if byte == 92 { escaped = true }
                else if byte == 34 { inString = false }
            } else if byte == 34 { inString = true }
            else if byte == 123 || byte == 91 {
                depth += 1
                guard depth <= 16 else { throw CompanionError.malformedMessage }
            } else if byte == 125 || byte == 93 { depth -= 1 }
        }
        guard depth == 0, inString == false else { throw CompanionError.malformedMessage }
    }
    private static func validate(_ request: CompanionRequest) throws {
        guard request.sequence > 0, validBuild(request.build), (1...CompanionLimits.timeoutMilliseconds).contains(request.timeoutMilliseconds) else {
            throw CompanionError.malformedMessage
        }
        switch request.operation {
        case .handshake, .status, .openSession, .closeSession:
            guard request.action == nil, request.cancelRequestID == nil else { throw CompanionError.malformedMessage }
        case .cancel:
            guard request.action == nil, request.cancelRequestID != nil, request.cancelRequestID != request.id else { throw CompanionError.malformedMessage }
        case .keyboardTriggerAction:
            guard case .keyboardTrigger(let value) = request.action else { throw CompanionError.malformedMessage }
            if case .configure(let configuration) = value, !configuration.isValid { throw CompanionError.malformedMessage }
        case .appMenuAction:
            guard let session = request.session, case .appMenu(let value) = request.action else { throw CompanionError.malformedMessage }
            if case .invoke(let handle) = value, handle.session != session { throw CompanionError.malformedMessage }
        case .windowLayoutAction:
            guard request.session != nil, case .windowLayout(let value) = request.action else { throw CompanionError.malformedMessage }
            if case .apply(let handle, let rect) = value {
                guard handle.session == request.session, rect.isValid else { throw CompanionError.malformedMessage }
            }
        case .windowAction:
            guard case .window(let value) = request.action, value.handle.session == request.session else { throw CompanionError.malformedMessage }
        case .menuAction:
            guard case .menu(let value) = request.action, value.handle.session == request.session else { throw CompanionError.malformedMessage }
        case .selectionAction:
            guard case .selection(let value) = request.action else { throw CompanionError.malformedMessage }
            if case .replace(let handle, _, let text) = value {
                guard handle.session == request.session, text.utf8.count <= CompanionLimits.textBytes else { throw CompanionError.oversizedMessage }
            }
        case .triggerAction:
            guard case .trigger(let value) = request.action else { throw CompanionError.malformedMessage }
            if case .configure(_, _, let command) = value {
                guard command.isEmpty == false, command.utf8.count <= 200,
                      command.unicodeScalars.allSatisfy({ CharacterSet.alphanumerics.union(CharacterSet(charactersIn: ".-_:")).contains($0) }) else {
                    throw CompanionError.malformedMessage
                }
            }
        case .lifecycleAction:
            guard case .lifecycle(let value) = request.action, value.handle.session == request.session else { throw CompanionError.malformedMessage }
        }
        if request.action != nil, request.cancelRequestID != nil { throw CompanionError.malformedMessage }
    }
    private static func validate(_ reply: CompanionReply) throws {
        if case .keyboardTrigger(.activations(let values)) = reply.value {
            guard values.count <= 32, Set(values.map(\.id)).count == values.count else { throw CompanionError.malformedMessage }
        }
        if case .windowLayout(.applied(let receipt)) = reply.value {
            guard receipt.isValid else { throw CompanionError.malformedMessage }
        }
        if case .appMenu(.snapshot(let snapshot)) = reply.value {
            guard !snapshot.bundleIdentifier.isEmpty, snapshot.bundleIdentifier.utf8.count <= 255,
                  snapshot.items.count <= CompanionLimits.menuEntries,
                  Set(snapshot.items.map(\.handle)).count == snapshot.items.count,
                  Set(snapshot.items.map { $0.handle.session }).count <= 1,
                  snapshot.items.allSatisfy({ $0.identity.isValid && $0.identity.bundleIdentifier == snapshot.bundleIdentifier
                    && $0.title.utf8.count <= 512 && $0.ancestors.count <= 12 && $0.ancestors.allSatisfy { $0.utf8.count <= 512 } }) else { throw CompanionError.malformedMessage }
        }
        if case .status(let status) = reply.value {
            guard validBuild(status.build), status.capabilities.count <= CompanionCapability.allCases.count,
                  Set(status.capabilities.map(\.capability)).count == status.capabilities.count else { throw CompanionError.malformedMessage }
        }
    }
    public static func validBuild(_ value: String) -> Bool {
        value.isEmpty == false && value.utf8.count <= 32
            && value.utf8.allSatisfy { (48...57).contains($0) || $0 == 46 }
    }
}
