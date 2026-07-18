import AppCore
import CommandKit
import Foundation
import Observation

nonisolated enum CommandWheelProfileStorePhase: Equatable, Sendable {
    case idle
    case loading
    case ready
    case failed
}

nonisolated enum CommandWheelProfileStoreError: LocalizedError, Equatable, Sendable {
    case mutationInProgress
    case validationFailed(CommandWheelValidationError)
    case repository(CommandWheelRepositoryError)
    case unavailable

    var errorDescription: String? {
        switch self {
        case .mutationInProgress:
            return "Another Command Wheel change is still being saved."
        case .validationFailed(let error):
            return error.errorDescription
        case .repository(let error):
            return error.errorDescription
        case .unavailable:
            return "Command Wheel settings are unavailable."
        }
    }
}

nonisolated enum CommandWheelProfileEditError: LocalizedError, Equatable, Sendable {
    case profileNotFound
    case pageNotFound
    case segmentNotFound
    case slotOutOfRange
    case slotOccupied
    case invalidName
    case identifierGenerationFailed

    var errorDescription: String? {
        switch self {
        case .profileNotFound:
            return "The selected wheel profile no longer exists."
        case .pageNotFound:
            return "The selected wheel page no longer exists."
        case .segmentNotFound:
            return "The selected wheel segment no longer exists."
        case .slotOutOfRange:
            return "The selected wheel slot is outside the current layout."
        case .slotOccupied:
            return "That wheel slot already contains an item."
        case .invalidName:
            return "Wheel profile and page names cannot be empty."
        case .identifierGenerationFailed:
            return "Command Wheel could not generate a unique identifier."
        }
    }
}

nonisolated struct CommandWheelSlotLocation: Codable, Hashable, Sendable {
    let profileID: UUID
    let pageID: UUID
    let slotIndex: Int
}

nonisolated struct CommandWheelCommandLocation: Hashable, Sendable {
    let location: CommandWheelSlotLocation
    let segmentID: UUID
    let profileName: String
    let pageName: String
    let reference: CommandReference
}

nonisolated struct CommandWheelOccupiedSlotMetadata: Hashable, Sendable {
    let location: CommandWheelSlotLocation
    let segmentID: UUID
    let content: CommandWheelSegmentContent
    let customLabel: String?
    let customIcon: CommandWheelIconOverride?
}

/// Main-actor cache shared by Settings and Command Wheel presentation.
///
/// Presentation code must read ``configurationSnapshot()`` and never load the repository. Settings
/// mutations validate a private candidate, persist it through the actor-backed repository, and only
/// then publish the new configuration and callback.
@Observable
@MainActor
final class CommandWheelProfileStore {
    private let repository: any CommandWheelProfileRepository
    private let validator: CommandWheelConfigurationValidator
    private let uuidProvider: any UUIDProviding

    @ObservationIgnored
    private var preloadTask: Task<CommandWheelConfiguration, any Error>?

    private(set) var configuration: CommandWheelConfiguration
    private(set) var phase: CommandWheelProfileStorePhase = .idle
    private(set) var isPersisting = false
    private(set) var errorMessage: String?

    @ObservationIgnored
    var onConfigurationChange: ((CommandWheelConfiguration) -> Void)?

    init(
        repository: any CommandWheelProfileRepository,
        initialConfiguration: CommandWheelConfiguration = CommandWheelDefaults.configuration,
        validator: CommandWheelConfigurationValidator = CommandWheelConfigurationValidator(),
        uuidProvider: any UUIDProviding = SystemUUIDProvider(),
        onConfigurationChange: ((CommandWheelConfiguration) -> Void)? = nil
    ) {
        self.repository = repository
        self.configuration = initialConfiguration
        self.validator = validator
        self.uuidProvider = uuidProvider
        self.onConfigurationChange = onConfigurationChange
    }

    /// Returns the in-memory configuration without repository or filesystem access.
    func configurationSnapshot() -> CommandWheelConfiguration {
        configuration
    }

    /// Loads durable state once. Concurrent callers coalesce on the same repository load.
    func preload() async {
        if phase == .ready { return }

        let task: Task<CommandWheelConfiguration, any Error>
        if phase == .loading, let preloadTask {
            task = preloadTask
        } else {
            phase = .loading
            errorMessage = nil
            let repository = self.repository
            let validator = self.validator
            task = Task {
                let loaded = try await repository.load()
                try validator.validate(loaded)
                return loaded
            }
            preloadTask = task
        }

        do {
            let loaded = try await task.value
            guard phase == .loading else { return }
            preloadTask = nil
            configuration = loaded
            phase = .ready
            onConfigurationChange?(loaded)
        } catch {
            guard phase == .loading else { return }
            preloadTask = nil
            phase = .failed
            errorMessage = sanitizedMessage(for: error)
        }
    }

    /// Commits one all-or-nothing edit after complete graph validation and durable persistence.
    func update(
        _ edit: (inout CommandWheelConfiguration) throws -> Void
    ) async throws {
        try await ensureReady()
        guard isPersisting == false else {
            throw CommandWheelProfileStoreError.mutationInProgress
        }

        var candidate = configuration
        try edit(&candidate)
        do {
            try validator.validate(candidate)
        } catch let error as CommandWheelValidationError {
            let mapped = CommandWheelProfileStoreError.validationFailed(error)
            errorMessage = mapped.errorDescription
            throw mapped
        }

        isPersisting = true
        errorMessage = nil
        defer { isPersisting = false }
        do {
            try await repository.save(candidate)
        } catch let error as CommandWheelRepositoryError {
            let mapped = CommandWheelProfileStoreError.repository(error)
            errorMessage = mapped.errorDescription
            throw mapped
        } catch {
            let mapped = CommandWheelProfileStoreError.unavailable
            errorMessage = mapped.errorDescription
            throw mapped
        }

        configuration = candidate
        phase = .ready
        onConfigurationChange?(candidate)
    }

    func exportProfiles(ids: Set<UUID>? = nil) async throws -> Data {
        try await ensureReady()
        do {
            return try await repository.exportProfiles(ids: ids)
        } catch let error as CommandWheelRepositoryError {
            let mapped = CommandWheelProfileStoreError.repository(error)
            errorMessage = mapped.errorDescription
            throw mapped
        } catch {
            let mapped = CommandWheelProfileStoreError.unavailable
            errorMessage = mapped.errorDescription
            throw mapped
        }
    }

    func importProfiles(
        from data: Data,
        knownCommandIDs: Set<CommandID>
    ) async throws -> CommandWheelImportResult {
        try await ensureReady()
        guard isPersisting == false else {
            throw CommandWheelProfileStoreError.mutationInProgress
        }
        isPersisting = true
        errorMessage = nil
        defer { isPersisting = false }

        do {
            let result = try await repository.importProfiles(
                from: data,
                knownCommandIDs: knownCommandIDs
            )
            let loaded = try await repository.load()
            try validator.validate(loaded)
            configuration = loaded
            phase = .ready
            onConfigurationChange?(loaded)
            return result
        } catch let error as CommandWheelRepositoryError {
            let mapped = CommandWheelProfileStoreError.repository(error)
            errorMessage = mapped.errorDescription
            throw mapped
        } catch let error as CommandWheelValidationError {
            let mapped = CommandWheelProfileStoreError.validationFailed(error)
            errorMessage = mapped.errorDescription
            throw mapped
        } catch {
            let mapped = CommandWheelProfileStoreError.unavailable
            errorMessage = mapped.errorDescription
            throw mapped
        }
    }

    func clearError() {
        errorMessage = nil
    }

    /// Replaces storage only after a failed load and an explicit user confirmation.
    ///
    /// Corrupt bytes and unsupported future schemas remain untouched until this method is called.
    func replaceCorruptStorageWithDefaults() async throws {
        guard phase == .failed else { return }
        guard isPersisting == false else {
            throw CommandWheelProfileStoreError.mutationInProgress
        }
        let defaults = CommandWheelDefaults.configuration
        do {
            try validator.validate(defaults)
        } catch let error as CommandWheelValidationError {
            throw CommandWheelProfileStoreError.validationFailed(error)
        }

        isPersisting = true
        defer { isPersisting = false }
        do {
            try await repository.save(defaults)
        } catch let error as CommandWheelRepositoryError {
            let mapped = CommandWheelProfileStoreError.repository(error)
            errorMessage = mapped.errorDescription
            throw mapped
        } catch {
            errorMessage = CommandWheelProfileStoreError.unavailable.errorDescription
            throw CommandWheelProfileStoreError.unavailable
        }
        configuration = defaults
        phase = .ready
        errorMessage = nil
        onConfigurationChange?(defaults)
    }

    func locations(for reference: CommandReference) -> [CommandWheelCommandLocation] {
        commandLocations { $0 == reference }
    }

    func locations(for commandID: CommandID) -> [CommandWheelCommandLocation] {
        commandLocations { $0.commandID == commandID }
    }

    func occupiedSlot(
        profileID: UUID,
        pageID: UUID,
        slotIndex: Int
    ) -> CommandWheelOccupiedSlotMetadata? {
        guard let profile = configuration.profiles.first(where: { $0.id == profileID }),
              let page = profile.pages.first(where: { $0.id == pageID }),
              let segment = page.segments.first(where: { $0.slotIndex == slotIndex }),
              segment.content != .empty else {
            return nil
        }
        return CommandWheelOccupiedSlotMetadata(
            location: CommandWheelSlotLocation(
                profileID: profileID,
                pageID: pageID,
                slotIndex: slotIndex
            ),
            segmentID: segment.id,
            content: segment.content,
            customLabel: segment.customLabel,
            customIcon: segment.customIcon
        )
    }

    func assign(
        _ reference: CommandReference,
        to location: CommandWheelSlotLocation,
        replacing: Bool
    ) async throws {
        try await assign(
            reference,
            to: location,
            replacing: replacing,
            customLabel: nil
        )
    }

    /// Assigns an exact command reference with optional non-secret display metadata.
    func assign(
        _ reference: CommandReference,
        to location: CommandWheelSlotLocation,
        replacing: Bool,
        customLabel: String?
    ) async throws {
        try await update { configuration in
            try Self.setContent(
                .command(reference),
                customLabel: customLabel,
                customIcon: nil,
                at: location,
                replacing: replacing,
                configuration: &configuration,
                uuidProvider: uuidProvider
            )
        }
    }

    func assignContent(
        _ content: CommandWheelSegmentContent,
        to location: CommandWheelSlotLocation,
        replacing: Bool
    ) async throws {
        try await update { configuration in
            try Self.setContent(
                content,
                customLabel: nil,
                customIcon: nil,
                at: location,
                replacing: replacing,
                configuration: &configuration,
                uuidProvider: uuidProvider
            )
        }
    }

    func move(
        from source: CommandWheelSlotLocation,
        to destination: CommandWheelSlotLocation,
        replacing: Bool
    ) async throws {
        guard source != destination else { return }
        try await update { configuration in
            let sourceValue = try Self.segment(at: source, in: configuration)
            try Self.setContent(
                sourceValue.content,
                customLabel: sourceValue.customLabel,
                customIcon: sourceValue.customIcon,
                at: destination,
                replacing: replacing,
                configuration: &configuration,
                uuidProvider: uuidProvider
            )
            try Self.setContent(
                .empty,
                customLabel: nil,
                customIcon: nil,
                at: source,
                replacing: true,
                configuration: &configuration,
                uuidProvider: uuidProvider,
                removesReplacedSubmenuTree: false
            )
        }
    }

    /// Atomically swaps two stable slots without deleting either slot's submenu tree.
    func swap(
        _ first: CommandWheelSlotLocation,
        _ second: CommandWheelSlotLocation
    ) async throws {
        guard first != second else { return }
        guard first.profileID == second.profileID,
              first.pageID == second.pageID else {
            throw CommandWheelProfileEditError.pageNotFound
        }
        try await update { configuration in
            let firstValue = try Self.segment(at: first, in: configuration)
            let secondValue = try Self.segment(at: second, in: configuration)
            try Self.setContent(
                firstValue.content,
                customLabel: firstValue.customLabel,
                customIcon: firstValue.customIcon,
                at: second,
                replacing: true,
                configuration: &configuration,
                uuidProvider: uuidProvider,
                removesReplacedSubmenuTree: false
            )
            try Self.setContent(
                secondValue.content,
                customLabel: secondValue.customLabel,
                customIcon: secondValue.customIcon,
                at: first,
                replacing: true,
                configuration: &configuration,
                uuidProvider: uuidProvider,
                removesReplacedSubmenuTree: false
            )
        }
    }

    func remove(at location: CommandWheelSlotLocation) async throws {
        try await update { configuration in
            _ = try Self.segment(at: location, in: configuration)
            try Self.setContent(
                .empty,
                customLabel: nil,
                customIcon: nil,
                at: location,
                replacing: true,
                configuration: &configuration,
                uuidProvider: uuidProvider
            )
        }
    }

    @discardableResult
    func createSubmenu(
        named name: String,
        at location: CommandWheelSlotLocation,
        replacing: Bool
    ) async throws -> UUID {
        let normalized = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalized.isEmpty == false else {
            throw CommandWheelProfileEditError.invalidName
        }
        var createdPageID: UUID?
        try await update { configuration in
            guard let profileIndex = configuration.profiles.firstIndex(where: {
                $0.id == location.profileID
            }) else {
                throw CommandWheelProfileEditError.profileNotFound
            }
            guard configuration.profiles[profileIndex].pages.contains(where: {
                $0.id == location.pageID
            }) else {
                throw CommandWheelProfileEditError.pageNotFound
            }
            let pageID = try Self.nextUniqueID(
                in: configuration,
                uuidProvider: uuidProvider
            )
            configuration.profiles[profileIndex].pages.append(
                CommandWheelPage(id: pageID, name: normalized, segments: [])
            )
            try Self.populateStableEmptySegments(
                pageID: pageID,
                profileID: location.profileID,
                configuration: &configuration,
                uuidProvider: uuidProvider
            )
            try Self.setContent(
                .submenu(pageID: pageID),
                customLabel: nil,
                customIcon: nil,
                at: location,
                replacing: replacing,
                configuration: &configuration,
                uuidProvider: uuidProvider
            )
            createdPageID = pageID
        }
        guard let createdPageID else {
            throw CommandWheelProfileEditError.identifierGenerationFailed
        }
        return createdPageID
    }

    /// Creates a submenu and places a command in it with one validated repository save.
    @discardableResult
    func createSubmenu(
        named name: String,
        at location: CommandWheelSlotLocation,
        replacing: Bool,
        containing reference: CommandReference,
        atChildSlotIndex childSlotIndex: Int = 0
    ) async throws -> UUID {
        try await createSubmenu(
            named: name,
            at: location,
            replacing: replacing,
            containing: reference,
            atChildSlotIndex: childSlotIndex,
            customLabel: nil
        )
    }

    /// Creates a submenu and preserves optional display metadata for its contained command.
    @discardableResult
    func createSubmenu(
        named name: String,
        at location: CommandWheelSlotLocation,
        replacing: Bool,
        containing reference: CommandReference,
        atChildSlotIndex childSlotIndex: Int = 0,
        customLabel: String?
    ) async throws -> UUID {
        let normalized = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalized.isEmpty == false else {
            throw CommandWheelProfileEditError.invalidName
        }
        var createdPageID: UUID?
        try await update { configuration in
            guard let profileIndex = configuration.profiles.firstIndex(where: {
                $0.id == location.profileID
            }) else {
                throw CommandWheelProfileEditError.profileNotFound
            }
            guard configuration.profiles[profileIndex].pages.contains(where: {
                $0.id == location.pageID
            }) else {
                throw CommandWheelProfileEditError.pageNotFound
            }
            let slotCount = configuration.profiles[profileIndex].interaction.visibleSlotCount
            guard (0 ..< slotCount).contains(childSlotIndex) else {
                throw CommandWheelProfileEditError.slotOutOfRange
            }

            let pageID = try Self.nextUniqueID(
                in: configuration,
                uuidProvider: uuidProvider
            )
            configuration.profiles[profileIndex].pages.append(
                CommandWheelPage(id: pageID, name: normalized, segments: [])
            )
            try Self.populateStableEmptySegments(
                pageID: pageID,
                profileID: location.profileID,
                configuration: &configuration,
                uuidProvider: uuidProvider
            )
            try Self.setContent(
                .submenu(pageID: pageID),
                customLabel: nil,
                customIcon: nil,
                at: location,
                replacing: replacing,
                configuration: &configuration,
                uuidProvider: uuidProvider
            )
            try Self.setContent(
                .command(reference),
                customLabel: customLabel,
                customIcon: nil,
                at: CommandWheelSlotLocation(
                    profileID: location.profileID,
                    pageID: pageID,
                    slotIndex: childSlotIndex
                ),
                replacing: true,
                configuration: &configuration,
                uuidProvider: uuidProvider
            )
            createdPageID = pageID
        }
        guard let createdPageID else {
            throw CommandWheelProfileEditError.identifierGenerationFailed
        }
        return createdPageID
    }

    func setVisibleSlotCount(_ count: Int, profileID: UUID) async throws {
        guard (1 ... CommandWheelLimits.maximumVisibleSlots).contains(count) else {
            throw CommandWheelProfileEditError.slotOutOfRange
        }
        try await update { configuration in
            guard let profileIndex = configuration.profiles.firstIndex(where: {
                $0.id == profileID
            }) else {
                throw CommandWheelProfileEditError.profileNotFound
            }
            try Self.synchronizeVisibleSlots(
                count,
                profileIndex: profileIndex,
                configuration: &configuration,
                uuidProvider: uuidProvider
            )
            configuration.profiles[profileIndex].interaction.visibleSlotCount = count
        }
    }

    func setInteractionConfiguration(
        _ interaction: CommandWheelInteractionConfiguration,
        profileID: UUID
    ) async throws {
        let count = interaction.visibleSlotCount
        guard (1 ... CommandWheelLimits.maximumVisibleSlots).contains(count) else {
            throw CommandWheelProfileEditError.slotOutOfRange
        }
        try await update { configuration in
            guard let profileIndex = configuration.profiles.firstIndex(where: {
                $0.id == profileID
            }) else {
                throw CommandWheelProfileEditError.profileNotFound
            }
            try Self.synchronizeVisibleSlots(
                count,
                profileIndex: profileIndex,
                configuration: &configuration,
                uuidProvider: uuidProvider
            )
            configuration.profiles[profileIndex].interaction = interaction
        }
    }

    private func sanitizedMessage(for error: any Error) -> String {
        if let error = error as? CommandWheelRepositoryError {
            return error.errorDescription ?? "Command Wheel settings are unavailable."
        }
        if let error = error as? CommandWheelValidationError {
            return error.errorDescription ?? "Command Wheel settings are invalid."
        }
        return "Command Wheel settings are unavailable."
    }

    private func commandLocations(
        matching predicate: (CommandReference) -> Bool
    ) -> [CommandWheelCommandLocation] {
        configuration.profiles.flatMap { profile in
            profile.pages.flatMap { page in
                page.segments.compactMap { segment in
                    guard case .command(let reference) = segment.content,
                          predicate(reference) else {
                        return nil
                    }
                    return CommandWheelCommandLocation(
                        location: CommandWheelSlotLocation(
                            profileID: profile.id,
                            pageID: page.id,
                            slotIndex: segment.slotIndex
                        ),
                        segmentID: segment.id,
                        profileName: profile.name,
                        pageName: page.name,
                        reference: reference
                    )
                }
            }
        }
    }

    private func uniqueID() throws -> UUID {
        try Self.nextUniqueID(in: configuration, uuidProvider: uuidProvider)
    }

    private func ensureReady() async throws {
        if phase != .ready { await preload() }
        guard phase == .ready else {
            throw CommandWheelProfileStoreError.unavailable
        }
    }

    private nonisolated static func segment(
        at location: CommandWheelSlotLocation,
        in configuration: CommandWheelConfiguration
    ) throws -> CommandWheelSegment {
        guard let profile = configuration.profiles.first(where: {
            $0.id == location.profileID
        }) else {
            throw CommandWheelProfileEditError.profileNotFound
        }
        guard (0 ..< profile.interaction.visibleSlotCount).contains(location.slotIndex) else {
            throw CommandWheelProfileEditError.slotOutOfRange
        }
        guard let page = profile.pages.first(where: { $0.id == location.pageID }) else {
            throw CommandWheelProfileEditError.pageNotFound
        }
        guard let segment = page.segments.first(where: {
            $0.slotIndex == location.slotIndex
        }) else {
            throw CommandWheelProfileEditError.segmentNotFound
        }
        return segment
    }

    private nonisolated static func setContent(
        _ content: CommandWheelSegmentContent,
        customLabel: String?,
        customIcon: CommandWheelIconOverride?,
        at location: CommandWheelSlotLocation,
        replacing: Bool,
        configuration: inout CommandWheelConfiguration,
        uuidProvider: any UUIDProviding,
        removesReplacedSubmenuTree: Bool = true
    ) throws {
        guard let profileIndex = configuration.profiles.firstIndex(where: {
            $0.id == location.profileID
        }) else {
            throw CommandWheelProfileEditError.profileNotFound
        }
        let slotCount = configuration.profiles[profileIndex].interaction.visibleSlotCount
        guard (0 ..< slotCount).contains(location.slotIndex) else {
            throw CommandWheelProfileEditError.slotOutOfRange
        }
        guard let pageIndex = configuration.profiles[profileIndex].pages.firstIndex(where: {
            $0.id == location.pageID
        }) else {
            throw CommandWheelProfileEditError.pageNotFound
        }
        let segmentIndex = configuration.profiles[profileIndex].pages[pageIndex]
            .segments.firstIndex(where: { $0.slotIndex == location.slotIndex })

        if let segmentIndex {
            let existing = configuration.profiles[profileIndex].pages[pageIndex]
                .segments[segmentIndex]
            if existing.content != .empty, content != .empty, replacing == false {
                throw CommandWheelProfileEditError.slotOccupied
            }
            let removedSubmenuRoot: UUID?
            if removesReplacedSubmenuTree,
               case .submenu(let existingPageID) = existing.content,
               existing.content != content {
                removedSubmenuRoot = existingPageID
            } else {
                removedSubmenuRoot = nil
            }
            configuration.profiles[profileIndex].pages[pageIndex].segments[segmentIndex]
                .content = content
            configuration.profiles[profileIndex].pages[pageIndex].segments[segmentIndex]
                .customLabel = customLabel
            configuration.profiles[profileIndex].pages[pageIndex].segments[segmentIndex]
                .customIcon = customIcon
            if let removedSubmenuRoot {
                Self.removeSubmenuTree(
                    rootedAt: removedSubmenuRoot,
                    profileIndex: profileIndex,
                    configuration: &configuration
                )
            }
        } else {
            configuration.profiles[profileIndex].pages[pageIndex].segments.append(
                CommandWheelSegment(
                    id: try nextUniqueID(
                        in: configuration,
                        uuidProvider: uuidProvider
                    ),
                    slotIndex: location.slotIndex,
                    content: content,
                    customLabel: customLabel,
                    customIcon: customIcon
                )
            )
        }
    }

    private nonisolated static func removeSubmenuTree(
        rootedAt rootPageID: UUID,
        profileIndex: Int,
        configuration: inout CommandWheelConfiguration
    ) {
        let pages = configuration.profiles[profileIndex].pages
        var removedIDs: Set<UUID> = []

        func collect(_ pageID: UUID) {
            guard removedIDs.insert(pageID).inserted,
                  let page = pages.first(where: { $0.id == pageID }) else {
                return
            }
            for segment in page.segments {
                if case .submenu(let childID) = segment.content {
                    collect(childID)
                }
            }
        }

        collect(rootPageID)
        configuration.profiles[profileIndex].pages.removeAll {
            removedIDs.contains($0.id)
        }
    }

    private nonisolated static func populateStableEmptySegments(
        pageID: UUID,
        profileID: UUID,
        configuration: inout CommandWheelConfiguration,
        uuidProvider: any UUIDProviding
    ) throws {
        guard let profileIndex = configuration.profiles.firstIndex(where: {
            $0.id == profileID
        }) else {
            throw CommandWheelProfileEditError.profileNotFound
        }
        guard let pageIndex = configuration.profiles[profileIndex].pages.firstIndex(where: {
            $0.id == pageID
        }) else {
            throw CommandWheelProfileEditError.pageNotFound
        }
        let slotCount = configuration.profiles[profileIndex].interaction.visibleSlotCount
        for slotIndex in 0 ..< slotCount {
            let segmentID = try nextUniqueID(
                in: configuration,
                uuidProvider: uuidProvider
            )
            configuration.profiles[profileIndex].pages[pageIndex].segments.append(
                CommandWheelSegment(
                    id: segmentID,
                    slotIndex: slotIndex,
                    content: .empty,
                    customLabel: nil,
                    customIcon: nil
                )
            )
        }
    }

    private nonisolated static func synchronizeVisibleSlots(
        _ count: Int,
        profileIndex: Int,
        configuration: inout CommandWheelConfiguration,
        uuidProvider: any UUIDProviding
    ) throws {
        let discardedSubmenuRoots = configuration.profiles[profileIndex].pages
            .flatMap(\.segments)
            .filter { $0.slotIndex >= count }
            .compactMap { segment -> UUID? in
                guard case .submenu(let pageID) = segment.content else { return nil }
                return pageID
            }
        for pageIndex in configuration.profiles[profileIndex].pages.indices {
            configuration.profiles[profileIndex].pages[pageIndex].segments.removeAll {
                $0.slotIndex >= count
            }
        }
        for pageID in discardedSubmenuRoots {
            removeSubmenuTree(
                rootedAt: pageID,
                profileIndex: profileIndex,
                configuration: &configuration
            )
        }

        for pageIndex in configuration.profiles[profileIndex].pages.indices {
            let occupiedSlots = Set(
                configuration.profiles[profileIndex].pages[pageIndex]
                    .segments.map(\.slotIndex)
            )
            for slotIndex in 0 ..< count where occupiedSlots.contains(slotIndex) == false {
                let segmentID = try nextUniqueID(
                    in: configuration,
                    uuidProvider: uuidProvider
                )
                configuration.profiles[profileIndex].pages[pageIndex].segments.append(
                    CommandWheelSegment(
                        id: segmentID,
                        slotIndex: slotIndex,
                        content: .empty,
                        customLabel: nil,
                        customIcon: nil
                    )
                )
            }
        }
    }

    private nonisolated static func nextUniqueID(
        in configuration: CommandWheelConfiguration,
        uuidProvider: any UUIDProviding
    ) throws -> UUID {
        let used = Set(configuration.profiles.map(\.id))
            .union(configuration.profiles.flatMap(\.pages).map(\.id))
            .union(
                configuration.profiles
                    .flatMap(\.pages)
                    .flatMap(\.segments)
                    .map(\.id)
            )
            .union(configuration.profiles.flatMap(\.contextRules).map(\.id))
        for _ in 0 ..< 256 {
            let candidate = uuidProvider.uuid()
            if used.contains(candidate) == false { return candidate }
        }
        throw CommandWheelProfileEditError.identifierGenerationFailed
    }
}
