import AIKit
import Foundation

nonisolated enum ExternalAgentEndpoint {
    static func parse(_ text: String) throws -> URL {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.utf8.count <= 2048, !text.contains("%"), !text.contains("\\"),
              var components = URLComponents(string: text), let host = components.host?.lowercased(), !host.isEmpty,
              components.user == nil, components.password == nil, components.query == nil, components.fragment == nil,
              components.port.map({ (1...65535).contains($0) }) ?? true else { throw ExternalAgentError.invalidEndpoint }
        let loopback = ["localhost", "127.0.0.1", "[::1]", "::1"].contains(host)
        guard components.scheme == "https" || (components.scheme == "http" && loopback) else { throw ExternalAgentError.invalidEndpoint }
        var path = components.path
        if path.hasSuffix("/") { path.removeLast() }
        let parts = path.split(separator: "/", omittingEmptySubsequences: false)
        guard path.hasSuffix("/v1"), !parts.contains(".."), !parts.contains("."),
              !path.contains("//"), path.unicodeScalars.allSatisfy({ !CharacterSet.controlCharacters.contains($0) }) else {
            throw ExternalAgentError.invalidEndpoint
        }
        components.path = path
        guard let url = components.url else { throw ExternalAgentError.invalidEndpoint }
        return url
    }
    static func validToken(_ token: String) -> Bool {
        (1...4096).contains(token.utf8.count) && token.utf8.allSatisfy { (32...126).contains($0) }
    }
    static func validTarget(_ value: String) -> Bool {
        !value.isEmpty && value.utf8.count <= 256 && value == value.trimmingCharacters(in: .whitespacesAndNewlines)
            && !value.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains)
    }
}
