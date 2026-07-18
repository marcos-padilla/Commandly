import CommandKit
import Foundation
import Infrastructure
import SecurityKit
import Testing
@testable import Commandly

@Suite("Command Wheel settings and shared store")
struct CommandWheelSettingsModelTests {
    @Test @MainActor
    func editWaitsForInflightPreloadAndCannotBeOverwritten() async throws {
        var durable = emptyWheelConfiguration()
        durable.profiles[0].name = "Durable"
        let repository = SuspendedCommandWheelRepository(loadResult: durable)
        let store = CommandWheelProfileStore(
            repository: repository,
            initialConfiguration: emptyWheelConfiguration()
        )

        let preload = Task { await store.preload() }
        await repository.waitUntilLoadStarts()
        let edit = Task {
            try await store.update { configuration in
                configuration.profiles[0].name = "Edited after load"
            }
        }
        await Task.yield()
        await repository.releaseLoad()

        await preload.value
        try await edit.value

        #expect(store.configuration.profiles[0].name == "Edited after load")
        #expect(await repository.savedConfiguration()?.profiles[0].name == "Edited after load")
        #expect(await repository.loadCount() == 1)
    }

    @Test @MainActor
    func staleCatalogRefreshCannotOverwriteANewerSettingsGeneration() async throws {
        let initialManifest = testManifest(id: "test.catalog.initial", title: "Initial")
        let olderManifest = testManifest(id: "test.catalog.older", title: "Older")
        let newerManifest = testManifest(id: "test.catalog.newer", title: "Newer")
        let source = SuspendedSettingsCatalogSource()
        let model = CommandWheelSettingsModel(
            store: CommandWheelProfileStore(
                repository: InMemoryCommandWheelProfileRepository(
                    configuration: emptyWheelConfiguration()
                )
            ),
            catalog: CommandWheelCommandCatalogSnapshot(manifests: [initialManifest]),
            catalogProvider: { await source.snapshot() }
        )

        let olderRefresh = Task { @MainActor in
            await model.refreshCatalog()
        }
        await source.waitUntilCallCount(1)

        let newerRefresh = Task { @MainActor in
            await model.refreshCatalog()
        }
        await source.waitUntilCallCount(2)

        await source.resume(
            pass: 2,
            with: CommandCatalogSnapshot(manifests: [newerManifest])
        )
        await newerRefresh.value
        #expect(model.catalog.manifests.map(\.title) == ["Newer"])

        await source.resume(
            pass: 1,
            with: CommandCatalogSnapshot(manifests: [olderManifest])
        )
        await olderRefresh.value
        #expect(model.catalog.manifests.map(\.title) == ["Newer"])
    }

    @Test @MainActor
    func invalidEditDoesNotPublishOrPersistCandidate() async throws {
        let original = emptyWheelConfiguration()
        let repository = RecordingCommandWheelRepository(configuration: original)
        var publications: [CommandWheelConfiguration] = []
        let store = CommandWheelProfileStore(
            repository: repository,
            onConfigurationChange: { publications.append($0) }
        )
        await store.preload()
        publications.removeAll()

        await #expect(throws: CommandWheelProfileStoreError.self) {
            try await store.update { configuration in
                configuration.profiles[0].pages.removeAll()
            }
        }

        #expect(store.configuration == original)
        #expect(await repository.saveCount() == 0)
        #expect(publications.isEmpty)
    }

    @Test @MainActor
    func atomicSubmenuAssignmentUsesOneSaveAndCreatesStableChildSlots() async throws {
        let original = emptyWheelConfiguration()
        let repository = RecordingCommandWheelRepository(configuration: original)
        let store = CommandWheelProfileStore(repository: repository)
        await store.preload()
        let profile = original.profiles[0]
        let location = CommandWheelSlotLocation(
            profileID: profile.id,
            pageID: profile.rootPageID,
            slotIndex: 0
        )
        let reference = CommandReference(commandID: CommandID(rawValue: "test.atomic"))

        let childID = try await store.createSubmenu(
            named: "Utilities",
            at: location,
            replacing: false,
            containing: reference
        )

        let result = store.configuration
        let child = try #require(result.profiles[0].pages.first(where: { $0.id == childID }))
        #expect(await repository.saveCount() == 1)
        #expect(child.segments.count == profile.interaction.visibleSlotCount)
        #expect(Set(child.segments.map(\.slotIndex)) == Set(0 ..< profile.interaction.visibleSlotCount))
        #expect(child.segments.first(where: { $0.slotIndex == 0 })?.content == .command(reference))
        #expect(store.locations(for: reference).first?.location.pageID == childID)
    }

    @Test @MainActor
    func replacingSubmenuPrunesItsWholeChildTree() async throws {
        let original = emptyWheelConfiguration()
        let store = CommandWheelProfileStore(
            repository: InMemoryCommandWheelProfileRepository(configuration: original)
        )
        await store.preload()
        let profile = original.profiles[0]
        let rootSlot = CommandWheelSlotLocation(
            profileID: profile.id,
            pageID: profile.rootPageID,
            slotIndex: 0
        )
        let childID = try await store.createSubmenu(
            named: "Child",
            at: rootSlot,
            replacing: false
        )
        _ = try await store.createSubmenu(
            named: "Grandchild",
            at: CommandWheelSlotLocation(
                profileID: profile.id,
                pageID: childID,
                slotIndex: 1
            ),
            replacing: false
        )
        #expect(store.configuration.profiles[0].pages.count == 3)

        let replacement = CommandReference(commandID: CommandID(rawValue: "test.replace"))
        try await store.assign(replacement, to: rootSlot, replacing: true)

        #expect(store.configuration.profiles[0].pages.map(\.id) == [profile.rootPageID])
        #expect(store.locations(for: replacement).count == 1)
    }

    @Test @MainActor
    func slotCountKeepsRetainedIDsAndCreatesStableEmptyRecords() async throws {
        let original = emptyWheelConfiguration()
        let store = CommandWheelProfileStore(
            repository: InMemoryCommandWheelProfileRepository(configuration: original)
        )
        await store.preload()
        let profileID = original.profiles[0].id
        let originalIDs = segmentIDs(in: store.configuration)

        try await store.setVisibleSlotCount(5, profileID: profileID)
        let reducedIDs = segmentIDs(in: store.configuration)
        #expect(reducedIDs == Dictionary(uniqueKeysWithValues: originalIDs.filter { $0.key < 5 }))

        try await store.setVisibleSlotCount(8, profileID: profileID)
        let expandedIDs = segmentIDs(in: store.configuration)
        for slotIndex in 0 ..< 5 {
            #expect(expandedIDs[slotIndex] == originalIDs[slotIndex])
        }
        #expect(Set(expandedIDs.keys) == Set(0 ..< 8))
        #expect(store.configuration.profiles[0].pages[0].segments.allSatisfy {
            $0.content == .empty
        })
    }

    @Test @MainActor
    func slotReorderSwapsOccupiedContentWithoutDeletingSubmenuTrees() async throws {
        let commandA = CommandReference(commandID: CommandID(rawValue: "test.swap-a"))
        let commandB = CommandReference(commandID: CommandID(rawValue: "test.swap-b"))
        let model = makeSettingsModel(
            configuration: emptyWheelConfiguration(),
            manifests: []
        )
        await model.load()
        let profile = try #require(model.selectedProfile)
        let pageID = profile.rootPageID
        try await model.store.assign(
            commandA,
            to: CommandWheelSlotLocation(profileID: profile.id, pageID: pageID, slotIndex: 0),
            replacing: false
        )
        try await model.store.assign(
            commandB,
            to: CommandWheelSlotLocation(profileID: profile.id, pageID: pageID, slotIndex: 1),
            replacing: false
        )
        let childID = try await model.store.createSubmenu(
            named: "Kept Child",
            at: CommandWheelSlotLocation(profileID: profile.id, pageID: pageID, slotIndex: 2),
            replacing: false
        )

        model.selectSlot(0)
        try await model.moveSlot(0, direction: .later)
        #expect(commandID(at: 0, in: model.configuration) == commandB.commandID)
        #expect(commandID(at: 1, in: model.configuration) == commandA.commandID)

        model.selectSlot(2)
        try await model.moveSlot(2, direction: .later)
        let root = try #require(model.selectedProfile?.pages.first(where: { $0.id == pageID }))
        #expect(root.segments.first(where: { $0.slotIndex == 2 })?.content == .empty)
        #expect(root.segments.first(where: { $0.slotIndex == 3 })?.content == .submenu(pageID: childID))
        #expect(model.selectedProfile?.pages.contains(where: { $0.id == childID }) == true)
    }

    @Test @MainActor
    func shrinkingVisibleSlotsRejectsOccupiedTruncatedContent() async throws {
        let model = makeSettingsModel(
            configuration: emptyWheelConfiguration(),
            manifests: []
        )
        await model.load()
        let profile = try #require(model.selectedProfile)
        let location = CommandWheelSlotLocation(
            profileID: profile.id,
            pageID: profile.rootPageID,
            slotIndex: 7
        )
        try await model.store.assign(
            CommandReference(commandID: CommandID(rawValue: "test.truncated")),
            to: location,
            replacing: false
        )

        await #expect(throws: CommandWheelSettingsError.occupiedSlotsOutsideRange) {
            try await model.setSlotCount(4, profileID: profile.id)
        }
        #expect(model.selectedProfile?.interaction.visibleSlotCount == 8)
        #expect(commandID(at: 7, in: model.configuration)?.rawValue == "test.truncated")
    }

    @Test @MainActor
    func genericPickerExcludesCommandsMissingRequiredInvocationInput() {
        let requiresInput = CommandManifest(
            id: CommandID(rawValue: "test.requires-input"),
            title: "Requires Input",
            systemImage: "text.cursor",
            category: .productivity,
            mode: .action,
            arguments: [
                CommandArgument(
                    name: "value",
                    description: "Required value",
                    isRequired: true,
                    valueType: .string
                ),
            ]
        )
        let hasDefault = CommandManifest(
            id: CommandID(rawValue: "test.has-default"),
            title: "Has Default",
            systemImage: "checkmark",
            category: .productivity,
            mode: .action,
            arguments: [
                CommandArgument(
                    name: "value",
                    description: "Defaulted value",
                    isRequired: true,
                    valueType: .string,
                    defaultValue: .string("safe")
                ),
            ]
        )
        let picker = CommandWheelCommandPickerModel(
            catalog: CommandWheelCommandCatalogSnapshot(
                manifests: [requiresInput, hasDefault]
            )
        )

        #expect(picker.options.map(\.manifest.id) == [hasDefault.id])
        #expect(picker.manifest(for: requiresInput.id) == requiresInput)
        #expect(picker.assignableManifest(for: requiresInput.id) == nil)
        #expect(picker.manifest(for: hasDefault.id) == hasDefault)
    }

    @Test @MainActor
    func installedApplicationsSearchAsExactReferenceAwarePickerOptions() async throws {
        let application = InstalledApplication(
            bundleIdentifier: "com.example.Notes",
            name: "Notes Pro",
            path: "/Applications/Notes Pro.app"
        )
        let picker = CommandWheelCommandPickerModel(
            catalog: installedApplicationCatalog(
                availableBundleIdentifiers: [application.bundleIdentifier]
            ),
            installedApplicationQuery: InMemoryInstalledApplicationQuery(
                applications: [application]
            )
        )
        picker.query = "notes"

        await picker.search()

        let option = try #require(picker.options.first)
        #expect(picker.options.count == 1)
        #expect(option.title == application.name)
        #expect(option.subtitle == application.bundleIdentifier)
        #expect(option.icon == .application(path: application.path))
        #expect(option.availability == .available)
        #expect(
            option.reference == BuiltInCommandReference.openInstalledApplication(
                bundleIdentifier: application.bundleIdentifier
            )
        )
    }

    @Test @MainActor
    func settingsPickerPersistsInstalledApplicationReferenceAndDisplayName() async throws {
        let application = InstalledApplication(
            bundleIdentifier: "com.example.RapidAccess",
            name: "Rapid Access",
            path: "/Applications/Rapid Access.app"
        )
        let model = CommandWheelSettingsModel(
            store: CommandWheelProfileStore(
                repository: InMemoryCommandWheelProfileRepository(
                    configuration: emptyWheelConfiguration()
                )
            ),
            catalog: installedApplicationCatalog(
                availableBundleIdentifiers: [application.bundleIdentifier]
            ),
            installedApplicationQuery: InMemoryInstalledApplicationQuery(
                applications: [application]
            )
        )
        await model.load()
        model.commandPicker.query = "rapid"
        await model.commandPicker.search()
        let option = try #require(model.commandPicker.options.first)

        try await model.requestCommandAssignment(option, to: 0)

        let segment = try #require(
            model.selectedPage?.segments.first(where: { $0.slotIndex == 0 })
        )
        #expect(segment.content == .command(option.reference))
        #expect(segment.customLabel == application.name)
        #expect(model.slotPresentations.first?.title == application.name)
        #expect(model.slotPresentations.first?.availability == .available)
        #expect(model.slotPresentations.first?.applicationIconPath == application.path)
        #expect(model.slotPresentations.first?.usesCustomIcon == false)

        try await model.setSegmentIcon("star.fill", slotIndex: 0)
        #expect(model.slotPresentations.first?.systemImage == "star.fill")
        #expect(model.slotPresentations.first?.usesCustomIcon == true)
        #expect(model.slotPresentations.first?.applicationIconPath == nil)
    }

    @Test @MainActor
    func installedApplicationPickerOptionUsesReferenceAwareUnavailableState() async throws {
        let application = InstalledApplication(
            bundleIdentifier: "com.example.StaleInventory",
            name: "Stale Inventory",
            path: "/Applications/Stale Inventory.app"
        )
        let picker = CommandWheelCommandPickerModel(
            catalog: installedApplicationCatalog(availableBundleIdentifiers: []),
            installedApplicationQuery: InMemoryInstalledApplicationQuery(
                applications: [application]
            )
        )
        picker.query = "stale"

        await picker.search()

        let option = try #require(picker.options.first)
        #expect(
            option.availability
                == .unavailable(.missingDependency(identifier: "installed-application"))
        )
    }

    @Test @MainActor
    func invalidCustomSymbolLeavesSegmentPresentationUntouched() async throws {
        let model = CommandWheelSettingsModel(
            store: CommandWheelProfileStore(
                repository: InMemoryCommandWheelProfileRepository(
                    configuration: emptyWheelConfiguration()
                )
            ),
            catalog: CommandWheelCommandCatalogSnapshot(manifests: [])
        )
        await model.load()
        let original = try #require(
            model.selectedPage?.segments.first(where: { $0.slotIndex == 0 })
        )

        await #expect(throws: CommandWheelSettingsError.invalidSymbol) {
            try await model.setSegmentPresentation(
                label: "Must not partially save",
                systemSymbol: "commandly.symbol.that.does.not.exist",
                slotIndex: 0
            )
        }

        let unchanged = try #require(
            model.selectedPage?.segments.first(where: { $0.slotIndex == 0 })
        )
        #expect(unchanged.customLabel == original.customLabel)
        #expect(unchanged.customIcon == original.customIcon)

        try await model.setSegmentPresentation(
            label: "Pinned",
            systemSymbol: "star.fill",
            slotIndex: 0
        )
        let updated = try #require(
            model.selectedPage?.segments.first(where: { $0.slotIndex == 0 })
        )
        #expect(updated.customLabel == "Pinned")
        #expect(updated.customIcon?.systemSymbolName == "star.fill")
    }

    @Test @MainActor
    func occupiedAssignmentWaitsForExplicitReplacementConfirmation() async throws {
        let commandA = testManifest(id: "test.command-a", title: "Command A")
        let commandB = testManifest(id: "test.command-b", title: "Command B")
        var configuration = emptyWheelConfiguration()
        configuration.profiles[0].pages[0].segments[0].content = .command(
            CommandReference(commandID: commandA.id)
        )
        let model = makeSettingsModel(
            configuration: configuration,
            manifests: [commandA, commandB]
        )
        await model.load()

        try await model.requestCommandAssignment(commandB.id, to: 0)
        #expect(model.pendingReplacement?.reference.commandID == commandB.id)
        #expect(commandID(at: 0, in: model.configuration) == commandA.id)

        try await model.confirmPendingReplacement()
        #expect(model.pendingReplacement == nil)
        #expect(commandID(at: 0, in: model.configuration) == commandB.id)
    }

    @Test @MainActor
    func duplicateProfileShortcutIsRejectedAndRuntimeIssueIsExplained() async throws {
        let configuration = emptyWheelConfiguration()
        let defaultID = configuration.defaultProfileID
        let hotKey = LauncherHotKey(keyCode: 49, modifiers: [.control, .option])
        let model = makeSettingsModel(
            configuration: configuration,
            manifests: [],
            shortcutIssues: { [defaultID: .unavailable] }
        )
        await model.load()
        try await model.setShortcut(hotKey, profileID: defaultID)
        #expect(model.shortcutWarning(for: defaultID)?.contains("macOS") == true)

        try await model.createProfile(named: "Second")
        let secondID = try #require(model.selectedProfileID)
        await #expect(throws: CommandWheelSettingsError.duplicateShortcut) {
            try await model.setShortcut(hotKey, profileID: secondID)
        }
        #expect(model.configuration.profiles.first(where: { $0.id == secondID })?.shortcut == nil)
    }

    @Test @MainActor
    func contextConflictMessageIsDeterministicAndPreventsSave() async throws {
        let model = makeSettingsModel(
            configuration: emptyWheelConfiguration(),
            manifests: []
        )
        await model.load()
        try await model.addContextRule(
            bundleIdentifier: "com.example.Editor",
            priority: 20
        )

        #expect(
            model.contextConflictMessage(
                bundleIdentifier: " COM.EXAMPLE.editor ",
                priority: 20
            ) != nil
        )
        await #expect(throws: CommandWheelSettingsError.contextRuleConflict) {
            try await model.addContextRule(
                bundleIdentifier: "com.example.editor",
                priority: 20
            )
        }
        #expect(model.selectedProfile?.contextRules.count == 1)
    }

    @Test @MainActor
    func interactionResetIsSeparateFromAppearanceAndRestoresStableSlots() async throws {
        var configuration = emptyWheelConfiguration()
        configuration.profiles[0].interaction.visibleSlotCount = 4
        configuration.profiles[0].interaction.deadZoneRadius = 9
        configuration.profiles[0].interaction.allowsClickSelection = false
        configuration.profiles[0].pages[0].segments.removeAll { $0.slotIndex >= 4 }
        configuration.profiles[0].appearance.wheelRadius = 222
        let profileID = configuration.defaultProfileID
        let model = makeSettingsModel(configuration: configuration, manifests: [])
        await model.load()

        try await model.resetInteractionDefaults(profileID: profileID)

        let profile = try #require(model.selectedProfile)
        #expect(profile.interaction == CommandWheelDefaults.interaction)
        #expect(profile.appearance.wheelRadius == 222)
        #expect(profile.pages[0].segments.count == CommandWheelDefaults.interaction.visibleSlotCount)
        #expect(Set(profile.pages[0].segments.map(\.slotIndex)) == Set(0 ..< 8))
    }

    @Test @MainActor
    func fixedPlacementCoordinatesRemainNormalizedAndPreserveDisplayIdentity() async throws {
        let configuration = emptyWheelConfiguration()
        let profileID = configuration.defaultProfileID
        let model = makeSettingsModel(configuration: configuration, manifests: [])
        await model.load()
        try await model.setPlacement(
            .fixedNormalizedPoint(screenIdentifier: "display-two", x: 0.5, y: 0.5),
            profileID: profileID
        )

        try await model.setFixedPlacementCoordinates(
            x: 0.2,
            y: 0.8,
            profileID: profileID
        )

        #expect(
            model.selectedProfile?.placement
                == .fixedNormalizedPoint(
                    screenIdentifier: "display-two",
                    x: 0.2,
                    y: 0.8
                )
        )

        try await model.setFixedPlacementScreenIdentifier(
            "display-three",
            profileID: profileID
        )
        #expect(
            model.selectedProfile?.placement
                == .fixedNormalizedPoint(
                    screenIdentifier: "display-three",
                    x: 0.2,
                    y: 0.8
                )
        )
    }

    @Test @MainActor
    func permissionPresentationExplainsStatusWithoutClaimingShortcutPermission() async {
        let model = makeSettingsModel(
            configuration: emptyWheelConfiguration(),
            manifests: []
        )
        await model.load()

        let denied = model.accessibilityPermissionPresentation(for: .denied)
        let granted = model.accessibilityPermissionPresentation(for: .authorized)

        #expect(denied.title == "Accessibility denied")
        #expect(denied.detail.contains("does not require Accessibility"))
        #expect(granted.title == "Accessibility granted")
    }

    @Test @MainActor
    func revealSelectsOnlyAValidPersistedLocation() async throws {
        let configuration = emptyWheelConfiguration()
        let model = makeSettingsModel(configuration: configuration, manifests: [])
        await model.load()
        let profile = configuration.profiles[0]
        let valid = CommandWheelSlotLocation(
            profileID: profile.id,
            pageID: profile.rootPageID,
            slotIndex: 3
        )

        #expect(model.reveal(valid))
        #expect(model.selectedProfileID == profile.id)
        #expect(model.selectedPageID == profile.rootPageID)
        #expect(model.selectedSlotIndex == 3)

        let invalid = CommandWheelSlotLocation(
            profileID: profile.id,
            pageID: profile.rootPageID,
            slotIndex: 99
        )
        #expect(model.reveal(invalid) == false)
        #expect(model.selectedSlotIndex == 3)
    }

    @Test @MainActor
    func failedPreloadPreservesStorageUntilExplicitDefaultsRecovery() async throws {
        let repository = RecoverableFailedCommandWheelRepository()
        let store = CommandWheelProfileStore(repository: repository)
        let model = CommandWheelSettingsModel(
            store: store,
            catalog: CommandWheelCommandCatalogSnapshot(manifests: [])
        )

        await model.load()
        #expect(store.phase == .failed)
        #expect(await repository.saveCount() == 0)

        try await model.restoreDefaultsAfterStorageFailure()

        #expect(store.phase == .ready)
        #expect(store.configuration == CommandWheelDefaults.configuration)
        #expect(await repository.savedConfiguration() == CommandWheelDefaults.configuration)
        #expect(await repository.saveCount() == 1)
    }
}

private actor SuspendedSettingsCatalogSource {
    private struct CallCountWaiter {
        let expectedCount: Int
        let continuation: CheckedContinuation<Void, Never>
    }

    private(set) var callCount = 0
    private var pending: [
        Int: CheckedContinuation<CommandCatalogSnapshot, Never>
    ] = [:]
    private var callCountWaiters: [CallCountWaiter] = []

    func snapshot() async -> CommandCatalogSnapshot {
        callCount += 1
        let pass = callCount
        resumeSatisfiedCallCountWaiters()
        return await withCheckedContinuation { continuation in
            pending[pass] = continuation
        }
    }

    func waitUntilCallCount(_ expectedCount: Int) async {
        if callCount >= expectedCount { return }
        await withCheckedContinuation { continuation in
            callCountWaiters.append(
                CallCountWaiter(
                    expectedCount: expectedCount,
                    continuation: continuation
                )
            )
        }
    }

    func resume(pass: Int, with snapshot: CommandCatalogSnapshot) {
        pending.removeValue(forKey: pass)?.resume(returning: snapshot)
    }

    private func resumeSatisfiedCallCountWaiters() {
        var remaining = [CallCountWaiter]()
        for waiter in callCountWaiters {
            if callCount >= waiter.expectedCount {
                waiter.continuation.resume()
            } else {
                remaining.append(waiter)
            }
        }
        callCountWaiters = remaining
    }
}

private actor RecordingCommandWheelRepository: CommandWheelProfileRepository {
    private var configuration: CommandWheelConfiguration
    private var saves = 0

    init(configuration: CommandWheelConfiguration) {
        self.configuration = configuration
    }

    func load() -> CommandWheelConfiguration { configuration }

    func save(_ configuration: CommandWheelConfiguration) {
        self.configuration = configuration
        saves += 1
    }

    func exportProfiles(ids: Set<UUID>?) throws -> Data {
        throw CommandWheelRepositoryError.noProfilesSelectedForExport
    }

    func importProfiles(
        from data: Data,
        knownCommandIDs: Set<CommandID>?
    ) throws -> CommandWheelImportResult {
        throw CommandWheelRepositoryError.malformedImport
    }

    func saveCount() -> Int { saves }
}

private actor SuspendedCommandWheelRepository: CommandWheelProfileRepository {
    private let loadResult: CommandWheelConfiguration
    private var saved: CommandWheelConfiguration?
    private var loads = 0
    private var didStart = false
    private var isReleased = false
    private var startWaiters: [CheckedContinuation<Void, Never>] = []
    private var releaseWaiters: [CheckedContinuation<Void, Never>] = []

    init(loadResult: CommandWheelConfiguration) {
        self.loadResult = loadResult
    }

    func load() async -> CommandWheelConfiguration {
        loads += 1
        didStart = true
        let waiters = startWaiters
        startWaiters.removeAll()
        for waiter in waiters { waiter.resume() }
        if isReleased == false {
            await withCheckedContinuation { continuation in
                releaseWaiters.append(continuation)
            }
        }
        return loadResult
    }

    func save(_ configuration: CommandWheelConfiguration) {
        saved = configuration
    }

    func exportProfiles(ids: Set<UUID>?) throws -> Data {
        throw CommandWheelRepositoryError.noProfilesSelectedForExport
    }

    func importProfiles(
        from data: Data,
        knownCommandIDs: Set<CommandID>?
    ) throws -> CommandWheelImportResult {
        throw CommandWheelRepositoryError.malformedImport
    }

    func waitUntilLoadStarts() async {
        if didStart { return }
        await withCheckedContinuation { continuation in
            startWaiters.append(continuation)
        }
    }

    func releaseLoad() {
        isReleased = true
        let waiters = releaseWaiters
        releaseWaiters.removeAll()
        for waiter in waiters { waiter.resume() }
    }

    func savedConfiguration() -> CommandWheelConfiguration? { saved }
    func loadCount() -> Int { loads }
}

private actor RecoverableFailedCommandWheelRepository: CommandWheelProfileRepository {
    private var saved: CommandWheelConfiguration?
    private var saves = 0

    func load() throws -> CommandWheelConfiguration {
        throw CommandWheelRepositoryError.corruptStorage
    }

    func save(_ configuration: CommandWheelConfiguration) {
        saved = configuration
        saves += 1
    }

    func exportProfiles(ids: Set<UUID>?) throws -> Data {
        throw CommandWheelRepositoryError.corruptStorage
    }

    func importProfiles(
        from data: Data,
        knownCommandIDs: Set<CommandID>?
    ) throws -> CommandWheelImportResult {
        throw CommandWheelRepositoryError.corruptStorage
    }

    func savedConfiguration() -> CommandWheelConfiguration? { saved }
    func saveCount() -> Int { saves }
}

@MainActor
private func makeSettingsModel(
    configuration: CommandWheelConfiguration,
    manifests: [CommandManifest],
    shortcutIssues: (@MainActor () -> [UUID: GlobalShortcutRegistrationIssue])? = nil
) -> CommandWheelSettingsModel {
    CommandWheelSettingsModel(
        store: CommandWheelProfileStore(
            repository: InMemoryCommandWheelProfileRepository(configuration: configuration)
        ),
        catalog: CommandWheelCommandCatalogSnapshot(manifests: manifests),
        shortcutIssues: shortcutIssues
    )
}

private nonisolated func testManifest(id: String, title: String) -> CommandManifest {
    CommandManifest(
        id: CommandID(rawValue: id),
        title: title,
        systemImage: "bolt.fill",
        category: .productivity,
        mode: .action
    )
}

private nonisolated func installedApplicationCatalog(
    availableBundleIdentifiers: Set<String>
) -> CommandWheelCommandCatalogSnapshot {
    CommandWheelCommandCatalogSnapshot(
        CommandCatalogSnapshot(
            manifests: [BuiltInCommandManifest.openInstalledApplication],
            availability: CommandAvailabilitySnapshot(
                installedApplicationBundleIdentifiers: availableBundleIdentifiers
            )
        )
    )
}

private nonisolated func emptyWheelConfiguration() -> CommandWheelConfiguration {
    var configuration = CommandWheelDefaults.configuration
    configuration.isEnabled = true
    for pageIndex in configuration.profiles[0].pages.indices {
        for segmentIndex in configuration.profiles[0].pages[pageIndex].segments.indices {
            configuration.profiles[0].pages[pageIndex].segments[segmentIndex].content = .empty
            configuration.profiles[0].pages[pageIndex].segments[segmentIndex].customLabel = nil
            configuration.profiles[0].pages[pageIndex].segments[segmentIndex].customIcon = nil
        }
    }
    return configuration
}

private nonisolated func segmentIDs(
    in configuration: CommandWheelConfiguration
) -> [Int: UUID] {
    Dictionary(
        uniqueKeysWithValues: configuration.profiles[0].pages[0].segments.map {
            ($0.slotIndex, $0.id)
        }
    )
}

private nonisolated func commandID(
    at slotIndex: Int,
    in configuration: CommandWheelConfiguration
) -> CommandID? {
    guard let segment = configuration.profiles[0].pages[0].segments.first(where: {
        $0.slotIndex == slotIndex
    }), case .command(let reference) = segment.content else {
        return nil
    }
    return reference.commandID
}
