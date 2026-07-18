import AppCore
import CommandKit
import Foundation
import Testing
@testable import Commandly

@Suite("Command Wheel persistence")
struct CommandWheelPersistenceTests {
    @Test
    func inMemoryRepositoryCreatesAndRecreatesRequiredDefaults() async throws {
        let repository = InMemoryCommandWheelProfileRepository()

        #expect(try await repository.load() == CommandWheelDefaults.configuration)

        let empty = CommandWheelConfiguration(
            isEnabled: true,
            contextAwareProfileSelectionEnabled: true,
            defaultProfileID: persistenceTestID(1),
            profiles: []
        )
        try await repository.save(empty)
        let recreated = try await repository.load()

        #expect(recreated.isEnabled)
        #expect(recreated.contextAwareProfileSelectionEnabled)
        #expect(recreated.profiles == CommandWheelDefaults.configuration.profiles)
        #expect(recreated.defaultProfileID == CommandWheelDefaults.configuration.defaultProfileID)
    }

    @Test
    func jsonRepositoryCreatesFileAndRoundTripsConfiguration() async throws {
        let directory = temporaryPersistenceDirectory()
        let fileURL = directory.appendingPathComponent("CommandWheel.json")
        defer { try? FileManager.default.removeItem(at: directory) }

        let firstRepository = JSONCommandWheelProfileRepository(fileURL: fileURL)
        let defaults = try await firstRepository.load()
        #expect(defaults == CommandWheelDefaults.configuration)
        #expect(FileManager.default.fileExists(atPath: fileURL.path))

        var changed = defaults
        changed.isEnabled = true
        changed.profiles[0].name = "Focused Work"
        changed.profiles[0].activationBehavior = .toggle
        try await firstRepository.save(changed)

        let secondRepository = JSONCommandWheelProfileRepository(fileURL: fileURL)
        #expect(try await secondRepository.load() == changed)
    }

    @Test
    func legacyV0StorageMigratesAndRewritesCurrentEnvelope() async throws {
        let directory = temporaryPersistenceDirectory()
        let fileURL = directory.appendingPathComponent("CommandWheel.json")
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )

        let source = CommandWheelDefaults.defaultProfile
        let legacy = LegacyCommandWheelEnvelopeV0(
            schemaVersion: 0,
            isEnabled: true,
            defaultProfileID: source.id,
            profiles: [
                LegacyCommandWheelProfileV0(
                    id: source.id,
                    name: "Migrated",
                    shortcut: nil,
                    rootPageID: source.rootPageID,
                    pages: source.pages
                ),
            ]
        )
        try JSONEncoder().encode(legacy).write(to: fileURL)

        let repository = JSONCommandWheelProfileRepository(fileURL: fileURL)
        let migrated = try await repository.load()
        let profile = try #require(migrated.profiles.first)

        #expect(migrated.schemaVersion == CommandWheelSchema.currentVersion)
        #expect(migrated.isEnabled)
        #expect(migrated.contextAwareProfileSelectionEnabled == false)
        #expect(profile.name == "Migrated")
        #expect(profile.appearance == CommandWheelDefaults.appearance)
        #expect(profile.interaction == CommandWheelDefaults.interaction)
        #expect(profile.placement == .cursor)

        let rewritten = try JSONSerialization.jsonObject(
            with: Data(contentsOf: fileURL)
        ) as? [String: Any]
        #expect(rewritten?["schemaVersion"] as? Int == CommandWheelSchema.currentVersion)
        #expect(rewritten?["configuration"] != nil)
    }

    @Test
    func corruptStorageThrowsWithoutOverwritingOriginalBytes() async throws {
        let directory = temporaryPersistenceDirectory()
        let fileURL = directory.appendingPathComponent("CommandWheel.json")
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        let corrupt = Data("{\"schemaVersion\":1,\"configuration\":".utf8)
        try corrupt.write(to: fileURL)

        let repository = JSONCommandWheelProfileRepository(fileURL: fileURL)
        await #expect(throws: CommandWheelRepositoryError.corruptStorage) {
            try await repository.load()
        }
        #expect(try Data(contentsOf: fileURL) == corrupt)
    }

    @Test
    func unsupportedStorageVersionIsReportedWithoutTreatingItAsCorruption() async throws {
        let directory = temporaryPersistenceDirectory()
        let fileURL = directory.appendingPathComponent("CommandWheel.json")
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        try Data("{\"schemaVersion\":99}".utf8).write(to: fileURL)

        let repository = JSONCommandWheelProfileRepository(fileURL: fileURL)
        await #expect(throws: CommandWheelRepositoryError.unsupportedSchemaVersion(99)) {
            try await repository.load()
        }
    }

    @Test
    func unknownJSONFieldsAreIgnoredAtEveryEnvelopeLevel() async throws {
        let directory = temporaryPersistenceDirectory()
        let fileURL = directory.appendingPathComponent("CommandWheel.json")
        defer { try? FileManager.default.removeItem(at: directory) }

        let writer = JSONCommandWheelProfileRepository(fileURL: fileURL)
        let expected = try await writer.load()
        let original = try Data(contentsOf: fileURL)
        var root = try #require(
            JSONSerialization.jsonObject(with: original) as? [String: Any]
        )
        var configuration = try #require(root["configuration"] as? [String: Any])
        var profiles = try #require(configuration["profiles"] as? [[String: Any]])
        profiles[0]["futureProfileSetting"] = ["nested": true]
        configuration["profiles"] = profiles
        configuration["futureConfigurationSetting"] = 42
        root["configuration"] = configuration
        root["futureEnvelopeSetting"] = "ignored"
        try JSONSerialization.data(withJSONObject: root).write(to: fileURL)

        let reader = JSONCommandWheelProfileRepository(fileURL: fileURL)
        #expect(try await reader.load() == expected)
    }

    @Test
    func importRegeneratesEveryConflictingIDAndPreservesGraphReferences() async throws {
        let sourceConfiguration = makeImportConfiguration()
        let source = InMemoryCommandWheelProfileRepository(
            configuration: sourceConfiguration
        )
        let exported = try await source.exportProfiles()

        let uuidProvider = LockedSequenceUUIDProvider(
            values: (200 ... 215).map { persistenceTestID(UInt8($0)) }
        )
        let target = InMemoryCommandWheelProfileRepository(
            configuration: sourceConfiguration,
            uuidProvider: uuidProvider
        )
        let result = try await target.importProfiles(
            from: exported,
            knownCommandIDs: [BuiltInCommandID.searchFiles]
        )
        let importedProfileID = try #require(result.importedProfileIDs.first)
        let importedProfile = try #require(
            try await target.load().profiles.first(where: { $0.id == importedProfileID })
        )
        let original = try #require(sourceConfiguration.profiles.first)
        let originalRoot = original.rootPageID
        let originalChild = try #require(
            original.pages.first(where: { $0.id != originalRoot })?.id
        )
        let remappedRoot = try #require(result.pageIDRemapping[originalRoot])
        let remappedChild = try #require(result.pageIDRemapping[originalChild])
        let importedRoot = try #require(
            importedProfile.pages.first(where: { $0.id == remappedRoot })
        )
        let submenuTarget = importedRoot.segments.compactMap { segment -> UUID? in
            guard case .submenu(let pageID) = segment.content else { return nil }
            return pageID
        }.first

        #expect(result.profileIDRemapping.count == 1)
        #expect(result.pageIDRemapping.count == 2)
        #expect(result.segmentIDRemapping.count == 3)
        #expect(result.contextRuleIDRemapping.count == 1)
        #expect(importedProfile.rootPageID == remappedRoot)
        #expect(submenuTarget == remappedChild)
        #expect(result.referencedCommandIDs == [
            BuiltInCommandID.searchFiles,
            BuiltInCommandID.clipboardHistory,
        ])
        #expect(result.missingCommandIDs == [BuiltInCommandID.clipboardHistory])

        let merged = try await target.load()
        #expect(merged.profiles.count == 2)
        #expect(Set(merged.profiles.map(\.id)).count == 2)
        #expect(Set(merged.profiles.flatMap(\.pages).map(\.id)).count == 4)
        #expect(Set(
            merged.profiles.flatMap(\.pages).flatMap(\.segments).map(\.id)
        ).count == 6)
    }

    @Test
    func malformedAndInvalidImportsDoNotMutateRepository() async throws {
        let repository = InMemoryCommandWheelProfileRepository()
        let original = try await repository.load()

        await #expect(throws: CommandWheelRepositoryError.malformedImport) {
            try await repository.importProfiles(from: Data("not-json".utf8))
        }
        #expect(try await repository.load() == original)

        let unsupported = Data("{\"schemaVersion\":48,\"profiles\":[]}".utf8)
        await #expect(throws: CommandWheelRepositoryError.unsupportedImportVersion(48)) {
            try await repository.importProfiles(from: unsupported)
        }
        #expect(try await repository.load() == original)
    }
}

private struct LegacyCommandWheelEnvelopeV0: Encodable {
    let schemaVersion: Int
    let isEnabled: Bool
    let defaultProfileID: UUID?
    let profiles: [LegacyCommandWheelProfileV0]
}

private struct LegacyCommandWheelProfileV0: Encodable {
    let id: UUID
    let name: String
    let shortcut: LauncherHotKey?
    let rootPageID: UUID
    let pages: [CommandWheelPage]
}

/// Safety: every access to the reference's mutable sequence is serialized by `lock`, and the
/// sequence never escapes this test-only provider.
private nonisolated final class LockedSequenceUUIDProvider: UUIDProviding, @unchecked Sendable {
    private let lock = NSLock()
    private var values: [UUID]
    private var fallbackIndex: UInt8 = 240

    init(values: [UUID]) {
        self.values = values
    }

    func uuid() -> UUID {
        lock.lock()
        defer { lock.unlock() }
        if values.isEmpty == false {
            return values.removeFirst()
        }
        defer { fallbackIndex &+= 1 }
        return persistenceTestID(fallbackIndex)
    }
}

private func makeImportConfiguration() -> CommandWheelConfiguration {
    let profileID = persistenceTestID(20)
    let rootID = persistenceTestID(21)
    let childID = persistenceTestID(22)
    let profile = CommandWheelProfile(
        id: profileID,
        name: "Imported",
        isEnabled: true,
        shortcut: nil,
        activationBehavior: .holdAndRelease,
        placement: .cursor,
        rootPageID: rootID,
        pages: [
            CommandWheelPage(
                id: rootID,
                name: "Root",
                segments: [
                    CommandWheelSegment(
                        id: persistenceTestID(23),
                        slotIndex: 0,
                        content: .command(
                            CommandReference(commandID: BuiltInCommandID.searchFiles)
                        ),
                        customLabel: nil,
                        customIcon: nil
                    ),
                    CommandWheelSegment(
                        id: persistenceTestID(24),
                        slotIndex: 1,
                        content: .submenu(pageID: childID),
                        customLabel: nil,
                        customIcon: nil
                    ),
                ]
            ),
            CommandWheelPage(
                id: childID,
                name: "Child",
                segments: [
                    CommandWheelSegment(
                        id: persistenceTestID(25),
                        slotIndex: 0,
                        content: .command(
                            CommandReference(commandID: BuiltInCommandID.clipboardHistory)
                        ),
                        customLabel: nil,
                        customIcon: nil
                    ),
                ]
            ),
        ],
        contextRules: [
            CommandWheelContextRule(
                id: persistenceTestID(26),
                frontmostApplicationBundleIdentifier: "com.example.import",
                priority: 1,
                isEnabled: false
            ),
        ],
        appearance: CommandWheelDefaults.appearance,
        interaction: CommandWheelDefaults.interaction,
        hidesUnavailableSegments: false
    )
    return CommandWheelConfiguration(
        isEnabled: true,
        contextAwareProfileSelectionEnabled: true,
        defaultProfileID: profileID,
        profiles: [profile]
    )
}

private func temporaryPersistenceDirectory() -> URL {
    FileManager.default.temporaryDirectory
        .appendingPathComponent("Commandly-CommandWheelTests", isDirectory: true)
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
}

private nonisolated func persistenceTestID(_ finalByte: UInt8) -> UUID {
    UUID(uuid: (
        0x50, 0x45, 0x52, 0x53,
        0x49, 0x53,
        0x54, 0x57,
        0x80, 0x00,
        0x00, 0x00, 0x00, 0x00, 0x00, finalByte
    ))
}
