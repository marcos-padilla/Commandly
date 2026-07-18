import CommandKit
import Foundation
import Observation

/// Focused mutation boundary used by launcher search's Command Wheel assignment flow.
///
/// Every mutating requirement maps to one validated, durable store transaction. In particular,
/// creating a submenu and placing the selected command inside it must never be split across saves.
@MainActor
protocol CommandWheelAssignmentStoring: AnyObject {
    /// Ensures the snapshot used to build an assignment destination is the durable configuration.
    func prepareForAssignment() async -> Bool
    func configurationSnapshot() -> CommandWheelConfiguration
    func locations(for reference: CommandReference) -> [CommandWheelCommandLocation]
    func occupiedSlot(
        profileID: UUID,
        pageID: UUID,
        slotIndex: Int
    ) -> CommandWheelOccupiedSlotMetadata?
    func assign(
        _ reference: CommandReference,
        to location: CommandWheelSlotLocation,
        replacing: Bool
    ) async throws
    func assign(
        _ reference: CommandReference,
        to location: CommandWheelSlotLocation,
        replacing: Bool,
        customLabel: String?
    ) async throws
    func move(
        from source: CommandWheelSlotLocation,
        to destination: CommandWheelSlotLocation,
        replacing: Bool
    ) async throws
    func remove(at location: CommandWheelSlotLocation) async throws
    @discardableResult
    func createSubmenu(
        named name: String,
        at location: CommandWheelSlotLocation,
        replacing: Bool,
        containing reference: CommandReference,
        atChildSlotIndex childSlotIndex: Int
    ) async throws -> UUID
    @discardableResult
    func createSubmenu(
        named name: String,
        at location: CommandWheelSlotLocation,
        replacing: Bool,
        containing reference: CommandReference,
        atChildSlotIndex childSlotIndex: Int,
        customLabel: String?
    ) async throws -> UUID
}

extension CommandWheelAssignmentStoring {
    func prepareForAssignment() async -> Bool { true }

    func assign(
        _ reference: CommandReference,
        to location: CommandWheelSlotLocation,
        replacing: Bool,
        customLabel _: String?
    ) async throws {
        try await assign(reference, to: location, replacing: replacing)
    }

    func createSubmenu(
        named name: String,
        at location: CommandWheelSlotLocation,
        replacing: Bool,
        containing reference: CommandReference,
        atChildSlotIndex childSlotIndex: Int,
        customLabel _: String?
    ) async throws -> UUID {
        try await createSubmenu(
            named: name,
            at: location,
            replacing: replacing,
            containing: reference,
            atChildSlotIndex: childSlotIndex
        )
    }
}

extension CommandWheelProfileStore: CommandWheelAssignmentStoring {
    func prepareForAssignment() async -> Bool {
        await preload()
        return phase == .ready
    }
}

nonisolated struct CommandWheelAssignmentProfileOption: Identifiable, Equatable, Sendable {
    let id: UUID
    let name: String
}

nonisolated struct CommandWheelAssignmentPageOption: Identifiable, Equatable, Sendable {
    let id: UUID
    let name: String
}

nonisolated struct CommandWheelAssignmentSlotOption: Identifiable, Equatable, Sendable {
    let id: Int
    let title: String
    let detail: String
    let isOccupied: Bool
}

nonisolated struct CommandWheelExistingAssignment: Identifiable, Equatable, Sendable {
    let id: UUID
    let location: CommandWheelSlotLocation
    let profileName: String
    let pageName: String
    let reference: CommandReference

    var locationDescription: String {
        "\(profileName) › \(pageName) › Slot \(location.slotIndex + 1)"
    }
}

nonisolated enum CommandWheelAssignmentPendingAction: Identifiable, Equatable, Sendable {
    case replaceAssignment(destination: CommandWheelSlotLocation, occupiedDescription: String)
    case replaceMove(
        source: CommandWheelSlotLocation,
        destination: CommandWheelSlotLocation,
        occupiedDescription: String
    )
    case remove(source: CommandWheelSlotLocation, locationDescription: String)
    case replaceWithSubmenu(
        name: String,
        destination: CommandWheelSlotLocation,
        childSlotIndex: Int,
        occupiedDescription: String
    )

    var id: String {
        switch self {
        case .replaceAssignment(let destination, _):
            return "assign-\(Self.locationID(destination))"
        case .replaceMove(let source, let destination, _):
            return "move-\(Self.locationID(source))-\(Self.locationID(destination))"
        case .remove(let source, _):
            return "remove-\(Self.locationID(source))"
        case .replaceWithSubmenu(let name, let destination, let childSlotIndex, _):
            return "submenu-\(name)-\(Self.locationID(destination))-\(childSlotIndex)"
        }
    }

    var title: String {
        switch self {
        case .replaceAssignment, .replaceMove, .replaceWithSubmenu:
            return "Replace occupied slot?"
        case .remove:
            return "Remove assignment?"
        }
    }

    var message: String {
        switch self {
        case .replaceAssignment(_, let occupiedDescription),
             .replaceMove(_, _, let occupiedDescription),
             .replaceWithSubmenu(_, _, _, let occupiedDescription):
            return "This replaces \(occupiedDescription). This change cannot be undone."
        case .remove(_, let locationDescription):
            return "Remove this command from \(locationDescription)?"
        }
    }

    var confirmationTitle: String {
        switch self {
        case .remove: return "Remove"
        case .replaceAssignment, .replaceMove, .replaceWithSubmenu: return "Replace"
        }
    }

    private static func locationID(_ location: CommandWheelSlotLocation) -> String {
        "\(location.profileID.uuidString)-\(location.pageID.uuidString)-\(location.slotIndex)"
    }
}

/// Testable state and all-or-nothing mutations for assigning one exact command reference.
@Observable
@MainActor
final class CommandWheelAssignmentModel: Identifiable {
    let id = UUID()
    let reference: CommandReference
    let commandTitle: String
    let commandSystemImage: String

    private let store: any CommandWheelAssignmentStoring
    @ObservationIgnored
    private let reportStatus: @MainActor (String) -> Void
    @ObservationIgnored
    private let revealAssignmentHandler: @MainActor (CommandWheelSlotLocation) -> Void

    var selectedProfileID: UUID
    var selectedPageID: UUID
    var selectedSlotIndex: Int
    var newSubmenuName = ""
    var newSubmenuChildSlotIndex = 0
    private(set) var isSaving = false
    private(set) var errorMessage: String?
    var pendingAction: CommandWheelAssignmentPendingAction?

    init?(
        reference: CommandReference,
        commandTitle: String,
        commandSystemImage: String,
        store: (any CommandWheelAssignmentStoring)?,
        reportStatus: @escaping @MainActor (String) -> Void,
        revealAssignment: @escaping @MainActor (CommandWheelSlotLocation) -> Void
    ) {
        guard let store else { return nil }
        let configuration = store.configurationSnapshot()
        guard let profile = Self.initialProfile(in: configuration),
              let page = profile.pages.first(where: { $0.id == profile.rootPageID })
                ?? profile.pages.first else {
            return nil
        }
        self.reference = reference
        self.commandTitle = commandTitle
        self.commandSystemImage = commandSystemImage
        self.store = store
        self.reportStatus = reportStatus
        self.revealAssignmentHandler = revealAssignment
        self.selectedProfileID = profile.id
        self.selectedPageID = page.id
        self.selectedSlotIndex = Self.preferredSlotIndex(in: page, profile: profile)
    }

    var profiles: [CommandWheelAssignmentProfileOption] {
        store.configurationSnapshot().profiles.map {
            CommandWheelAssignmentProfileOption(id: $0.id, name: $0.name)
        }
    }

    var pages: [CommandWheelAssignmentPageOption] {
        guard let profile = selectedProfile else { return [] }
        return profile.pages.map {
            CommandWheelAssignmentPageOption(id: $0.id, name: $0.name)
        }
    }

    var slots: [CommandWheelAssignmentSlotOption] {
        guard let profile = selectedProfile else { return [] }
        return (0 ..< profile.interaction.visibleSlotCount).map { slotIndex in
            let metadata = store.occupiedSlot(
                profileID: profile.id,
                pageID: selectedPageID,
                slotIndex: slotIndex
            )
            return CommandWheelAssignmentSlotOption(
                id: slotIndex,
                title: "Slot \(slotIndex + 1)",
                detail: metadata.map(describe) ?? "Empty",
                isOccupied: metadata != nil
            )
        }
    }

    var childSlots: [CommandWheelAssignmentSlotOption] {
        guard let profile = selectedProfile else { return [] }
        return (0 ..< profile.interaction.visibleSlotCount).map {
            CommandWheelAssignmentSlotOption(
                id: $0,
                title: "Slot \($0 + 1)",
                detail: "New submenu",
                isOccupied: false
            )
        }
    }

    var existingAssignments: [CommandWheelExistingAssignment] {
        store.locations(for: reference).map {
            CommandWheelExistingAssignment(
                id: $0.segmentID,
                location: $0.location,
                profileName: $0.profileName,
                pageName: $0.pageName,
                reference: $0.reference
            )
        }
    }

    var selectedLocation: CommandWheelSlotLocation? {
        guard let profile = selectedProfile,
              profile.pages.contains(where: { $0.id == selectedPageID }),
              (0 ..< profile.interaction.visibleSlotCount).contains(selectedSlotIndex) else {
            return nil
        }
        return CommandWheelSlotLocation(
            profileID: selectedProfileID,
            pageID: selectedPageID,
            slotIndex: selectedSlotIndex
        )
    }

    var selectedSlotDescription: String {
        guard let location = selectedLocation,
              let metadata = store.occupiedSlot(
                  profileID: location.profileID,
                  pageID: location.pageID,
                  slotIndex: location.slotIndex
              ) else {
            return "Empty slot"
        }
        return "Occupied by \(describe(metadata))"
    }

    var selectedSlotIsOccupied: Bool {
        guard let location = selectedLocation else { return false }
        return store.occupiedSlot(
            profileID: location.profileID,
            pageID: location.pageID,
            slotIndex: location.slotIndex
        ) != nil
    }

    func selectProfile(_ profileID: UUID) {
        guard let profile = store.configurationSnapshot().profiles.first(where: {
            $0.id == profileID
        }), let page = profile.pages.first(where: { $0.id == profile.rootPageID })
            ?? profile.pages.first else {
            return
        }
        selectedProfileID = profileID
        selectedPageID = page.id
        selectedSlotIndex = Self.preferredSlotIndex(in: page, profile: profile)
        newSubmenuChildSlotIndex = 0
        clearTransientState()
    }

    func selectPage(_ pageID: UUID) {
        guard let profile = selectedProfile,
              let page = profile.pages.first(where: { $0.id == pageID }) else {
            return
        }
        selectedPageID = pageID
        selectedSlotIndex = Self.preferredSlotIndex(in: page, profile: profile)
        clearTransientState()
    }

    func selectSlot(_ slotIndex: Int) {
        guard let profile = selectedProfile,
              (0 ..< profile.interaction.visibleSlotCount).contains(slotIndex) else {
            return
        }
        selectedSlotIndex = slotIndex
        clearTransientState()
    }

    /// Adds the exact reference or requests explicit replacement when the target is occupied.
    @discardableResult
    func requestAssignment() async -> Bool {
        guard let destination = selectedLocation else {
            return fail("Choose a valid Command Wheel slot.")
        }
        if let occupied = occupiedDescription(at: destination) {
            pendingAction = .replaceAssignment(
                destination: destination,
                occupiedDescription: occupied
            )
            return false
        }
        return await performAssignment(to: destination, replacing: false)
    }

    /// Moves one exact existing assignment to the currently selected destination.
    @discardableResult
    func requestMove(from source: CommandWheelSlotLocation) async -> Bool {
        guard existingAssignments.contains(where: { $0.location == source }) else {
            return fail("That Command Wheel assignment no longer exists.")
        }
        guard let destination = selectedLocation else {
            return fail("Choose a valid destination slot.")
        }
        guard source != destination else {
            return fail("Choose a different destination slot.")
        }
        if let occupied = occupiedDescription(at: destination) {
            pendingAction = .replaceMove(
                source: source,
                destination: destination,
                occupiedDescription: occupied
            )
            return false
        }
        return await performMove(from: source, to: destination, replacing: false)
    }

    func requestRemoval(of assignment: CommandWheelExistingAssignment) {
        pendingAction = .remove(
            source: assignment.location,
            locationDescription: assignment.locationDescription
        )
    }

    /// Creates a child page and places the exact reference inside it in one store transaction.
    @discardableResult
    func requestNewSubmenu() async -> Bool {
        let name = newSubmenuName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard name.isEmpty == false else {
            return fail("Enter a name for the new submenu.")
        }
        guard let destination = selectedLocation,
              childSlots.contains(where: { $0.id == newSubmenuChildSlotIndex }) else {
            return fail("Choose valid parent and child slots.")
        }
        if let occupied = occupiedDescription(at: destination) {
            pendingAction = .replaceWithSubmenu(
                name: name,
                destination: destination,
                childSlotIndex: newSubmenuChildSlotIndex,
                occupiedDescription: occupied
            )
            return false
        }
        return await performNewSubmenu(
            named: name,
            at: destination,
            childSlotIndex: newSubmenuChildSlotIndex,
            replacing: false
        )
    }

    @discardableResult
    func confirmPendingAction(
        _ presentedAction: CommandWheelAssignmentPendingAction? = nil
    ) async -> Bool {
        guard let action = presentedAction ?? pendingAction else { return false }
        pendingAction = nil
        switch action {
        case .replaceAssignment(let destination, _):
            return await performAssignment(to: destination, replacing: true)
        case .replaceMove(let source, let destination, _):
            return await performMove(from: source, to: destination, replacing: true)
        case .remove(let source, _):
            return await performRemoval(at: source)
        case .replaceWithSubmenu(let name, let destination, let childSlotIndex, _):
            return await performNewSubmenu(
                named: name,
                at: destination,
                childSlotIndex: childSlotIndex,
                replacing: true
            )
        }
    }

    func cancelPendingAction() {
        pendingAction = nil
    }

    func reveal(_ assignment: CommandWheelExistingAssignment) {
        revealAssignmentHandler(assignment.location)
    }

    private var selectedProfile: CommandWheelProfile? {
        store.configurationSnapshot().profiles.first(where: { $0.id == selectedProfileID })
    }

    private func performAssignment(
        to destination: CommandWheelSlotLocation,
        replacing: Bool
    ) async -> Bool {
        await performMutation(successMessage: replacing
            ? "Replaced the occupied slot with \(commandTitle)."
            : "Added \(commandTitle) to Command Wheel."
        ) {
            try await store.assign(
                reference,
                to: destination,
                replacing: replacing,
                customLabel: persistedDisplayName
            )
        }
    }

    private func performMove(
        from source: CommandWheelSlotLocation,
        to destination: CommandWheelSlotLocation,
        replacing: Bool
    ) async -> Bool {
        await performMutation(successMessage: "Moved \(commandTitle) in Command Wheel.") {
            try await store.move(from: source, to: destination, replacing: replacing)
        }
    }

    private func performRemoval(at location: CommandWheelSlotLocation) async -> Bool {
        await performMutation(successMessage: "Removed \(commandTitle) from Command Wheel.") {
            try await store.remove(at: location)
        }
    }

    private func performNewSubmenu(
        named name: String,
        at destination: CommandWheelSlotLocation,
        childSlotIndex: Int,
        replacing: Bool
    ) async -> Bool {
        await performMutation(
            successMessage: "Created \(name) and added \(commandTitle) to it."
        ) {
            try await store.createSubmenu(
                named: name,
                at: destination,
                replacing: replacing,
                containing: reference,
                atChildSlotIndex: childSlotIndex,
                customLabel: persistedDisplayName
            )
        }
    }

    private var persistedDisplayName: String? {
        reference.commandID == BuiltInCommandID.openInstalledApplication
            ? commandTitle
            : nil
    }

    private func performMutation(
        successMessage: String,
        operation: () async throws -> Void
    ) async -> Bool {
        guard isSaving == false else { return false }
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }
        do {
            try await operation()
            reportStatus(successMessage)
            normalizeSelectionAfterMutation()
            return true
        } catch is CancellationError {
            return fail("Command Wheel change was cancelled.")
        } catch let error as LocalizedError {
            return fail(error.errorDescription ?? "Command Wheel settings could not be saved.")
        } catch {
            return fail("Command Wheel settings could not be saved.")
        }
    }

    @discardableResult
    private func fail(_ message: String) -> Bool {
        errorMessage = message
        reportStatus(message)
        return false
    }

    private func normalizeSelectionAfterMutation() {
        let configuration = store.configurationSnapshot()
        guard let profile = configuration.profiles.first(where: { $0.id == selectedProfileID })
                ?? Self.initialProfile(in: configuration),
              let page = profile.pages.first(where: { $0.id == selectedPageID })
                ?? profile.pages.first(where: { $0.id == profile.rootPageID })
                ?? profile.pages.first else {
            return
        }
        selectedProfileID = profile.id
        selectedPageID = page.id
        selectedSlotIndex = min(
            max(selectedSlotIndex, 0),
            max(profile.interaction.visibleSlotCount - 1, 0)
        )
        newSubmenuChildSlotIndex = min(
            max(newSubmenuChildSlotIndex, 0),
            max(profile.interaction.visibleSlotCount - 1, 0)
        )
    }

    private func clearTransientState() {
        errorMessage = nil
        pendingAction = nil
    }

    private func occupiedDescription(at location: CommandWheelSlotLocation) -> String? {
        store.occupiedSlot(
            profileID: location.profileID,
            pageID: location.pageID,
            slotIndex: location.slotIndex
        ).map(describe)
    }

    private func describe(_ metadata: CommandWheelOccupiedSlotMetadata) -> String {
        if let label = metadata.customLabel?.trimmingCharacters(in: .whitespacesAndNewlines),
           label.isEmpty == false {
            return "\(label)"
        }
        switch metadata.content {
        case .command(let reference):
            return "command \(reference.commandID.rawValue)"
        case .submenu(let pageID):
            let pageName = selectedProfile?.pages.first(where: { $0.id == pageID })?.name
            return pageName.map { "submenu “\($0)”" } ?? "a submenu"
        case .dynamicProvider(let provider):
            switch provider.providerID {
            case CommandWheelDynamicProviderID.recentCommands:
                return "Recent Commands"
            case CommandWheelDynamicProviderID.frequentCommands:
                return "Frequent Commands"
            default:
                return "dynamic provider \(provider.providerID)"
            }
        case .empty:
            return "an empty slot"
        }
    }

    private static func initialProfile(
        in configuration: CommandWheelConfiguration
    ) -> CommandWheelProfile? {
        configuration.profiles.first(where: { $0.id == configuration.defaultProfileID })
            ?? configuration.profiles.first
    }

    private static func preferredSlotIndex(
        in page: CommandWheelPage,
        profile: CommandWheelProfile
    ) -> Int {
        for slotIndex in 0 ..< profile.interaction.visibleSlotCount {
            if page.segments.first(where: { $0.slotIndex == slotIndex })?.content == .empty {
                return slotIndex
            }
        }
        return 0
    }
}
