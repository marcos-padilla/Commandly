import Foundation

/// A configured physical key. Printable single keys pass through editable/unknown contexts.
public enum CompanionTriggerKey: UInt16, Codable, CaseIterable, Sendable {
    case a = 0, s = 1, d = 2, f = 3, h = 4, g = 5, z = 6, x = 7, c = 8, v = 9, b = 11
    case q = 12, w = 13, e = 14, r = 15, y = 16, t = 17, o = 31, u = 32, i = 34, p = 35
    case l = 37, j = 38, k = 40, n = 45, m = 46
    case f1 = 122, f2 = 120, f3 = 99, f4 = 118, f5 = 96, f6 = 97, f7 = 98, f8 = 100
    case f9 = 101, f10 = 109, f11 = 103, f12 = 111, f13 = 105, f14 = 107, f15 = 113
    case f16 = 106, f17 = 64, f18 = 79, f19 = 80, f20 = 90
    public var isFunctionKey: Bool { rawValue >= 64 }
    public var title: String { String(describing: self).uppercased() }
}
/// Double-tap bindings intentionally accept only modifier keys; the first tap always passes through.
public enum CompanionDoubleTapKey: UInt16, Codable, CaseIterable, Sendable {
    case leftShift = 56, rightShift = 60, leftControl = 59, rightControl = 62
    case leftOption = 58, rightOption = 61, leftCommand = 55, rightCommand = 54
}
/// No command identifier, path, or argument is needed by the helper; the main app retains that mapping.
public struct CompanionKeyBinding: Codable, Equatable, Sendable {
    public let id: UUID
    public let key: CompanionTriggerKey
    public let requiresHyper: Bool
    public init(id: UUID, key: CompanionTriggerKey, requiresHyper: Bool = false) {
        self.id = id; self.key = key; self.requiresHyper = requiresHyper
    }
}
/// An explicitly assigned two-tap modifier binding.
public struct CompanionDoubleTapBinding: Codable, Equatable, Sendable {
    public let id: UUID
    public let key: CompanionDoubleTapKey
    public init(id: UUID, key: CompanionDoubleTapKey) { self.id = id; self.key = key }
}
/// Reviewed literal expansion. Dynamic/clipboard/named-input snippets require the interactive library flow.
public struct CompanionKeywordExpansion: Codable, Equatable, Sendable {
    public let id: UUID
    public let keyword: String
    public let replacement: String
    public init(id: UUID, keyword: String, replacement: String) {
        self.id = id; self.keyword = keyword; self.replacement = replacement
    }
}
/// Session-only configuration. Constructing or decoding this value does not enable input observation.
public struct CompanionKeyboardConfiguration: Codable, Equatable, Sendable {
    public let revision: UUID
    public let hyperEnabled: Bool
    public let preserveCapsLockTap: Bool
    public let keys: [CompanionKeyBinding]
    public let doubleTaps: [CompanionDoubleTapBinding]
    public let expansions: [CompanionKeywordExpansion]
    public init(revision: UUID = UUID(), hyperEnabled: Bool = false, preserveCapsLockTap: Bool = true,
                keys: [CompanionKeyBinding] = [], doubleTaps: [CompanionDoubleTapBinding] = [],
                expansions: [CompanionKeywordExpansion] = []) {
        self.revision = revision; self.hyperEnabled = hyperEnabled; self.preserveCapsLockTap = preserveCapsLockTap
        self.keys = keys; self.doubleTaps = doubleTaps; self.expansions = expansions
    }
    /// Bounds both peer decoding and the helper's private suffix/configuration memory.
    public var isValid: Bool {
        let ids = keys.map(\.id) + doubleTaps.map(\.id) + expansions.map(\.id)
        return keys.count <= 64 && doubleTaps.count <= 8 && expansions.count <= 128
            && Set(ids).count == ids.count
            && Set(keys.map { "\($0.key.rawValue):\($0.requiresHyper)" }).count == keys.count
            && (hyperEnabled || keys.allSatisfy { !$0.requiresHyper })
            && Set(doubleTaps.map(\.key)).count == doubleTaps.count
            && Set(expansions.map(\.keyword)).count == expansions.count
            && expansions.allSatisfy { value in
                (2...32).contains(value.keyword.utf8.count)
                    && value.keyword.utf8.allSatisfy { (33...126).contains($0) }
                    && value.keyword.first.map { !$0.isLetter && !$0.isNumber } == true
                    && !value.replacement.isEmpty && value.replacement.utf8.count <= 8_192
            }
            && expansions.reduce(0, { $0 + $1.replacement.utf8.count }) <= 64 * 1024
    }
}
/// Input permission is requested only by the helper's visible Settings action, never by configure.
public enum CompanionKeyboardTriggerRequest: Codable, Equatable, Sendable {
    case configure(CompanionKeyboardConfiguration)
    case stop
    case nextActivations
}
/// An activation is only a session/configuration-bound opaque binding, never an input event.
public struct CompanionKeyboardActivation: Codable, Equatable, Sendable {
    public let id: UUID
    public let bindingID: UUID
    public let revision: UUID
    public init(id: UUID = UUID(), bindingID: UUID, revision: UUID) {
        self.id = id; self.bindingID = bindingID; self.revision = revision
    }
}
/// Fixed, content-free failures suitable for Settings recovery.
public enum CompanionKeyboardError: String, Codable, Error, Sendable {
    case disabled, permissionDenied, secureInput, invalidConfiguration, unsupportedKeyboard, disconnected, expired, unavailable, canceled
}
/// Polling never discloses raw input, app names, suffixes or field content.
public enum CompanionKeyboardTriggerReply: Codable, Equatable, Sendable {
    case configured(UUID)
    case stopped
    case activations([CompanionKeyboardActivation])
    case failure(CompanionKeyboardError)
}
/// Main app operations are available only through the authenticated bound action session.
public protocol CompanionKeyboardTriggerOperating: Sendable {
    func keyboardTriggers(_ request: CompanionKeyboardTriggerRequest) async throws -> CompanionKeyboardTriggerReply
}

/// Production composition is separately reviewed; constructors and Settings never open this gate.
public enum CompanionKeyboardTriggerReleaseGate { public static let reviewed = false }
/// Generated product fixtures never register input observation.
public struct UnavailableCompanionKeyboardTriggers: CompanionKeyboardTriggerOperating {
    public init() {}
    public func keyboardTriggers(_ request: CompanionKeyboardTriggerRequest) async throws -> CompanionKeyboardTriggerReply { .failure(.disabled) }
}
