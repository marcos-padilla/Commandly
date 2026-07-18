import Foundation
import Testing
@testable import CommandKit

struct CommandKitTests {
    @Test func commandIDEquality() {
        let left = CommandID(rawValue: "open.settings")
        let right = CommandID(rawValue: "open.settings")
        let other = CommandID(rawValue: "open.about")
        #expect(left == right)
        #expect(left != other)
    }

    @Test func duplicateRegistrationThrows() async throws {
        let registry = CommandRegistry()
        let descriptor = CommandDescriptor(
            id: CommandID(rawValue: "demo.command"),
            title: "Demo",
            category: .productivity
        )
        try await registry.register(descriptor)
        await #expect(throws: CommandRegistryError.duplicateCommand(CommandID(rawValue: "demo.command"))) {
            try await registry.register(descriptor)
        }
        let count = await registry.count
        #expect(count == 1)
    }

    @Test func registryReturnsSortedDescriptors() async throws {
        let registry = CommandRegistry()
        try await registry.register(
            CommandDescriptor(id: CommandID(rawValue: "b"), title: "Bravo", category: .system)
        )
        try await registry.register(
            CommandDescriptor(id: CommandID(rawValue: "a"), title: "Alpha", category: .system)
        )
        let titles = await registry.allDescriptors().map(\.title)
        #expect(titles == ["Alpha", "Bravo"])
    }

    @Test func manifestRegistrationPreservesModeAndActions() async throws {
        let registry = CommandRegistry()
        let manifest = CommandManifest(
            id: BuiltInCommandID.clipboardHistory,
            title: "Clipboard History",
            systemImage: "clipboard",
            category: .productivity,
            mode: .view,
            defaultActions: [
                CommandActionDescriptor(
                    id: BuiltInCommandActionID.copy,
                    title: "Copy",
                    isPrimary: true,
                    keyHint: .return
                )
            ]
        )
        try await registry.register(manifest)
        let loaded = await registry.manifest(for: BuiltInCommandID.clipboardHistory)
        #expect(loaded?.mode == .view)
        #expect(loaded?.defaultActions.first?.id == BuiltInCommandActionID.copy)
    }

    @Test func commandReferenceCodableRoundTripPreservesTypedArguments() throws {
        let targetURL = try #require(URL(string: "https://example.com/path"))
        let reference = CommandReference(
            commandID: CommandID(rawValue: "test.arguments"),
            arguments: CommandArguments([
                "name": .string("Commandly"),
                "enabled": .boolean(true),
                "count": .integer(3),
                "ratio": .decimal(0.75),
                "target": .url(targetURL),
                "labels": .stringList(["one", "two"]),
            ])
        )

        let data = try JSONEncoder().encode(reference)
        let decoded = try JSONDecoder().decode(CommandReference.self, from: data)

        #expect(decoded == reference)
        #expect(decoded.arguments["count"] == .integer(3))
        #expect(String(decoding: data, as: UTF8.self).contains("\"type\""))
    }

    @Test func invocationContextRoundTripPreservesWheelSourceMetadata() throws {
        let profileID = try #require(UUID(uuidString: "00000000-0000-0000-0000-000000000001"))
        let pageID = try #require(UUID(uuidString: "00000000-0000-0000-0000-000000000002"))
        let segmentID = try #require(UUID(uuidString: "00000000-0000-0000-0000-000000000003"))
        let timestamp = Date(timeIntervalSince1970: 1_234)
        let context = CommandInvocationContext(
            source: .commandWheel(
                profileID: profileID,
                pageID: pageID,
                segmentID: segmentID
            ),
            frontmostApplicationBundleIdentifier: "com.example.Editor",
            screenIdentifier: "display-1",
            timestamp: timestamp
        )

        let data = try JSONEncoder().encode(context)
        let decoded = try JSONDecoder().decode(CommandInvocationContext.self, from: data)

        #expect(decoded == context)
        #expect(CommandInvocationSource.search != .applicationHotKey)
    }

    @Test func resolverAppliesDefaultsAndPreservesValidatedValues() async throws {
        let id = CommandID(rawValue: "test.resolve")
        let manifest = makeManifest(
            id: id,
            arguments: [
                CommandArgument(
                    name: "name",
                    description: "Name",
                    isRequired: true,
                    valueType: .string
                ),
                CommandArgument(
                    name: "count",
                    description: "Count",
                    isRequired: false,
                    valueType: .integer,
                    defaultValue: .integer(2)
                ),
            ]
        )
        let registry = CommandRegistry()
        try await registry.register(manifest)

        let resolved = try await registry.resolve(
            reference: CommandReference(
                commandID: id,
                arguments: CommandArguments(["name": .string("Demo")])
            )
        )

        #expect(resolved.manifest == manifest)
        #expect(resolved.reference.arguments["name"] == .string("Demo"))
        #expect(resolved.reference.arguments["count"] == .integer(2))
        #expect(resolved.availability == .available)
    }

    @Test func resolverRejectsMissingRequiredArguments() async throws {
        let id = CommandID(rawValue: "test.required")
        let registry = CommandRegistry()
        try await registry.register(
            makeManifest(
                id: id,
                arguments: [
                    CommandArgument(
                        name: "target",
                        description: "Target",
                        isRequired: true,
                        valueType: .url
                    )
                ]
            )
        )

        await #expect(
            throws: CommandRegistryError.missingRequiredArgument(
                commandID: id,
                name: "target"
            )
        ) {
            try await registry.resolve(reference: CommandReference(commandID: id))
        }
    }

    @Test func resolverRejectsUnknownArguments() async throws {
        let id = CommandID(rawValue: "test.unknown")
        let registry = CommandRegistry()
        try await registry.register(makeManifest(id: id))

        await #expect(
            throws: CommandRegistryError.unknownArgument(commandID: id, name: "extra")
        ) {
            try await registry.resolve(
                reference: CommandReference(
                    commandID: id,
                    arguments: CommandArguments(["extra": .string("value")])
                )
            )
        }
    }

    @Test func resolverRejectsTypeInvalidArguments() async throws {
        let id = CommandID(rawValue: "test.type")
        let registry = CommandRegistry()
        try await registry.register(
            makeManifest(
                id: id,
                arguments: [
                    CommandArgument(
                        name: "enabled",
                        description: "Enabled",
                        isRequired: true,
                        valueType: .boolean
                    )
                ]
            )
        )

        await #expect(
            throws: CommandRegistryError.invalidArgumentType(
                commandID: id,
                name: "enabled",
                expected: .boolean,
                actual: .string
            )
        ) {
            try await registry.resolve(
                reference: CommandReference(
                    commandID: id,
                    arguments: CommandArguments(["enabled": .string("true")])
                )
            )
        }
    }

    @Test func resolverRejectsMissingCommands() async {
        let id = CommandID(rawValue: "test.missing")
        let registry = CommandRegistry()

        await #expect(throws: CommandRegistryError.commandNotFound(id)) {
            try await registry.resolve(reference: CommandReference(commandID: id))
        }
    }

    @Test func catalogReplacementIsAtomicAndDeterministicallySorted() async throws {
        let registry = CommandRegistry()
        let alpha = makeManifest(id: CommandID(rawValue: "a"), title: "Alpha")
        let secondAlpha = makeManifest(id: CommandID(rawValue: "a-2"), title: "Alpha")
        let bravo = makeManifest(id: CommandID(rawValue: "b"), title: "Bravo")

        try await registry.replaceCatalog(with: [bravo, secondAlpha, alpha])
        let sortedIDs = await registry.allManifests().map(\.id)
        #expect(sortedIDs == [alpha.id, secondAlpha.id, bravo.id])

        await #expect(throws: CommandRegistryError.duplicateCommand(alpha.id)) {
            try await registry.replaceCatalog(with: [alpha, alpha])
        }
        let unchangedIDs = await registry.allManifests().map(\.id)
        #expect(unchangedIDs == sortedIDs)
    }

    @Test func registryResolvesKnownDisabledCommandFromAtomicAvailabilitySnapshot() async throws {
        let manifest = makeManifest(id: CommandID(rawValue: "test.disabled"))
        let availability = CommandAvailabilitySnapshot(
            commandAvailability: [manifest.id: .unavailable(.disabled)]
        )
        let registry = CommandRegistry()

        try await registry.replaceCatalog(
            with: [manifest],
            availability: availability
        )

        let resolved = try await registry.resolve(
            reference: CommandReference(commandID: manifest.id)
        )
        #expect(resolved.manifest == manifest)
        #expect(resolved.availability == .unavailable(.disabled))
        #expect(await registry.catalogSnapshot() == CommandCatalogSnapshot(
            manifests: [manifest],
            availability: availability
        ))
    }

    @Test func installedApplicationAvailabilityIsReferenceAware() async throws {
        let installedBundleIdentifier = "com.example.Installed"
        let registry = CommandRegistry()
        try await registry.replaceCatalog(
            with: [BuiltInCommandManifest.openInstalledApplication],
            availability: CommandAvailabilitySnapshot(
                installedApplicationBundleIdentifiers: [installedBundleIdentifier]
            )
        )

        let installed = try await registry.resolve(
            reference: BuiltInCommandReference.openInstalledApplication(
                bundleIdentifier: installedBundleIdentifier
            )
        )
        let uninstalled = try await registry.resolve(
            reference: BuiltInCommandReference.openInstalledApplication(
                bundleIdentifier: "com.example.Uninstalled"
            )
        )

        #expect(installed.availability == .available)
        #expect(
            uninstalled.availability
                == .unavailable(.missingDependency(identifier: "installed-application"))
        )
    }

    @Test func legacyDescriptorRegistrationPreservesArgumentSchema() async throws {
        let id = CommandID(rawValue: "test.legacy")
        let argument = CommandArgument(
            name: "query",
            description: "Search query",
            isRequired: true,
            valueType: .string
        )
        let registry = CommandRegistry()

        try await registry.register(
            CommandDescriptor(
                id: id,
                title: "Legacy",
                category: .productivity,
                arguments: [argument]
            )
        )

        #expect(await registry.manifest(for: id)?.arguments == [argument])
        #expect(await registry.descriptor(for: id)?.arguments == [argument])
    }

    @Test func registryRejectsInvalidArgumentSchemasWithoutMutation() async throws {
        let existing = makeManifest(id: CommandID(rawValue: "existing"))
        let invalidID = CommandID(rawValue: "invalid")
        let duplicate = CommandArgument(
            name: "value",
            description: "Value",
            isRequired: false
        )
        let registry = CommandRegistry()
        try await registry.register(existing)

        await #expect(
            throws: CommandRegistryError.duplicateArgument(
                commandID: invalidID,
                name: "value"
            )
        ) {
            try await registry.replaceCatalog(
                with: [makeManifest(id: invalidID, arguments: [duplicate, duplicate])]
            )
        }

        #expect(await registry.allManifests() == [existing])
    }

    @Test func registryRejectsNonFiniteDecimalDefaultsAndReferences() async throws {
        let defaultCommandID = CommandID(rawValue: "test.nonfinite-default")
        let referenceCommandID = CommandID(rawValue: "test.nonfinite-reference")
        let decimalArgument = CommandArgument(
            name: "ratio",
            description: "Ratio",
            isRequired: true,
            valueType: .decimal
        )
        let registry = CommandRegistry()

        await #expect(
            throws: CommandRegistryError.nonFiniteDecimal(
                commandID: defaultCommandID,
                name: decimalArgument.name
            )
        ) {
            try await registry.register(
                makeManifest(
                    id: defaultCommandID,
                    arguments: [
                        CommandArgument(
                            name: decimalArgument.name,
                            description: decimalArgument.description,
                            isRequired: false,
                            valueType: .decimal,
                            defaultValue: .decimal(.infinity)
                        )
                    ]
                )
            )
        }

        try await registry.register(
            makeManifest(id: referenceCommandID, arguments: [decimalArgument])
        )
        await #expect(
            throws: CommandRegistryError.nonFiniteDecimal(
                commandID: referenceCommandID,
                name: decimalArgument.name
            )
        ) {
            try await registry.resolve(
                reference: CommandReference(
                    commandID: referenceCommandID,
                    arguments: CommandArguments([
                        decimalArgument.name: .decimal(.nan)
                    ])
                )
            )
        }
    }

    @Test func commandResultMapsToPrivacySafeExecutionOutcome() {
        #expect(CommandResult.success(message: "Done").executionOutcome == .succeeded)
        #expect(CommandResult.failure(message: "Failed").executionOutcome == .failed)
        #expect(CommandResult.cancelled.executionOutcome == .cancelled)
    }

    @Test func installedApplicationBuiltInUsesOneTypedParameterizedReference() async throws {
        let bundleIdentifier = "com.example.commandly-test"
        let manifest = BuiltInCommandManifest.openInstalledApplication
        let reference = BuiltInCommandReference.openInstalledApplication(
            bundleIdentifier: bundleIdentifier
        )
        let registry = CommandRegistry()
        try await registry.register(manifest)

        let resolved = try await registry.resolve(reference: reference)

        #expect(manifest.id == BuiltInCommandID.openInstalledApplication)
        #expect(manifest.arguments.count == 1)
        #expect(manifest.arguments.first?.name == BuiltInCommandArgumentName.bundleIdentifier)
        #expect(manifest.arguments.first?.valueType == .string)
        #expect(manifest.arguments.first?.isRequired == true)
        #expect(
            resolved.reference.arguments[BuiltInCommandArgumentName.bundleIdentifier]
                == .string(bundleIdentifier)
        )
    }

    @Test func usageHistoryCountsOnlySuccessAndUsesLatestSuccessfulTimestamp() async throws {
        let commandID = CommandID(rawValue: "test.history")
        let otherID = CommandID(rawValue: "test.other")
        let history = InMemoryCommandUsageHistory()
        let duplicateID = try #require(
            UUID(uuidString: "00000000-0000-0000-0000-000000000010")
        )
        let firstSuccess = CommandExecutionRecord(
            id: duplicateID,
            commandID: commandID,
            source: .search,
            outcome: .succeeded,
            timestamp: Date(timeIntervalSince1970: 100)
        )
        let latestSuccess = CommandExecutionRecord(
            commandID: commandID,
            source: .applicationHotKey,
            outcome: .succeeded,
            timestamp: Date(timeIntervalSince1970: 300)
        )

        await history.record(firstSuccess)
        await history.record(firstSuccess)
        await history.record(
            CommandExecutionRecord(
                commandID: commandID,
                source: .search,
                outcome: .failed,
                timestamp: Date(timeIntervalSince1970: 400)
            )
        )
        await history.record(latestSuccess)
        await history.record(
            CommandExecutionRecord(
                commandID: otherID,
                source: .search,
                outcome: .cancelled,
                timestamp: Date(timeIntervalSince1970: 500)
            )
        )

        let records = await history.records(for: commandID)
        let summary = try #require(await history.summary(for: commandID))
        let summaries = await history.allSummaries()

        #expect(records.count == 3)
        #expect(summary.successfulExecutionCount == 2)
        #expect(summary.lastSuccessfulExecutionAt == latestSuccess.timestamp)
        #expect(await history.summary(for: otherID) == nil)
        #expect(summaries == [summary])
    }

    private func makeManifest(
        id: CommandID,
        title: String = "Test Command",
        arguments: [CommandArgument] = []
    ) -> CommandManifest {
        CommandManifest(
            id: id,
            title: title,
            systemImage: "command",
            category: .productivity,
            mode: .action,
            arguments: arguments
        )
    }
}
