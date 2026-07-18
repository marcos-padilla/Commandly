import AppCore
import CommandKit
import Foundation

/// Actor-confined, atomic, versioned JSON storage in Commandly's Application Support folder.
///
/// The payload contains non-secret command identifiers and user-selected layout preferences.
/// Command arguments must remain subject to the shared command engine's persistence policy and
/// must never contain credentials or private runtime results.
actor JSONCommandWheelProfileRepository: CommandWheelProfileRepository {
    private let explicitFileURL: URL?
    private let validator: CommandWheelConfigurationValidator
    private let uuidProvider: any UUIDProviding
    private var cachedConfiguration: CommandWheelConfiguration?

    init(
        fileURL: URL? = nil,
        validator: CommandWheelConfigurationValidator = CommandWheelConfigurationValidator(),
        uuidProvider: any UUIDProviding = SystemUUIDProvider()
    ) {
        self.explicitFileURL = fileURL
        self.validator = validator
        self.uuidProvider = uuidProvider
    }

    func load() throws -> CommandWheelConfiguration {
        if let cachedConfiguration { return cachedConfiguration }
        let fileURL = try resolvedFileURL()
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            let defaults = CommandWheelDefaults.configuration
            try validateForStorage(defaults)
            try persist(defaults, to: fileURL)
            cachedConfiguration = defaults
            return defaults
        }

        let data: Data
        do {
            data = try Data(contentsOf: fileURL, options: [.mappedIfSafe])
        } catch {
            throw CommandWheelRepositoryError.readFailed
        }
        let decoded = try CommandWheelPersistenceCodec.decodeStorage(
            data,
            validator: validator
        )
        if decoded.requiresRewrite {
            try persist(decoded.configuration, to: fileURL)
        }
        cachedConfiguration = decoded.configuration
        return decoded.configuration
    }

    func save(_ configuration: CommandWheelConfiguration) throws {
        let normalized = CommandWheelRepositorySupport.recreateRequiredDefault(
            in: configuration
        )
        try validateForStorage(normalized)
        let fileURL = try resolvedFileURL()
        try persist(normalized, to: fileURL)
        cachedConfiguration = normalized
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
        let fileURL = try resolvedFileURL()
        try persist(merge.configuration, to: fileURL)
        cachedConfiguration = merge.configuration
        return merge.result
    }

    private func validateForStorage(_ value: CommandWheelConfiguration) throws {
        do {
            try validator.validate(value)
        } catch let error as CommandWheelValidationError {
            throw CommandWheelRepositoryError.validationFailed(error)
        }
    }

    private func persist(_ value: CommandWheelConfiguration, to fileURL: URL) throws {
        let data = try CommandWheelPersistenceCodec.encodeStorage(value)
        do {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try data.write(to: fileURL, options: [.atomic])
        } catch {
            throw CommandWheelRepositoryError.writeFailed
        }
    }

    private func resolvedFileURL() throws -> URL {
        if let explicitFileURL { return explicitFileURL }
        guard let applicationSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first else {
            throw CommandWheelRepositoryError.applicationSupportUnavailable
        }
        return applicationSupport
            .appendingPathComponent("Commandly", isDirectory: true)
            .appendingPathComponent("CommandWheel.json", isDirectory: false)
    }
}
