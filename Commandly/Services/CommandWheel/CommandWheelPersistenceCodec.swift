import AppCore
import CommandKit
import Foundation

/// Versioned JSON encoding, legacy migration, and import merging shared by repositories.
nonisolated enum CommandWheelPersistenceCodec {
    struct DecodedStorage {
        let configuration: CommandWheelConfiguration
        let requiresRewrite: Bool
    }

    private struct VersionProbe: Decodable {
        let schemaVersion: Int
    }

    private struct StorageEnvelope: Codable {
        let schemaVersion: Int
        let configuration: CommandWheelConfiguration
    }

    private struct TransferDocument: Codable {
        let schemaVersion: Int
        let profiles: [CommandWheelProfile]
    }

    private struct LegacyEnvelopeV0: Decodable {
        let schemaVersion: Int
        let isEnabled: Bool
        let defaultProfileID: UUID?
        let profiles: [LegacyProfileV0]

        private enum CodingKeys: String, CodingKey {
            case schemaVersion
            case isEnabled
            case defaultProfileID
            case profiles
        }

        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
            isEnabled = try container.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? false
            defaultProfileID = try container.decodeIfPresent(
                UUID.self,
                forKey: .defaultProfileID
            )
            profiles = try container.decode([LegacyProfileV0].self, forKey: .profiles)
        }
    }

    private struct LegacyTransferDocumentV0: Decodable {
        let schemaVersion: Int
        let profiles: [LegacyProfileV0]
    }

    private struct LegacyProfileV0: Decodable {
        let id: UUID
        let name: String
        let shortcut: LauncherHotKey?
        let rootPageID: UUID
        let pages: [CommandWheelPage]
    }

    static func encodeStorage(_ configuration: CommandWheelConfiguration) throws -> Data {
        do {
            return try makeEncoder().encode(
                StorageEnvelope(
                    schemaVersion: CommandWheelSchema.currentVersion,
                    configuration: configuration
                )
            )
        } catch {
            throw CommandWheelRepositoryError.writeFailed
        }
    }

    static func decodeStorage(
        _ data: Data,
        validator: CommandWheelConfigurationValidator
    ) throws -> DecodedStorage {
        let version: Int
        do {
            version = try JSONDecoder().decode(VersionProbe.self, from: data).schemaVersion
        } catch {
            throw CommandWheelRepositoryError.corruptStorage
        }

        let configuration: CommandWheelConfiguration
        let migrated: Bool
        do {
            switch version {
            case CommandWheelSchema.currentVersion:
                configuration = try JSONDecoder()
                    .decode(StorageEnvelope.self, from: data)
                    .configuration
                migrated = false
            case CommandWheelSchema.legacyVersion:
                configuration = migrate(
                    try JSONDecoder().decode(LegacyEnvelopeV0.self, from: data)
                )
                migrated = true
            default:
                throw CommandWheelRepositoryError.unsupportedSchemaVersion(version)
            }
        } catch let error as CommandWheelRepositoryError {
            throw error
        } catch {
            throw CommandWheelRepositoryError.corruptStorage
        }

        let normalized = CommandWheelRepositorySupport.recreateRequiredDefault(
            in: configuration
        )
        do {
            try validator.validate(normalized)
        } catch let error as CommandWheelValidationError {
            throw CommandWheelRepositoryError.validationFailed(error)
        }
        return DecodedStorage(
            configuration: normalized,
            requiresRewrite: migrated || normalized != configuration
        )
    }

    static func exportProfiles(
        from configuration: CommandWheelConfiguration,
        ids: Set<UUID>?,
        validator: CommandWheelConfigurationValidator
    ) throws -> Data {
        let selected = configuration.profiles.filter { profile in
            ids?.contains(profile.id) ?? true
        }
        guard selected.isEmpty == false else {
            throw CommandWheelRepositoryError.noProfilesSelectedForExport
        }
        try validateImportedProfiles(selected, validator: validator, isImport: false)
        do {
            return try makeEncoder().encode(
                TransferDocument(
                    schemaVersion: CommandWheelSchema.currentVersion,
                    profiles: selected
                )
            )
        } catch {
            throw CommandWheelRepositoryError.writeFailed
        }
    }

    static func decodeImport(
        _ data: Data,
        validator: CommandWheelConfigurationValidator
    ) throws -> [CommandWheelProfile] {
        let version: Int
        do {
            version = try JSONDecoder().decode(VersionProbe.self, from: data).schemaVersion
        } catch {
            throw CommandWheelRepositoryError.malformedImport
        }

        let profiles: [CommandWheelProfile]
        do {
            switch version {
            case CommandWheelSchema.currentVersion:
                profiles = try JSONDecoder()
                    .decode(TransferDocument.self, from: data)
                    .profiles
            case CommandWheelSchema.legacyVersion:
                profiles = try JSONDecoder()
                    .decode(LegacyTransferDocumentV0.self, from: data)
                    .profiles
                    .map(migrate)
            default:
                throw CommandWheelRepositoryError.unsupportedImportVersion(version)
            }
        } catch let error as CommandWheelRepositoryError {
            throw error
        } catch {
            throw CommandWheelRepositoryError.malformedImport
        }
        try validateImportedProfiles(profiles, validator: validator, isImport: true)
        return profiles
    }

    private static func validateImportedProfiles(
        _ profiles: [CommandWheelProfile],
        validator: CommandWheelConfigurationValidator,
        isImport: Bool
    ) throws {
        guard profiles.isEmpty == false else {
            let error = CommandWheelValidationError.noProfiles
            if isImport {
                throw CommandWheelRepositoryError.importValidationFailed(error)
            }
            throw CommandWheelRepositoryError.validationFailed(error)
        }
        var validationProfiles = profiles
        validationProfiles[0].isEnabled = true
        let temporary = CommandWheelConfiguration(
            isEnabled: false,
            contextAwareProfileSelectionEnabled: true,
            defaultProfileID: validationProfiles[0].id,
            profiles: validationProfiles
        )
        do {
            try validator.validate(temporary)
        } catch let error as CommandWheelValidationError {
            if isImport {
                throw CommandWheelRepositoryError.importValidationFailed(error)
            }
            throw CommandWheelRepositoryError.validationFailed(error)
        }
    }

    private static func migrate(_ envelope: LegacyEnvelopeV0) -> CommandWheelConfiguration {
        let profiles = envelope.profiles.map(migrate)
        let requestedDefault = envelope.defaultProfileID.flatMap { candidate in
            profiles.contains(where: { $0.id == candidate }) ? candidate : nil
        }
        return CommandWheelConfiguration(
            isEnabled: envelope.isEnabled,
            contextAwareProfileSelectionEnabled: false,
            defaultProfileID: requestedDefault ?? profiles.first?.id
                ?? CommandWheelDefaults.configuration.defaultProfileID,
            profiles: profiles
        )
    }

    private static func migrate(_ profile: LegacyProfileV0) -> CommandWheelProfile {
        CommandWheelProfile(
            id: profile.id,
            name: profile.name,
            isEnabled: true,
            shortcut: profile.shortcut,
            activationBehavior: .holdAndRelease,
            placement: .cursor,
            rootPageID: profile.rootPageID,
            pages: profile.pages,
            contextRules: [],
            appearance: CommandWheelDefaults.appearance,
            interaction: CommandWheelDefaults.interaction,
            hidesUnavailableSegments: false
        )
    }

    private static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return encoder
    }
}

nonisolated enum CommandWheelRepositorySupport {
    struct ImportMerge {
        let configuration: CommandWheelConfiguration
        let result: CommandWheelImportResult
    }

    static func recreateRequiredDefault(
        in configuration: CommandWheelConfiguration
    ) -> CommandWheelConfiguration {
        var normalized = configuration
        guard normalized.profiles.isEmpty == false else {
            var defaults = CommandWheelDefaults.configuration
            defaults.schemaVersion = configuration.schemaVersion
            defaults.isEnabled = configuration.isEnabled
            defaults.contextAwareProfileSelectionEnabled =
                configuration.contextAwareProfileSelectionEnabled
            return defaults
        }

        if let defaultIndex = normalized.profiles.firstIndex(where: {
            $0.id == normalized.defaultProfileID
        }) {
            if normalized.profiles[defaultIndex].isEnabled == false {
                if let enabled = normalized.profiles.first(where: \.isEnabled) {
                    normalized.defaultProfileID = enabled.id
                } else {
                    normalized.profiles[defaultIndex].isEnabled = true
                }
            }
            return normalized
        }

        if let enabled = normalized.profiles.first(where: \.isEnabled) {
            normalized.defaultProfileID = enabled.id
        } else {
            normalized.profiles[0].isEnabled = true
            normalized.defaultProfileID = normalized.profiles[0].id
        }
        return normalized
    }

    static func mergeImportedProfiles(
        _ importedProfiles: [CommandWheelProfile],
        into current: CommandWheelConfiguration,
        knownCommandIDs: Set<CommandID>?,
        uuidProvider: any UUIDProviding,
        validator: CommandWheelConfigurationValidator
    ) throws -> ImportMerge {
        var merged = current
        var usedProfileIDs = Set(current.profiles.map(\.id))
        var usedPageIDs = Set(current.profiles.flatMap(\.pages).map(\.id))
        var usedSegmentIDs = Set(
            current.profiles.flatMap(\.pages).flatMap(\.segments).map(\.id)
        )
        var usedRuleIDs = Set(current.profiles.flatMap(\.contextRules).map(\.id))

        var profileMap: [UUID: UUID] = [:]
        var pageMap: [UUID: UUID] = [:]
        var segmentMap: [UUID: UUID] = [:]
        var ruleMap: [UUID: UUID] = [:]
        var importedIDs: [UUID] = []

        for profile in importedProfiles {
            let profileID = try remappedID(
                profile.id,
                used: &usedProfileIDs,
                mapping: &profileMap,
                uuidProvider: uuidProvider
            )
            var localPageMap: [UUID: UUID] = [:]
            for page in profile.pages {
                localPageMap[page.id] = try remappedID(
                    page.id,
                    used: &usedPageIDs,
                    mapping: &pageMap,
                    uuidProvider: uuidProvider
                )
            }

            let pages = try profile.pages.map { page in
                let remappedSegments = try page.segments.map { segment in
                    let segmentID = try remappedID(
                        segment.id,
                        used: &usedSegmentIDs,
                        mapping: &segmentMap,
                        uuidProvider: uuidProvider
                    )
                    let content: CommandWheelSegmentContent
                    switch segment.content {
                    case .submenu(let pageID):
                        guard let remappedPageID = localPageMap[pageID] else {
                            throw CommandWheelRepositoryError.importValidationFailed(
                                .missingSubmenuPage(segmentID: segment.id)
                            )
                        }
                        content = .submenu(pageID: remappedPageID)
                    default:
                        content = segment.content
                    }
                    return CommandWheelSegment(
                        id: segmentID,
                        slotIndex: segment.slotIndex,
                        content: content,
                        customLabel: segment.customLabel,
                        customIcon: segment.customIcon
                    )
                }
                guard let pageID = localPageMap[page.id] else {
                    throw CommandWheelRepositoryError.identifierGenerationFailed
                }
                return CommandWheelPage(
                    id: pageID,
                    name: page.name,
                    segments: remappedSegments
                )
            }

            let rules = try profile.contextRules.map { rule in
                CommandWheelContextRule(
                    id: try remappedID(
                        rule.id,
                        used: &usedRuleIDs,
                        mapping: &ruleMap,
                        uuidProvider: uuidProvider
                    ),
                    frontmostApplicationBundleIdentifier:
                        rule.frontmostApplicationBundleIdentifier,
                    priority: rule.priority,
                    isEnabled: rule.isEnabled
                )
            }
            guard let rootPageID = localPageMap[profile.rootPageID] else {
                throw CommandWheelRepositoryError.importValidationFailed(
                    .missingRootPage(profile.id)
                )
            }

            merged.profiles.append(
                CommandWheelProfile(
                    id: profileID,
                    name: profile.name,
                    isEnabled: profile.isEnabled,
                    shortcut: profile.shortcut,
                    activationBehavior: profile.activationBehavior,
                    placement: profile.placement,
                    rootPageID: rootPageID,
                    pages: pages,
                    contextRules: rules,
                    appearance: profile.appearance,
                    interaction: profile.interaction,
                    hidesUnavailableSegments: profile.hidesUnavailableSegments
                )
            )
            importedIDs.append(profileID)
        }

        do {
            try validator.validate(merged)
        } catch let error as CommandWheelValidationError {
            throw CommandWheelRepositoryError.importValidationFailed(error)
        }

        let references = referencedCommandIDs(in: importedProfiles)
        let missing = knownCommandIDs.map { references.subtracting($0) } ?? []
        return ImportMerge(
            configuration: merged,
            result: CommandWheelImportResult(
                importedProfileIDs: importedIDs,
                profileIDRemapping: profileMap,
                pageIDRemapping: pageMap,
                segmentIDRemapping: segmentMap,
                contextRuleIDRemapping: ruleMap,
                referencedCommandIDs: references,
                missingCommandIDs: missing
            )
        )
    }

    private static func remappedID(
        _ original: UUID,
        used: inout Set<UUID>,
        mapping: inout [UUID: UUID],
        uuidProvider: any UUIDProviding
    ) throws -> UUID {
        guard used.contains(original) else {
            used.insert(original)
            return original
        }
        for _ in 0 ..< 256 {
            let candidate = uuidProvider.uuid()
            if used.insert(candidate).inserted {
                mapping[original] = candidate
                return candidate
            }
        }
        throw CommandWheelRepositoryError.identifierGenerationFailed
    }

    private static func referencedCommandIDs(
        in profiles: [CommandWheelProfile]
    ) -> Set<CommandID> {
        Set(profiles.flatMap(\.pages).flatMap(\.segments).compactMap { segment in
            guard case .command(let reference) = segment.content else { return nil }
            return reference.commandID
        })
    }
}
