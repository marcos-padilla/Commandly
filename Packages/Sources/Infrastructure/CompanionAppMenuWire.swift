import Foundation

/// Canonical closed menu payloads for a future reviewed bound-channel route. This does not enable that route.
public enum CompanionAppMenuWire {
    public static func encodeRequest(_ request: CompanionAppMenuRequest) throws -> Data { try encode(request, limit: 2048) }
    public static func decodeRequest(_ data: Data) throws -> CompanionAppMenuRequest { try decode(data, as: CompanionAppMenuRequest.self, limit: 2048) }
    public static func encodeReply(_ reply: CompanionAppMenuReply) throws -> Data { try encode(reply, limit: 524_288) }
    public static func decodeReply(_ data: Data) throws -> CompanionAppMenuReply { try decode(data, as: CompanionAppMenuReply.self, limit: 524_288) }
    private static func encode<T: Encodable>(_ value: T, limit: Int) throws -> Data {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(value)
        guard data.count <= limit else { throw CompanionAppMenuError.tooLarge }
        return data
    }
    private static func decode<T: Codable>(_ data: Data, as: T.Type, limit: Int) throws -> T {
        guard !data.isEmpty, data.count <= limit else { throw CompanionAppMenuError.invalidData }
        var depth = 0; var quoted = false; var escape = false
        for byte in data {
            if quoted {
                if escape { escape = false } else if byte == 92 { escape = true } else if byte == 34 { quoted = false }
            } else if byte == 34 { quoted = true }
            else if byte == 91 || byte == 123 { depth += 1; guard depth <= 16 else { throw CompanionAppMenuError.invalidData } }
            else if byte == 93 || byte == 125 { depth -= 1; guard depth >= 0 else { throw CompanionAppMenuError.invalidData } }
        }
        guard depth == 0, !quoted else { throw CompanionAppMenuError.invalidData }
        do {
            let value = try JSONDecoder().decode(T.self, from: data)
            guard try encode(value, limit: limit) == data else { throw CompanionAppMenuError.invalidData }
            return value
        } catch { throw CompanionAppMenuError.invalidData }
    }
}
