import CommandKit
import Foundation

/// Schema versions understood by Command Wheel persistence and transfer documents.
nonisolated enum CommandWheelSchema {
    static let legacyVersion = 0
    static let currentVersion = 1
}

/// The complete non-secret, persistable configuration for Command Wheel.
nonisolated struct CommandWheelConfiguration: Codable, Hashable, Sendable {
    var schemaVersion: Int
    var isEnabled: Bool
    var contextAwareProfileSelectionEnabled: Bool
    var defaultProfileID: UUID
    var profiles: [CommandWheelProfile]

    init(
        schemaVersion: Int = CommandWheelSchema.currentVersion,
        isEnabled: Bool,
        contextAwareProfileSelectionEnabled: Bool,
        defaultProfileID: UUID,
        profiles: [CommandWheelProfile]
    ) {
        self.schemaVersion = schemaVersion
        self.isEnabled = isEnabled
        self.contextAwareProfileSelectionEnabled = contextAwareProfileSelectionEnabled
        self.defaultProfileID = defaultProfileID
        self.profiles = profiles
    }
}

/// One ordered, user-configurable wheel and its contextual activation rules.
nonisolated struct CommandWheelProfile: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    var name: String
    var isEnabled: Bool
    var shortcut: LauncherHotKey?
    var activationBehavior: CommandWheelActivationBehavior
    var placement: CommandWheelPlacement
    var rootPageID: UUID
    var pages: [CommandWheelPage]
    var contextRules: [CommandWheelContextRule]
    var appearance: CommandWheelAppearanceConfiguration
    var interaction: CommandWheelInteractionConfiguration
    var hidesUnavailableSegments: Bool
}

/// One radial level. Pages form a validated rooted tree through submenu entries.
nonisolated struct CommandWheelPage: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    var name: String
    var segments: [CommandWheelSegment]
}

/// One stable radial slot on a wheel page.
nonisolated struct CommandWheelSegment: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    var slotIndex: Int
    var content: CommandWheelSegmentContent
    var customLabel: String?
    var customIcon: CommandWheelIconOverride?
}

/// Persistable content for a radial slot. It never stores executable behavior.
nonisolated enum CommandWheelSegmentContent: Hashable, Sendable {
    case command(CommandReference)
    case submenu(pageID: UUID)
    case dynamicProvider(CommandWheelDynamicProviderReference)
    case empty
}

extension CommandWheelSegmentContent: Codable {
    private enum CodingKeys: String, CodingKey {
        case type
        case command
        case pageID
        case dynamicProvider
    }

    private enum Kind: String, Codable {
        case command
        case submenu
        case dynamicProvider
        case empty
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(Kind.self, forKey: .type) {
        case .command:
            self = try .command(container.decode(CommandReference.self, forKey: .command))
        case .submenu:
            self = try .submenu(pageID: container.decode(UUID.self, forKey: .pageID))
        case .dynamicProvider:
            self = try .dynamicProvider(
                container.decode(
                    CommandWheelDynamicProviderReference.self,
                    forKey: .dynamicProvider
                )
            )
        case .empty:
            self = .empty
        }
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .command(let reference):
            try container.encode(Kind.command, forKey: .type)
            try container.encode(reference, forKey: .command)
        case .submenu(let pageID):
            try container.encode(Kind.submenu, forKey: .type)
            try container.encode(pageID, forKey: .pageID)
        case .dynamicProvider(let reference):
            try container.encode(Kind.dynamicProvider, forKey: .type)
            try container.encode(reference, forKey: .dynamicProvider)
        case .empty:
            try container.encode(Kind.empty, forKey: .type)
        }
    }
}

/// An optional user-selected SF Symbol override for a segment.
nonisolated struct CommandWheelIconOverride: Codable, Hashable, Sendable {
    var systemSymbolName: String
}

/// A reference to shared command-engine content that is frozen for one wheel session.
nonisolated struct CommandWheelDynamicProviderReference: Codable, Hashable, Sendable {
    var providerID: String
    var maximumResultCount: Int
    var sortingMethod: CommandWheelDynamicProviderSortingMethod
    var emptyState: CommandWheelDynamicProviderEmptyState
    var refreshStrategy: CommandWheelDynamicProviderRefreshStrategy
    var cachePolicy: CommandWheelDynamicProviderCachePolicy
}

nonisolated enum CommandWheelDynamicProviderSortingMethod: String, Codable, Hashable, Sendable {
    case providerDefault
    case mostRecent
    case mostFrequent
    case alphabetical
}

nonisolated enum CommandWheelDynamicProviderEmptyState: String, Codable, Hashable, Sendable {
    case showEmptySlots
    case hideSegment
}

nonisolated enum CommandWheelDynamicProviderRefreshStrategy: String, Codable, Hashable, Sendable {
    case onInvocation
    /// Reserved serialized value. The current schema rejects it until runtime support exists.
    case onProfileChange
    /// Reserved serialized value. The current schema rejects it until runtime support exists.
    case manual

    static let supported: Set<Self> = [.onInvocation]
}

nonisolated enum CommandWheelDynamicProviderCachePolicy: String, Codable, Hashable, Sendable {
    case invocation
    /// Reserved serialized value. The current schema rejects it until runtime support exists.
    case session

    static let supported: Set<Self> = [.invocation]
}

/// Stable dynamic provider identifiers currently backed by shared command history.
nonisolated enum CommandWheelDynamicProviderID {
    static let recentCommands = "commands.recent"
    static let frequentCommands = "commands.frequent"

    static let supported: Set<String> = [
        recentCommands,
        frequentCommands,
    ]
}

nonisolated enum CommandWheelActivationBehavior: String, Codable, Hashable, Sendable {
    case holdAndRelease
    case toggle
}

/// Where a wheel is initially placed. Fixed coordinates are normalized to a usable display frame.
nonisolated enum CommandWheelPlacement: Hashable, Sendable {
    case cursor
    case activeScreenCenter
    case fixedNormalizedPoint(screenIdentifier: String?, x: Double, y: Double)
}

extension CommandWheelPlacement: Codable {
    private enum CodingKeys: String, CodingKey {
        case type
        case screenIdentifier
        case x
        case y
    }

    private enum Kind: String, Codable {
        case cursor
        case activeScreenCenter
        case fixedNormalizedPoint
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(Kind.self, forKey: .type) {
        case .cursor:
            self = .cursor
        case .activeScreenCenter:
            self = .activeScreenCenter
        case .fixedNormalizedPoint:
            self = try .fixedNormalizedPoint(
                screenIdentifier: container.decodeIfPresent(
                    String.self,
                    forKey: .screenIdentifier
                ),
                x: container.decode(Double.self, forKey: .x),
                y: container.decode(Double.self, forKey: .y)
            )
        }
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .cursor:
            try container.encode(Kind.cursor, forKey: .type)
        case .activeScreenCenter:
            try container.encode(Kind.activeScreenCenter, forKey: .type)
        case .fixedNormalizedPoint(let screenIdentifier, let x, let y):
            try container.encode(Kind.fixedNormalizedPoint, forKey: .type)
            try container.encodeIfPresent(screenIdentifier, forKey: .screenIdentifier)
            try container.encode(x, forKey: .x)
            try container.encode(y, forKey: .y)
        }
    }
}

/// Visual preferences that do not alter selection behavior.
nonisolated struct CommandWheelAppearanceConfiguration: Codable, Hashable, Sendable {
    var wheelRadius: Double
    var startAngleDegrees: Double
    /// Legacy persisted preference retained for backward-compatible profile decoding.
    /// Runtime and preview wheels are intentionally icon-only regardless of this value.
    var showsLabels: Bool
    var showsKeyboardHints: Bool
    var animationPreference: CommandWheelAnimationPreference
}

nonisolated enum CommandWheelAnimationPreference: String, Codable, Hashable, Sendable {
    case system
    case reduced
    case disabled
}

/// Gesture and alternate-input thresholds used by the selection engine.
nonisolated struct CommandWheelInteractionConfiguration: Codable, Hashable, Sendable {
    var visibleSlotCount: Int
    var deadZoneRadius: Double
    var selectionRadius: Double
    var submenuActivationRadius: Double
    var submenuDwellDurationSeconds: Double
    var selectionHysteresisDegrees: Double
    var minimumSelectionMovement: Double
    var allowsClickSelection: Bool
    var allowsKeyboardSelection: Bool
    var submenuActivationBehavior: CommandWheelSubmenuActivationBehavior
}

nonisolated enum CommandWheelSubmenuActivationBehavior: String, Codable, Hashable, Sendable {
    case directionalContinuation
    case dwell
    case clickOnly
    case disabled
}

/// An exact frontmost-application match for the profile containing this rule.
nonisolated struct CommandWheelContextRule: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    var frontmostApplicationBundleIdentifier: String
    var priority: Int
    var isEnabled: Bool
}

/// Why a profile was selected for one invocation.
nonisolated struct CommandWheelProfileSelection: Codable, Hashable, Sendable {
    let profileID: UUID
    let reason: Reason

    enum Reason: Codable, Hashable, Sendable {
        case explicit
        case context(ruleID: UUID)
        case defaultProfile
    }
}

/// Resolves explicit, contextual, and default profile selection without polling application state.
nonisolated enum CommandWheelProfileSelector {
    static func resolve(
        configuration: CommandWheelConfiguration,
        explicitProfileID: UUID? = nil,
        allowsContextOverride: Bool = false,
        frontmostApplicationBundleIdentifier: String? = nil
    ) -> CommandWheelProfileSelection? {
        if let explicitProfileID, allowsContextOverride == false {
            guard configuration.profiles.contains(where: {
                $0.id == explicitProfileID && $0.isEnabled
            }) else {
                return nil
            }
            return CommandWheelProfileSelection(
                profileID: explicitProfileID,
                reason: .explicit
            )
        }

        if configuration.contextAwareProfileSelectionEnabled,
           let bundleIdentifier = normalizedBundleIdentifier(
               frontmostApplicationBundleIdentifier
           ) {
            let matches = configuration.profiles.enumerated().flatMap { profileIndex, profile in
                guard profile.isEnabled else {
                    return [ContextMatch]()
                }
                return profile.contextRules.enumerated().compactMap { ruleIndex, rule in
                    guard rule.isEnabled,
                          normalizedBundleIdentifier(
                              rule.frontmostApplicationBundleIdentifier
                          ) == bundleIdentifier else {
                        return nil
                    }
                    return ContextMatch(
                        profileID: profile.id,
                        ruleID: rule.id,
                        priority: rule.priority,
                        profileIndex: profileIndex,
                        ruleIndex: ruleIndex
                    )
                }
            }
            if let match = matches.sorted(by: ContextMatch.precedes).first {
                return CommandWheelProfileSelection(
                    profileID: match.profileID,
                    reason: .context(ruleID: match.ruleID)
                )
            }
        }

        if let explicitProfileID,
           configuration.profiles.contains(where: {
               $0.id == explicitProfileID && $0.isEnabled
           }) {
            return CommandWheelProfileSelection(
                profileID: explicitProfileID,
                reason: .explicit
            )
        }

        guard configuration.profiles.contains(where: {
            $0.id == configuration.defaultProfileID && $0.isEnabled
        }) else {
            return nil
        }
        return CommandWheelProfileSelection(
            profileID: configuration.defaultProfileID,
            reason: .defaultProfile
        )
    }

    private struct ContextMatch {
        let profileID: UUID
        let ruleID: UUID
        let priority: Int
        let profileIndex: Int
        let ruleIndex: Int

        static func precedes(_ left: ContextMatch, _ right: ContextMatch) -> Bool {
            if left.priority != right.priority { return left.priority > right.priority }
            if left.profileIndex != right.profileIndex {
                return left.profileIndex < right.profileIndex
            }
            if left.ruleIndex != right.ruleIndex { return left.ruleIndex < right.ruleIndex }
            if left.profileID != right.profileID {
                return left.profileID.uuidString < right.profileID.uuidString
            }
            return left.ruleID.uuidString < right.ruleID.uuidString
        }
    }

    private static func normalizedBundleIdentifier(_ value: String?) -> String? {
        guard let value else { return nil }
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return normalized.isEmpty ? nil : normalized
    }
}
