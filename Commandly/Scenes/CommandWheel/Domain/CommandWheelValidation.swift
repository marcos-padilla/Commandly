import AppKit
import CommandKit
import Foundation

/// Native SF Symbol validation and deterministic fallback used by persistence, Settings, and the
/// icon-only runtime surface. Invalid imported values never become blank segment tiles.
nonisolated enum CommandWheelSystemSymbol {
    static let guaranteedFallback = "questionmark"

    static func isValid(_ candidate: String) -> Bool {
        let normalized = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalized.isEmpty == false else { return false }
        return NSImage(
            systemSymbolName: normalized,
            accessibilityDescription: nil
        ) != nil
    }

    static func resolvedName(_ preferred: String?, fallback: String) -> String {
        if let preferred {
            let normalized = preferred.trimmingCharacters(in: .whitespacesAndNewlines)
            if isValid(normalized) { return normalized }
        }
        let normalizedFallback = fallback.trimmingCharacters(in: .whitespacesAndNewlines)
        return isValid(normalizedFallback) ? normalizedFallback : guaranteedFallback
    }
}

nonisolated enum CommandWheelLimits {
    static let maximumProfiles = 64
    static let maximumPagesPerProfile = 64
    static let maximumVisibleSlots = 12
    static let maximumNameLength = 80
    static let minimumWheelRadius = 80.0
    static let maximumWheelRadius = 400.0
    static let maximumContextPriorityMagnitude = 10_000
}

/// Sanitized structural failures for saved or imported Command Wheel configuration.
nonisolated enum CommandWheelValidationError: Error, Equatable, Sendable {
    case unsupportedSchemaVersion(Int)
    case noProfiles
    case tooManyProfiles
    case duplicateProfileID(UUID)
    case missingDefaultProfile
    case disabledDefaultProfile
    case emptyProfileName(UUID)
    case profileNameTooLong(UUID)
    case invalidShortcut(UUID)
    case noPages(UUID)
    case tooManyPages(UUID)
    case duplicatePageID(UUID)
    case missingRootPage(UUID)
    case emptyPageName(UUID)
    case pageNameTooLong(UUID)
    case tooManySegments(UUID)
    case duplicateSegmentID(UUID)
    case duplicateSlot(pageID: UUID, slotIndex: Int)
    case invalidSlot(pageID: UUID, slotIndex: Int)
    case invalidCustomLabel(UUID)
    case invalidCustomIcon(UUID)
    case invalidCommandReference(UUID)
    case missingSubmenuPage(segmentID: UUID)
    case rootPageHasParent(UUID)
    case multipleSubmenuParents(UUID)
    case submenuCycle(UUID)
    case unreachablePage(UUID)
    case unsupportedDynamicProvider(UUID)
    case invalidDynamicProviderConfiguration(UUID)
    case invalidPlacement(UUID)
    case invalidAppearance(UUID)
    case invalidInteraction(UUID)
    case duplicateContextRuleID(UUID)
    case invalidContextRule(UUID)
    case conflictingContextRules(priority: Int)
}

extension CommandWheelValidationError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .unsupportedSchemaVersion:
            return "This Command Wheel configuration uses an unsupported version."
        case .noProfiles:
            return "Command Wheel needs at least one profile."
        case .tooManyProfiles:
            return "The configuration contains too many wheel profiles."
        case .duplicateProfileID, .duplicatePageID, .duplicateSegmentID,
             .duplicateContextRuleID:
            return "The configuration contains duplicate identifiers."
        case .missingDefaultProfile:
            return "The default wheel profile is missing."
        case .disabledDefaultProfile:
            return "The default wheel profile must be enabled."
        case .emptyProfileName, .emptyPageName:
            return "Wheel profile and page names cannot be empty."
        case .profileNameTooLong, .pageNameTooLong:
            return "A wheel profile or page name is too long."
        case .invalidShortcut:
            return "A wheel shortcut is invalid."
        case .noPages, .missingRootPage:
            return "A wheel profile does not contain a valid root page."
        case .tooManyPages:
            return "A wheel profile contains too many pages."
        case .tooManySegments, .duplicateSlot, .invalidSlot:
            return "A wheel page contains an invalid slot layout."
        case .invalidCustomLabel, .invalidCustomIcon:
            return "A wheel segment contains an invalid label or icon override."
        case .invalidCommandReference:
            return "A wheel segment contains an invalid command reference."
        case .missingSubmenuPage, .rootPageHasParent, .multipleSubmenuParents,
             .submenuCycle, .unreachablePage:
            return "The wheel submenu structure is invalid."
        case .unsupportedDynamicProvider, .invalidDynamicProviderConfiguration:
            return "A wheel segment uses an unsupported dynamic provider configuration."
        case .invalidPlacement:
            return "A wheel placement is invalid."
        case .invalidAppearance:
            return "A wheel appearance setting is outside the supported range."
        case .invalidInteraction:
            return "A wheel interaction setting is outside the supported range."
        case .invalidContextRule, .conflictingContextRules:
            return "The wheel application-context rules are invalid or conflicting."
        }
    }
}

/// Validates the complete persisted graph before it reaches runtime presentation code.
nonisolated struct CommandWheelConfigurationValidator: Sendable {
    let supportedDynamicProviderIDs: Set<String>

    init(
        supportedDynamicProviderIDs: Set<String> = CommandWheelDynamicProviderID.supported
    ) {
        self.supportedDynamicProviderIDs = supportedDynamicProviderIDs
    }

    func validate(_ configuration: CommandWheelConfiguration) throws {
        guard configuration.schemaVersion == CommandWheelSchema.currentVersion else {
            throw CommandWheelValidationError.unsupportedSchemaVersion(
                configuration.schemaVersion
            )
        }
        guard configuration.profiles.isEmpty == false else {
            throw CommandWheelValidationError.noProfiles
        }
        guard configuration.profiles.count <= CommandWheelLimits.maximumProfiles else {
            throw CommandWheelValidationError.tooManyProfiles
        }

        var profileIDs: Set<UUID> = []
        var pageIDs: Set<UUID> = []
        var segmentIDs: Set<UUID> = []
        var contextRuleIDs: Set<UUID> = []
        var contextOwners: [ContextRuleKey: UUID] = [:]

        for profile in configuration.profiles {
            guard profileIDs.insert(profile.id).inserted else {
                throw CommandWheelValidationError.duplicateProfileID(profile.id)
            }
            try validateName(
                profile.name,
                emptyError: .emptyProfileName(profile.id),
                tooLongError: .profileNameTooLong(profile.id)
            )
            if let shortcut = profile.shortcut, shortcut.isValid == false {
                throw CommandWheelValidationError.invalidShortcut(profile.id)
            }
            try validate(profile.placement, profileID: profile.id)
            try validate(profile.appearance, profileID: profile.id)
            try validate(profile.interaction, profileID: profile.id)

            guard profile.pages.isEmpty == false else {
                throw CommandWheelValidationError.noPages(profile.id)
            }
            guard profile.pages.count <= CommandWheelLimits.maximumPagesPerProfile else {
                throw CommandWheelValidationError.tooManyPages(profile.id)
            }

            var localPageIDs: Set<UUID> = []
            for page in profile.pages {
                guard localPageIDs.insert(page.id).inserted,
                      pageIDs.insert(page.id).inserted else {
                    throw CommandWheelValidationError.duplicatePageID(page.id)
                }
                try validateName(
                    page.name,
                    emptyError: .emptyPageName(page.id),
                    tooLongError: .pageNameTooLong(page.id)
                )
                guard page.segments.count <= profile.interaction.visibleSlotCount else {
                    throw CommandWheelValidationError.tooManySegments(page.id)
                }

                var slots: Set<Int> = []
                for segment in page.segments {
                    guard segmentIDs.insert(segment.id).inserted else {
                        throw CommandWheelValidationError.duplicateSegmentID(segment.id)
                    }
                    guard segment.slotIndex >= 0,
                          segment.slotIndex < profile.interaction.visibleSlotCount else {
                        throw CommandWheelValidationError.invalidSlot(
                            pageID: page.id,
                            slotIndex: segment.slotIndex
                        )
                    }
                    guard slots.insert(segment.slotIndex).inserted else {
                        throw CommandWheelValidationError.duplicateSlot(
                            pageID: page.id,
                            slotIndex: segment.slotIndex
                        )
                    }
                    try validateSegmentPresentation(segment)
                    try validateCommandContent(segment)
                    try validateDynamicContent(
                        segment,
                        visibleSlotCount: profile.interaction.visibleSlotCount
                    )
                }
            }

            guard localPageIDs.contains(profile.rootPageID) else {
                throw CommandWheelValidationError.missingRootPage(profile.id)
            }
            try validateSubmenuGraph(profile, pageIDs: localPageIDs)

            for rule in profile.contextRules {
                guard contextRuleIDs.insert(rule.id).inserted else {
                    throw CommandWheelValidationError.duplicateContextRuleID(rule.id)
                }
                guard isValidBundleIdentifier(rule.frontmostApplicationBundleIdentifier),
                      rule.priority >= -CommandWheelLimits.maximumContextPriorityMagnitude,
                      rule.priority <= CommandWheelLimits.maximumContextPriorityMagnitude else {
                    throw CommandWheelValidationError.invalidContextRule(rule.id)
                }
                guard rule.isEnabled else { continue }
                let key = ContextRuleKey(
                    bundleIdentifier: rule.frontmostApplicationBundleIdentifier
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                        .lowercased(),
                    priority: rule.priority
                )
                if contextOwners[key] != nil {
                    throw CommandWheelValidationError.conflictingContextRules(
                        priority: rule.priority
                    )
                }
                contextOwners[key] = profile.id
            }
        }

        guard let defaultProfile = configuration.profiles.first(where: {
            $0.id == configuration.defaultProfileID
        }) else {
            throw CommandWheelValidationError.missingDefaultProfile
        }
        guard defaultProfile.isEnabled else {
            throw CommandWheelValidationError.disabledDefaultProfile
        }
    }

    private func validateName(
        _ value: String,
        emptyError: CommandWheelValidationError,
        tooLongError: CommandWheelValidationError
    ) throws {
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalized.isEmpty == false else { throw emptyError }
        guard normalized.count <= CommandWheelLimits.maximumNameLength else {
            throw tooLongError
        }
    }

    private func validate(
        _ placement: CommandWheelPlacement,
        profileID: UUID
    ) throws {
        guard case .fixedNormalizedPoint(let screenIdentifier, let x, let y) = placement else {
            return
        }
        guard x.isFinite, y.isFinite, (0 ... 1).contains(x), (0 ... 1).contains(y) else {
            throw CommandWheelValidationError.invalidPlacement(profileID)
        }
        if let screenIdentifier,
           screenIdentifier.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw CommandWheelValidationError.invalidPlacement(profileID)
        }
    }

    private func validate(
        _ appearance: CommandWheelAppearanceConfiguration,
        profileID: UUID
    ) throws {
        guard appearance.wheelRadius.isFinite,
              appearance.startAngleDegrees.isFinite,
              (CommandWheelLimits.minimumWheelRadius ... CommandWheelLimits.maximumWheelRadius)
              .contains(appearance.wheelRadius),
              (-360.0 ... 360.0).contains(appearance.startAngleDegrees) else {
            throw CommandWheelValidationError.invalidAppearance(profileID)
        }
    }

    private func validate(
        _ interaction: CommandWheelInteractionConfiguration,
        profileID: UUID
    ) throws {
        let values = [
            interaction.deadZoneRadius,
            interaction.selectionRadius,
            interaction.submenuActivationRadius,
            interaction.submenuDwellDurationSeconds,
            interaction.selectionHysteresisDegrees,
            interaction.minimumSelectionMovement,
        ]
        guard values.allSatisfy(\.isFinite),
              (1 ... CommandWheelLimits.maximumVisibleSlots)
              .contains(interaction.visibleSlotCount),
              interaction.deadZoneRadius >= 0,
              interaction.selectionRadius > interaction.deadZoneRadius,
              interaction.submenuActivationRadius >= interaction.selectionRadius,
              interaction.submenuActivationRadius <= CommandWheelLimits.maximumWheelRadius * 2,
              (0 ... 5).contains(interaction.submenuDwellDurationSeconds),
              (0 ... 30).contains(interaction.selectionHysteresisDegrees),
              (0 ... 64).contains(interaction.minimumSelectionMovement) else {
            throw CommandWheelValidationError.invalidInteraction(profileID)
        }
        if interaction.submenuActivationBehavior == .dwell,
           interaction.submenuDwellDurationSeconds == 0 {
            throw CommandWheelValidationError.invalidInteraction(profileID)
        }
        if interaction.submenuActivationBehavior == .clickOnly,
           interaction.allowsClickSelection == false {
            throw CommandWheelValidationError.invalidInteraction(profileID)
        }
    }

    private func validateSegmentPresentation(_ segment: CommandWheelSegment) throws {
        if let customLabel = segment.customLabel {
            let normalized = customLabel.trimmingCharacters(in: .whitespacesAndNewlines)
            guard normalized.isEmpty == false,
                  normalized.count <= CommandWheelLimits.maximumNameLength else {
                throw CommandWheelValidationError.invalidCustomLabel(segment.id)
            }
        }
        if let customIcon = segment.customIcon {
            let normalized = customIcon.systemSymbolName
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard normalized.isEmpty == false,
                  normalized.count <= CommandWheelLimits.maximumNameLength,
                  CommandWheelSystemSymbol.isValid(normalized) else {
                throw CommandWheelValidationError.invalidCustomIcon(segment.id)
            }
        }
    }

    private func validateDynamicContent(
        _ segment: CommandWheelSegment,
        visibleSlotCount: Int
    ) throws {
        guard case .dynamicProvider(let reference) = segment.content else { return }
        guard supportedDynamicProviderIDs.contains(reference.providerID) else {
            throw CommandWheelValidationError.unsupportedDynamicProvider(segment.id)
        }
        guard reference.maximumResultCount > 0,
              reference.maximumResultCount <= visibleSlotCount else {
            throw CommandWheelValidationError.invalidDynamicProviderConfiguration(segment.id)
        }
        guard CommandWheelDynamicProviderRefreshStrategy.supported.contains(
            reference.refreshStrategy
        ), CommandWheelDynamicProviderCachePolicy.supported.contains(reference.cachePolicy) else {
            throw CommandWheelValidationError.invalidDynamicProviderConfiguration(segment.id)
        }
        switch (reference.providerID, reference.sortingMethod) {
        case (_, .providerDefault), (_, .alphabetical),
             (CommandWheelDynamicProviderID.recentCommands, .mostRecent),
             (CommandWheelDynamicProviderID.frequentCommands, .mostFrequent):
            break
        default:
            throw CommandWheelValidationError.invalidDynamicProviderConfiguration(segment.id)
        }
    }

    private func validateCommandContent(_ segment: CommandWheelSegment) throws {
        guard case .command(let reference) = segment.content else { return }
        let commandID = reference.commandID.rawValue
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard commandID.isEmpty == false,
              commandID.count <= 160,
              reference.arguments.values.keys.allSatisfy({ name in
                  let normalized = name.trimmingCharacters(in: .whitespacesAndNewlines)
                  return normalized.isEmpty == false
                      && normalized.count <= CommandWheelLimits.maximumNameLength
              }),
              reference.arguments.values.values.allSatisfy(isPersistableArgumentValue) else {
            throw CommandWheelValidationError.invalidCommandReference(segment.id)
        }
    }

    private func isPersistableArgumentValue(_ value: CommandArgumentValue) -> Bool {
        switch value {
        case .decimal(let value):
            return value.isFinite
        case .url(let value):
            return value.absoluteString.isEmpty == false
        case .string, .boolean, .integer, .stringList:
            return true
        }
    }

    private func validateSubmenuGraph(
        _ profile: CommandWheelProfile,
        pageIDs: Set<UUID>
    ) throws {
        var children: [UUID: [UUID]] = [:]
        var incomingCounts: [UUID: Int] = [:]

        for page in profile.pages {
            for segment in page.segments {
                guard case .submenu(let childID) = segment.content else { continue }
                guard pageIDs.contains(childID) else {
                    throw CommandWheelValidationError.missingSubmenuPage(
                        segmentID: segment.id
                    )
                }
                children[page.id, default: []].append(childID)
                incomingCounts[childID, default: 0] += 1
            }
        }

        var states: [UUID: VisitState] = [:]
        func visit(_ pageID: UUID) throws {
            if states[pageID] == .visiting {
                throw CommandWheelValidationError.submenuCycle(pageID)
            }
            guard states[pageID] != .visited else { return }
            states[pageID] = .visiting
            for childID in children[pageID, default: []] {
                try visit(childID)
            }
            states[pageID] = .visited
        }

        for pageID in pageIDs.sorted(by: { $0.uuidString < $1.uuidString }) {
            try visit(pageID)
        }

        if incomingCounts[profile.rootPageID, default: 0] > 0 {
            throw CommandWheelValidationError.rootPageHasParent(profile.rootPageID)
        }
        for pageID in pageIDs where pageID != profile.rootPageID {
            if incomingCounts[pageID, default: 0] > 1 {
                throw CommandWheelValidationError.multipleSubmenuParents(pageID)
            }
        }

        var reachable: Set<UUID> = []
        func collectReachable(_ pageID: UUID) {
            guard reachable.insert(pageID).inserted else { return }
            for childID in children[pageID, default: []] {
                collectReachable(childID)
            }
        }
        collectReachable(profile.rootPageID)
        if let unreachable = pageIDs
            .subtracting(reachable)
            .sorted(by: { $0.uuidString < $1.uuidString })
            .first {
            throw CommandWheelValidationError.unreachablePage(unreachable)
        }
    }

    private func isValidBundleIdentifier(_ value: String) -> Bool {
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let components = normalized.split(separator: ".", omittingEmptySubsequences: false)
        guard components.count >= 2 else { return false }
        let allowed = CharacterSet.alphanumerics.union(
            CharacterSet(charactersIn: "-")
        )
        return components.allSatisfy { component in
            component.isEmpty == false
                && component.unicodeScalars.allSatisfy(allowed.contains)
        }
    }

    private struct ContextRuleKey: Hashable {
        let bundleIdentifier: String
        let priority: Int
    }

    private enum VisitState {
        case visiting
        case visited
    }
}
