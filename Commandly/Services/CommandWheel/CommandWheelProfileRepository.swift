import AppCore
import CommandKit
import Foundation

/// Persistence boundary for the complete Command Wheel configuration and profile transfers.
nonisolated protocol CommandWheelProfileRepository: Sendable {
    func load() async throws -> CommandWheelConfiguration
    func save(_ configuration: CommandWheelConfiguration) async throws
    func exportProfiles(ids: Set<UUID>?) async throws -> Data
    func importProfiles(
        from data: Data,
        knownCommandIDs: Set<CommandID>?
    ) async throws -> CommandWheelImportResult
}

extension CommandWheelProfileRepository {
    func exportProfiles() async throws -> Data {
        try await exportProfiles(ids: nil)
    }

    func importProfiles(from data: Data) async throws -> CommandWheelImportResult {
        try await importProfiles(from: data, knownCommandIDs: nil)
    }
}

/// IDs changed while safely merging imported profiles into existing configuration.
nonisolated struct CommandWheelImportResult: Equatable, Sendable {
    let importedProfileIDs: [UUID]
    let profileIDRemapping: [UUID: UUID]
    let pageIDRemapping: [UUID: UUID]
    let segmentIDRemapping: [UUID: UUID]
    let contextRuleIDRemapping: [UUID: UUID]
    let referencedCommandIDs: Set<CommandID>
    let missingCommandIDs: Set<CommandID>
}

/// Sanitized failures from durable storage and profile transfer operations.
nonisolated enum CommandWheelRepositoryError: Error, Equatable, Sendable {
    case applicationSupportUnavailable
    case readFailed
    case writeFailed
    case corruptStorage
    case unsupportedSchemaVersion(Int)
    case validationFailed(CommandWheelValidationError)
    case malformedImport
    case unsupportedImportVersion(Int)
    case importValidationFailed(CommandWheelValidationError)
    case noProfilesSelectedForExport
    case identifierGenerationFailed
}

extension CommandWheelRepositoryError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .applicationSupportUnavailable:
            return "Command Wheel storage is unavailable."
        case .readFailed:
            return "Command Wheel settings could not be read."
        case .writeFailed:
            return "Command Wheel settings could not be saved."
        case .corruptStorage:
            return "Command Wheel settings are damaged and were not overwritten."
        case .unsupportedSchemaVersion:
            return "Command Wheel settings were created by an unsupported version."
        case .validationFailed(let error):
            return error.errorDescription
        case .malformedImport:
            return "The selected Command Wheel profile file is not valid JSON."
        case .unsupportedImportVersion:
            return "The selected Command Wheel profile file uses an unsupported version."
        case .importValidationFailed(let error):
            return error.errorDescription
        case .noProfilesSelectedForExport:
            return "Choose at least one wheel profile to export."
        case .identifierGenerationFailed:
            return "Command Wheel could not generate unique imported identifiers."
        }
    }
}

/// Deterministic actor-backed repository for tests and previews.
actor InMemoryCommandWheelProfileRepository: CommandWheelProfileRepository {
    private var configuration: CommandWheelConfiguration?
    private let validator: CommandWheelConfigurationValidator
    private let uuidProvider: any UUIDProviding

    init(
        configuration: CommandWheelConfiguration? = nil,
        validator: CommandWheelConfigurationValidator = CommandWheelConfigurationValidator(),
        uuidProvider: any UUIDProviding = SystemUUIDProvider()
    ) {
        self.configuration = configuration
        self.validator = validator
        self.uuidProvider = uuidProvider
    }

    func load() throws -> CommandWheelConfiguration {
        if let configuration {
            let normalized = CommandWheelRepositorySupport.recreateRequiredDefault(
                in: configuration
            )
            try validateForStorage(normalized)
            self.configuration = normalized
            return normalized
        }
        let defaults = CommandWheelDefaults.configuration
        try validateForStorage(defaults)
        configuration = defaults
        return defaults
    }

    func save(_ configuration: CommandWheelConfiguration) throws {
        let normalized = CommandWheelRepositorySupport.recreateRequiredDefault(
            in: configuration
        )
        try validateForStorage(normalized)
        self.configuration = normalized
    }

    func exportProfiles(ids: Set<UUID>?) throws -> Data {
        let configuration = try load()
        return try CommandWheelPersistenceCodec.exportProfiles(
            from: configuration,
            ids: ids,
            validator: validator
        )
    }

    func importProfiles(
        from data: Data,
        knownCommandIDs: Set<CommandID>?
    ) throws -> CommandWheelImportResult {
        let current = try load()
        let imported = try CommandWheelPersistenceCodec.decodeImport(
            data,
            validator: validator
        )
        let merge = try CommandWheelRepositorySupport.mergeImportedProfiles(
            imported,
            into: current,
            knownCommandIDs: knownCommandIDs,
            uuidProvider: uuidProvider,
            validator: validator
        )
        configuration = merge.configuration
        return merge.result
    }

    func snapshot() -> CommandWheelConfiguration? {
        configuration
    }

    private func validateForStorage(_ value: CommandWheelConfiguration) throws {
        do {
            try validator.validate(value)
        } catch let error as CommandWheelValidationError {
            throw CommandWheelRepositoryError.validationFailed(error)
        }
    }
}
