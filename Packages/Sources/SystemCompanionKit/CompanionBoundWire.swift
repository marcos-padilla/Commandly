import Foundation
import Infrastructure

/// Metadata-only bootstrap. These generated IDs are not application content or native target handles.
public struct CompanionBoundHello: Codable, Equatable, Sendable {
    public let version: Int
    public let requestID: UUID
    public let clientNonce: UUID
    public let build: String
    public init(version: Int = CompanionLimits.protocolVersion, requestID: UUID = UUID(), clientNonce: UUID = UUID(), build: String) {
        self.version = version; self.requestID = requestID; self.clientNonce = clientNonce; self.build = build
    }
}
/// Binds an authenticated bootstrap reply to one anonymous listener, not a rediscoverable service name.
public struct CompanionBoundTicket: Codable, Equatable, Sendable {
    public let hello: CompanionBoundHello
    public let listenerID: UUID
    public let serverNonce: UUID
    public init(hello: CompanionBoundHello, listenerID: UUID = UUID(), serverNonce: UUID = UUID()) {
        self.hello = hello; self.listenerID = listenerID; self.serverNonce = serverNonce
    }
}
/// A second fresh challenge must be echoed over the endpoint connection before it is usable.
public struct CompanionBoundProof: Codable, Equatable, Sendable {
    public let ticket: CompanionBoundTicket
    public let challenge: UUID
    public init(ticket: CompanionBoundTicket, challenge: UUID = UUID()) { self.ticket = ticket; self.challenge = challenge }
}
/// Closed 4 KiB canonical bootstrap schema. Unknown/duplicate fields and alternate encodings fail closed.
public enum CompanionBoundWire {
    private struct Failure: Codable { let error: CompanionError }
    static func failure(_ error: any Error) -> Data {
        (try? encode(Failure(error: (error as? CompanionError) ?? .malformedMessage))) ?? Data()
    }
    public static let maximumBytes = 4_096
    public static func encode<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(value)
        guard data.count <= maximumBytes else { throw CompanionError.oversizedMessage }
        return data
    }
    public static func hello(_ data: Data) throws -> CompanionBoundHello {
        let value: CompanionBoundHello = try decode(data); try validate(value); return value
    }
    public static func ticket(_ data: Data) throws -> CompanionBoundTicket {
        if let failure: Failure = try? decode(data) { throw failure.error }
        let value: CompanionBoundTicket = try decode(data); try validate(value.hello); return value
    }
    public static func proof(_ data: Data) throws -> CompanionBoundProof {
        if let failure: Failure = try? decode(data) { throw failure.error }
        let value: CompanionBoundProof = try decode(data); try validate(value.ticket.hello); return value
    }
    public static func validate(_ hello: CompanionBoundHello) throws {
        guard hello.version == CompanionLimits.protocolVersion else { throw CompanionError.unsupportedVersion }
        guard CompanionWireCodec.validBuild(hello.build) else { throw CompanionError.malformedMessage }
    }
    private static func decode<T: Codable>(_ data: Data) throws -> T {
        guard data.count <= maximumBytes else { throw CompanionError.oversizedMessage }
        // The small byte limit plus a nesting preflight bounds Foundation decoder work.
        var depth = 0; var quoted = false; var escaped = false
        for byte in data {
            if quoted {
                if escaped { escaped = false } else if byte == 92 { escaped = true } else if byte == 34 { quoted = false }
            } else if byte == 34 { quoted = true }
            else if byte == 123 || byte == 91 { depth += 1; guard depth <= 8 else { throw CompanionError.malformedMessage } }
            else if byte == 125 || byte == 93 { depth -= 1; guard depth >= 0 else { throw CompanionError.malformedMessage } }
        }
        guard depth == 0, quoted == false else { throw CompanionError.malformedMessage }
        do {
            let value = try JSONDecoder().decode(T.self, from: data)
            guard try encode(value) == data else { throw CompanionError.malformedMessage }
            return value
        } catch let error as CompanionError { throw error }
        catch { throw CompanionError.malformedMessage }
    }
}

/// Named bootstrap carries only generated metadata and a Foundation secure-coded endpoint object.
@objc public protocol CompanionBootstrapXPCProtocol: CompanionXPCProtocol {
    func bootstrap(_ hello: Data, withReply reply: @escaping @Sendable (Data, NSXPCListenerEndpoint?) -> Void)
}
/// An anonymous endpoint must complete bind before even metadata requests are dispatched.
@objc public protocol CompanionBoundXPCProtocol: CompanionXPCProtocol {
    func bind(_ proof: Data, withReply reply: @escaping @Sendable (Data) -> Void)
}
