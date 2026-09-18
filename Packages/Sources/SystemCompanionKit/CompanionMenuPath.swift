import CryptoKit
import Foundation
import Infrastructure

/// Exact transient fingerprint; titles remain only in the in-memory active snapshot.
public struct CompanionMenuPathComponent: Codable, Equatable, Sendable {
    public let index: Int
    public let role: String
    public let title: String
    public let identifier: String
    public let shortcut: String
    public init(index: Int, role: String, title: String, identifier: String = "", shortcut: String = "") {
        self.index = index; self.role = role; self.title = title; self.identifier = identifier; self.shortcut = shortcut
    }
    public var isValid: Bool {
        (0..<500).contains(index) && [role, title, identifier, shortcut].allSatisfy {
            $0.utf8.count <= 512 && !$0.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) })
        }
    }
}
/// Native worker candidates never contain AX objects; IDs resolve only inside that worker.
public struct CompanionMenuCandidate: Equatable, Sendable {
    public let id: UUID
    public let path: [CompanionMenuPathComponent]
    public let enabled: Bool
    public init(id: UUID = UUID(), path: [CompanionMenuPathComponent], enabled: Bool) {
        self.id = id; self.path = path; self.enabled = enabled
    }
    public func identity(bundle: String) throws -> CompanionMenuIdentity {
        guard !path.isEmpty, path.count <= 12, path.allSatisfy(\.isValid) else { throw CompanionAppMenuError.invalidData }
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        let components = try path.map {
            CompanionMenuIdentity.Component(index: $0.index, digest: SHA256.hash(data: try encoder.encode($0)).map { String(format: "%02x", $0) }.joined())
        }
        let value = CompanionMenuIdentity(bundleIdentifier: bundle, path: components)
        guard value.isValid else { throw CompanionAppMenuError.invalidData }
        return value
    }
    public func requireUnchanged(path current: [CompanionMenuPathComponent], enabled: Bool) throws {
        guard enabled, self.enabled, current == path else { throw CompanionAppMenuError.stale }
    }
}
