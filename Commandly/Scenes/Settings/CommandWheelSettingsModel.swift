import AppCore
import CommandKit
import Foundation
import Infrastructure
import Observation
import SearchKit
import SecurityKit

nonisolated enum CommandWheelSettingsError: LocalizedError, Equatable, Sendable {
    case invalidName
    case profileNotFound
    case pageNotFound
    case cannotDeleteLastProfile
    case cannotDeleteDefaultProfile
    case cannotDisableDefaultProfile
    case cannotDeleteRootPage
    case commandNotFound
    case invalidArgumentValue
    case invalidSymbol
    case requiredArgumentMissing
    case contextRuleConflict
    case duplicateShortcut
    case occupiedSlotsOutsideRange
    case identifierGenerationFailed

    var errorDescription: String? {
        switch self {
        case .invalidName:
            return "Wheel profile and page names cannot be empty."
        case .profileNotFound:
            return "The selected wheel profile no longer exists."
        case .pageNotFound:
            return "The selected wheel page no longer exists."
        case .cannotDeleteLastProfile:
            return "Command Wheel must keep at least one profile."
        case .cannotDeleteDefaultProfile:
            return "Choose another default profile before deleting this one."
        case .cannotDisableDefaultProfile:
            return "Choose another default profile before disabling this one."
        case .cannotDeleteRootPage:
            return "The root wheel page cannot be deleted."
        case .commandNotFound:
            return "That command is no longer available in the command catalog."
        case .invalidArgumentValue:
            return "A command argument has an invalid value."
        case .invalidSymbol:
            return "Enter the name of an SF Symbol available on this Mac."
        case .requiredArgumentMissing:
            return "A required command argument needs a value."
        case .contextRuleConflict:
            return "Another enabled rule already uses this application and priority."
        case .duplicateShortcut:
            return "Another Command Wheel profile already uses that shortcut."
        case .occupiedSlotsOutsideRange:
            return "Move or clear items outside the new slot count first."
        case .identifierGenerationFailed:
            return "Command Wheel could not generate a unique identifier."
        }
    }
}

nonisolated enum CommandWheelMoveDirection: Sendable {
    case earlier
    case later
}

nonisolated struct CommandWheelSlotID: Hashable, Sendable {
    let profileID: UUID
    let pageID: UUID
    let slotIndex: Int
}

nonisolated enum CommandWheelSlotAvailability: Equatable, Sendable {
    case empty
    case available
    case missing
    case unavailable(requiresPermission: Bool)
}

nonisolated struct CommandWheelSlotPresentation: Identifiable, Sendable {
    let id: CommandWheelSlotID
    let segmentID: UUID?
    let content: CommandWheelSegmentContent
    let title: String
    let subtitle: String?
    let systemImage: String
    let usesCustomIcon: Bool
    let applicationIconPath: String?
    let availability: CommandWheelSlotAvailability
}

nonisolated struct CommandWheelPendingReplacement: Identifiable, Sendable {
    let reference: CommandReference
    let destination: CommandWheelSlotLocation
    let title: String
    let customLabel: String?

    var id: CommandWheelSlotID {
        CommandWheelSlotID(
            profileID: destination.profileID,
            pageID: destination.pageID,
            slotIndex: destination.slotIndex
        )
    }
}

nonisolated struct CommandWheelImportFeedback: Equatable, Sendable {
    let importedProfileCount: Int
    let remappedIdentifierCount: Int
    let missingCommandCount: Int

    var message: String {
        var parts = [
            "Imported \(importedProfileCount) profile\(importedProfileCount == 1 ? "" : "s")."
        ]
        if remappedIdentifierCount > 0 {
            parts.append("Regenerated \(remappedIdentifierCount) conflicting identifiers.")
        }
        if missingCommandCount > 0 {
            parts.append("\(missingCommandCount) referenced commands are unavailable on this Mac.")
        }
        return parts.joined(separator: " ")
    }
}

nonisolated struct CommandWheelPermissionPresentation: Equatable, Sendable {
    let title: String
    let detail: String
    let systemImage: String
}

@Observable
@MainActor
final class CommandWheelSettingsModel {
    let store: CommandWheelProfileStore
    private(set) var commandPicker: CommandWheelCommandPickerModel
    private(set) var catalog: CommandWheelCommandCatalogSnapshot

    @ObservationIgnored
    private let catalogProvider: (@MainActor @Sendable () async -> CommandCatalogSnapshot)?

    @ObservationIgnored
    private let commandSearchProvider: (any SearchProviding)?

    @ObservationIgnored
    private let installedApplicationQuery: any InstalledApplicationQuerying

    @ObservationIgnored
    private var catalogRefreshGeneration: UInt64 = 0

    @ObservationIgnored
    let uuidProvider: any UUIDProviding

    @ObservationIgnored
    private let shortcutIssues: @MainActor () -> [UUID: GlobalShortcutRegistrationIssue]

    var selectedProfileID: UUID?
    var selectedPageID: UUID?
    var selectedSlotIndex: Int?
    var pendingReplacement: CommandWheelPendingReplacement?
    var statusMessage: String?
    var errorMessage: String?
    var importFeedback: CommandWheelImportFeedback?

    init(
        store: CommandWheelProfileStore,
        catalog: CommandWheelCommandCatalogSnapshot,
        catalogProvider: (@MainActor @Sendable () async -> CommandCatalogSnapshot)? = nil,
        commandSearchProvider: (any SearchProviding)? = nil,
        installedApplicationQuery: any InstalledApplicationQuerying =
            InMemoryInstalledApplicationQuery(),
        uuidProvider: any UUIDProviding = SystemUUIDProvider(),
        shortcutIssues: (@MainActor () -> [UUID: GlobalShortcutRegistrationIssue])? = nil
    ) {
        self.store = store
        self.catalog = catalog
        self.catalogProvider = catalogProvider
        self.commandSearchProvider = commandSearchProvider
        self.installedApplicationQuery = installedApplicationQuery
        self.uuidProvider = uuidProvider
        self.shortcutIssues = shortcutIssues ?? { [:] }
        self.commandPicker = CommandWheelCommandPickerModel(
            catalog: catalog,
            provider: commandSearchProvider,
            installedApplicationQuery: installedApplicationQuery
        )
        self.selectedProfileID = store.configuration.defaultProfileID
        self.selectedPageID = store.configuration.profiles.first(where: {
            $0.id == store.configuration.defaultProfileID
        })?.rootPageID
    }

    var configuration: CommandWheelConfiguration {
        store.configuration
    }

    var profiles: [CommandWheelProfile] {
        configuration.profiles
    }

    var selectedProfile: CommandWheelProfile? {
        guard let selectedProfileID else { return nil }
        return profiles.first(where: { $0.id == selectedProfileID })
    }

    var selectedPage: CommandWheelPage? {
        guard let selectedPageID else { return nil }
        return selectedProfile?.pages.first(where: { $0.id == selectedPageID })
    }

    var slotPresentations: [CommandWheelSlotPresentation] {
        guard let profile = selectedProfile, let page = selectedPage else { return [] }
        return (0 ..< profile.interaction.visibleSlotCount).map { slotIndex in
            slotPresentation(profile: profile, page: page, slotIndex: slotIndex)
        }
    }

    var isBusy: Bool {
        store.isPersisting || store.phase == .loading
    }

    func load() async {
        await store.preload()
        await refreshCatalog()
        repairSelection()
        if let storeError = store.errorMessage {
            errorMessage = storeError
        }
    }

    /// Refreshes availability from the same production evaluator used by command resolution.
    func refreshCatalog() async {
        catalogRefreshGeneration &+= 1
        let generation = catalogRefreshGeneration
        if let catalogProvider {
            let refreshedCatalog = CommandWheelCommandCatalogSnapshot(await catalogProvider())
            guard Task.isCancelled == false,
                  generation == catalogRefreshGeneration else {
                return
            }
            catalog = refreshedCatalog
            commandPicker = CommandWheelCommandPickerModel(
                catalog: refreshedCatalog,
                provider: commandSearchProvider,
                installedApplicationQuery: installedApplicationQuery
            )
        }
        await commandPicker.prepareInstalledApplications()
    }

    func selectProfile(_ profileID: UUID) {
        guard let profile = profiles.first(where: { $0.id == profileID }) else { return }
        selectedProfileID = profile.id
        selectedPageID = profile.rootPageID
        selectedSlotIndex = nil
    }

    func selectPage(_ pageID: UUID) {
        guard selectedProfile?.pages.contains(where: { $0.id == pageID }) == true else { return }
        selectedPageID = pageID
        selectedSlotIndex = nil
    }

    func selectSlot(_ slotIndex: Int) {
        guard let profile = selectedProfile,
              (0 ..< profile.interaction.visibleSlotCount).contains(slotIndex) else {
            return
        }
        selectedSlotIndex = slotIndex
    }

    @discardableResult
    func reveal(_ location: CommandWheelSlotLocation) -> Bool {
        guard let profile = profiles.first(where: { $0.id == location.profileID }),
              profile.pages.contains(where: { $0.id == location.pageID }),
              (0 ..< profile.interaction.visibleSlotCount).contains(location.slotIndex) else {
            return false
        }
        selectedProfileID = location.profileID
        selectedPageID = location.pageID
        selectedSlotIndex = location.slotIndex
        return true
    }

    func restoreDefaultsAfterStorageFailure() async throws {
        try await store.replaceCorruptStorageWithDefaults()
        repairSelection()
        statusMessage = "Restored Command Wheel defaults."
    }

    func createProfile(named requestedName: String? = nil) async throws {
        let name = normalizedName(requestedName ?? nextProfileName())
        guard name.isEmpty == false else { throw CommandWheelSettingsError.invalidName }
        var usedIDs = allUsedIDs()
        let profileID = try nextID(used: &usedIDs)
        let pageID = try nextID(used: &usedIDs)
        var segments: [CommandWheelSegment] = []
        for slotIndex in 0 ..< CommandWheelDefaults.interaction.visibleSlotCount {
            segments.append(
                CommandWheelSegment(
                    id: try nextID(used: &usedIDs),
                    slotIndex: slotIndex,
                    content: .empty,
                    customLabel: nil,
                    customIcon: nil
                )
            )
        }
        let profile = CommandWheelProfile(
            id: profileID,
            name: name,
            isEnabled: true,
            shortcut: nil,
            activationBehavior: .holdAndRelease,
            placement: .cursor,
            rootPageID: pageID,
            pages: [CommandWheelPage(id: pageID, name: "Main", segments: segments)],
            contextRules: [],
            appearance: CommandWheelDefaults.appearance,
            interaction: CommandWheelDefaults.interaction,
            hidesUnavailableSegments: false
        )

        try await store.update { configuration in
            if let selectedProfileID,
               let index = configuration.profiles.firstIndex(where: {
                   $0.id == selectedProfileID
               }) {
                configuration.profiles.insert(profile, at: index + 1)
            } else {
                configuration.profiles.append(profile)
            }
        }
        selectedProfileID = profileID
        selectedPageID = pageID
        selectedSlotIndex = nil
        statusMessage = "Created \(name)."
    }

    func renameProfile(_ profileID: UUID, to requestedName: String) async throws {
        let name = normalizedName(requestedName)
        guard name.isEmpty == false else { throw CommandWheelSettingsError.invalidName }
        try await store.update { configuration in
            guard let index = configuration.profiles.firstIndex(where: {
                $0.id == profileID
            }) else {
                throw CommandWheelSettingsError.profileNotFound
            }
            configuration.profiles[index].name = name
        }
        statusMessage = "Renamed wheel profile."
    }

    func duplicateProfile(_ profileID: UUID) async throws {
        guard let source = profiles.first(where: { $0.id == profileID }) else {
            throw CommandWheelSettingsError.profileNotFound
        }
        var usedIDs = allUsedIDs()
        let duplicate = try duplicatedProfile(source, usedIDs: &usedIDs)
        try await store.update { configuration in
            guard let index = configuration.profiles.firstIndex(where: {
                $0.id == profileID
            }) else {
                throw CommandWheelSettingsError.profileNotFound
            }
            configuration.profiles.insert(duplicate, at: index + 1)
        }
        selectedProfileID = duplicate.id
        selectedPageID = duplicate.rootPageID
        selectedSlotIndex = nil
        statusMessage = "Duplicated \(source.name)."
    }

    func deleteProfile(_ profileID: UUID) async throws {
        guard configuration.profiles.contains(where: { $0.id == profileID }) else {
            throw CommandWheelSettingsError.profileNotFound
        }
        guard configuration.profiles.count > 1 else {
            throw CommandWheelSettingsError.cannotDeleteLastProfile
        }
        guard configuration.defaultProfileID != profileID else {
            throw CommandWheelSettingsError.cannotDeleteDefaultProfile
        }
        try await store.update { configuration in
            configuration.profiles.removeAll { $0.id == profileID }
        }
        repairSelection()
        statusMessage = "Deleted wheel profile."
    }

    func moveProfile(_ profileID: UUID, direction: CommandWheelMoveDirection) async throws {
        try await store.update { configuration in
            guard let index = configuration.profiles.firstIndex(where: {
                $0.id == profileID
            }) else {
                throw CommandWheelSettingsError.profileNotFound
            }
            let destination = direction == .earlier ? index - 1 : index + 1
            guard configuration.profiles.indices.contains(destination) else { return }
            let profile = configuration.profiles.remove(at: index)
            configuration.profiles.insert(profile, at: destination)
        }
    }

    func setProfileEnabled(_ enabled: Bool, profileID: UUID) async throws {
        if enabled == false, profileID == configuration.defaultProfileID {
            throw CommandWheelSettingsError.cannotDisableDefaultProfile
        }
        try await store.update { configuration in
            guard let index = configuration.profiles.firstIndex(where: {
                $0.id == profileID
            }) else {
                throw CommandWheelSettingsError.profileNotFound
            }
            configuration.profiles[index].isEnabled = enabled
        }
    }

    func setDefaultProfile(_ profileID: UUID) async throws {
        try await store.update { configuration in
            guard let index = configuration.profiles.firstIndex(where: {
                $0.id == profileID
            }) else {
                throw CommandWheelSettingsError.profileNotFound
            }
            configuration.profiles[index].isEnabled = true
            configuration.defaultProfileID = profileID
        }
        statusMessage = "Updated the default wheel profile."
    }

    func setShortcut(_ shortcut: LauncherHotKey?, profileID: UUID) async throws {
        if let shortcut,
           profiles.contains(where: {
               $0.id != profileID && $0.shortcut == shortcut
           }) {
            throw CommandWheelSettingsError.duplicateShortcut
        }
        try await updateProfile(profileID) { profile in
            profile.shortcut = shortcut
        }
    }

    func shortcutWarning(for profileID: UUID) -> String? {
        guard let profile = profiles.first(where: { $0.id == profileID }),
              profile.shortcut != nil else {
            return nil
        }
        if profiles.contains(where: {
            $0.id != profileID && $0.shortcut == profile.shortcut
        }) {
            return "This shortcut duplicates another Command Wheel profile and cannot be registered."
        }
        guard let issue = shortcutIssues()[profileID] else { return nil }
        switch issue {
        case .duplicate:
            return "This shortcut conflicts with another Commandly global shortcut. Choose another combination."
        case .duplicateID:
            return "Commandly could not uniquely register this profile shortcut."
        case .unavailable:
            return "macOS could not register this shortcut. Choose another combination."
        }
    }

    func accessibilityPermissionPresentation(
        for state: PermissionState
    ) -> CommandWheelPermissionPresentation {
        let detail = "The wheel shortcut itself uses Carbon and does not require Accessibility access. Assigned commands that need access are checked before execution."
        switch state {
        case .authorized:
            return CommandWheelPermissionPresentation(
                title: "Accessibility granted",
                detail: detail,
                systemImage: "checkmark.circle.fill"
            )
        case .notDetermined:
            return CommandWheelPermissionPresentation(
                title: "Accessibility not requested",
                detail: detail,
                systemImage: "minus.circle.fill"
            )
        case .denied:
            return CommandWheelPermissionPresentation(
                title: "Accessibility denied",
                detail: detail,
                systemImage: "xmark.circle.fill"
            )
        case .restricted:
            return CommandWheelPermissionPresentation(
                title: "Accessibility restricted",
                detail: detail,
                systemImage: "exclamationmark.triangle.fill"
            )
        }
    }

    func setCommandWheelEnabled(_ enabled: Bool) async throws {
        try await store.update { $0.isEnabled = enabled }
    }

    func setContextSelectionEnabled(_ enabled: Bool) async throws {
        try await store.update { $0.contextAwareProfileSelectionEnabled = enabled }
    }

    func perform(_ operation: @MainActor () async throws -> Void) async {
        errorMessage = nil
        do {
            try await operation()
        } catch {
            errorMessage = sanitizedMessage(for: error)
        }
    }

    func clearFeedback() {
        statusMessage = nil
        errorMessage = nil
        importFeedback = nil
        store.clearError()
    }

    func contextConflictMessage(
        bundleIdentifier: String,
        priority: Int,
        excluding ruleID: UUID? = nil
    ) -> String? {
        let normalized = bundleIdentifier
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        guard normalized.isEmpty == false else { return nil }
        let conflict = profiles
            .flatMap(\.contextRules)
            .contains { rule in
                rule.id != ruleID
                    && rule.isEnabled
                    && rule.priority == priority
                    && rule.frontmostApplicationBundleIdentifier
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                        .lowercased() == normalized
            }
        return conflict ? CommandWheelSettingsError.contextRuleConflict.errorDescription : nil
    }

    func updateProfile(
        _ profileID: UUID,
        edit: (inout CommandWheelProfile) throws -> Void
    ) async throws {
        try await store.update { configuration in
            guard let index = configuration.profiles.firstIndex(where: {
                $0.id == profileID
            }) else {
                throw CommandWheelSettingsError.profileNotFound
            }
            try edit(&configuration.profiles[index])
        }
    }

    func repairSelection() {
        if selectedProfileID == nil
            || profiles.contains(where: { $0.id == selectedProfileID }) == false {
            selectedProfileID = configuration.defaultProfileID
        }
        guard let profile = selectedProfile else {
            selectedPageID = nil
            selectedSlotIndex = nil
            return
        }
        if selectedPageID == nil
            || profile.pages.contains(where: { $0.id == selectedPageID }) == false {
            selectedPageID = profile.rootPageID
        }
        if let selectedSlotIndex,
           (0 ..< profile.interaction.visibleSlotCount).contains(selectedSlotIndex) == false {
            self.selectedSlotIndex = nil
        }
    }

    func setImportFeedback(_ result: CommandWheelImportResult) {
        importFeedback = CommandWheelImportFeedback(
            importedProfileCount: result.importedProfileIDs.count,
            remappedIdentifierCount: result.profileIDRemapping.count
                + result.pageIDRemapping.count
                + result.segmentIDRemapping.count
                + result.contextRuleIDRemapping.count,
            missingCommandCount: result.missingCommandIDs.count
        )
        statusMessage = importFeedback?.message
        repairSelection()
    }

    private func slotPresentation(
        profile: CommandWheelProfile,
        page: CommandWheelPage,
        slotIndex: Int
    ) -> CommandWheelSlotPresentation {
        let segment = page.segments.first(where: { $0.slotIndex == slotIndex })
        let content = segment?.content ?? .empty
        let identity = CommandWheelSlotID(
            profileID: profile.id,
            pageID: page.id,
            slotIndex: slotIndex
        )
        switch content {
        case .empty:
            let customIcon = validCustomIconName(segment)
            return CommandWheelSlotPresentation(
                id: identity,
                segmentID: segment?.id,
                content: content,
                title: "Empty slot",
                subtitle: "Choose a command, submenu, or dynamic provider",
                systemImage: CommandWheelSystemSymbol.resolvedName(
                    customIcon,
                    fallback: "plus"
                ),
                usesCustomIcon: customIcon != nil,
                applicationIconPath: nil,
                availability: .empty
            )
        case .command(let reference):
            let installedApplication = commandPicker.installedApplication(for: reference)
            let customIcon = validCustomIconName(segment)
            guard let manifest = commandPicker.manifest(for: reference.commandID) else {
                return CommandWheelSlotPresentation(
                    id: identity,
                    segmentID: segment?.id,
                    content: content,
                    title: segment?.customLabel
                        ?? installedApplication?.name
                        ?? "Missing command",
                    subtitle: "Command ID: \(reference.commandID.rawValue)",
                    systemImage: CommandWheelSystemSymbol.resolvedName(
                        customIcon,
                        fallback: "questionmark.diamond"
                    ),
                    usesCustomIcon: customIcon != nil,
                    applicationIconPath: customIcon == nil
                        ? installedApplication?.path : nil,
                    availability: .missing
                )
            }
            let availability = commandPicker.availability(for: reference) ?? .available
            let state: CommandWheelSlotAvailability
            switch availability {
            case .available:
                state = .available
            case .unavailable(let reason):
                if case .missingPermission = reason {
                    state = .unavailable(requiresPermission: true)
                } else {
                    state = .unavailable(requiresPermission: false)
                }
            }
            return CommandWheelSlotPresentation(
                id: identity,
                segmentID: segment?.id,
                content: content,
                title: segment?.customLabel
                    ?? installedApplication?.name
                    ?? manifest.title,
                subtitle: installedApplication?.bundleIdentifier
                    ?? manifest.subtitle,
                systemImage: CommandWheelSystemSymbol.resolvedName(
                    customIcon,
                    fallback: manifest.systemImage
                ),
                usesCustomIcon: customIcon != nil,
                applicationIconPath: customIcon == nil ? installedApplication?.path : nil,
                availability: state
            )
        case .submenu(let pageID):
            let child = profile.pages.first(where: { $0.id == pageID })
            let customIcon = validCustomIconName(segment)
            return CommandWheelSlotPresentation(
                id: identity,
                segmentID: segment?.id,
                content: content,
                title: segment?.customLabel ?? child?.name ?? "Missing submenu",
                subtitle: "Submenu",
                systemImage: CommandWheelSystemSymbol.resolvedName(
                    customIcon,
                    fallback: "circle.grid.2x2"
                ),
                usesCustomIcon: customIcon != nil,
                applicationIconPath: nil,
                availability: child == nil ? .missing : .available
            )
        case .dynamicProvider(let reference):
            let recent = reference.providerID == CommandWheelDynamicProviderID.recentCommands
            let customIcon = validCustomIconName(segment)
            return CommandWheelSlotPresentation(
                id: identity,
                segmentID: segment?.id,
                content: content,
                title: segment?.customLabel ?? (recent ? "Recent Commands" : "Frequent Commands"),
                subtitle: "Dynamic provider",
                systemImage: CommandWheelSystemSymbol.resolvedName(
                    customIcon,
                    fallback: recent ? "clock.arrow.circlepath" : "chart.bar.fill"
                ),
                usesCustomIcon: customIcon != nil,
                applicationIconPath: nil,
                availability: CommandWheelDynamicProviderID.supported.contains(reference.providerID)
                    ? .available : .missing
            )
        }
    }

    private func validCustomIconName(_ segment: CommandWheelSegment?) -> String? {
        guard let candidate = segment?.customIcon?.systemSymbolName
            .trimmingCharacters(in: .whitespacesAndNewlines),
              CommandWheelSystemSymbol.isValid(candidate) else {
            return nil
        }
        return candidate
    }

    private func duplicatedProfile(
        _ source: CommandWheelProfile,
        usedIDs: inout Set<UUID>
    ) throws -> CommandWheelProfile {
        let profileID = try nextID(used: &usedIDs)
        var pageMap: [UUID: UUID] = [:]
        for page in source.pages {
            pageMap[page.id] = try nextID(used: &usedIDs)
        }
        let pages = try source.pages.map { page in
            let pageID = try requiredMappedID(page.id, in: pageMap)
            let segments = try page.segments.map { segment in
                let content: CommandWheelSegmentContent
                if case .submenu(let childID) = segment.content {
                    content = .submenu(pageID: try requiredMappedID(childID, in: pageMap))
                } else {
                    content = segment.content
                }
                return CommandWheelSegment(
                    id: try nextID(used: &usedIDs),
                    slotIndex: segment.slotIndex,
                    content: content,
                    customLabel: segment.customLabel,
                    customIcon: segment.customIcon
                )
            }
            return CommandWheelPage(id: pageID, name: page.name, segments: segments)
        }
        let rules = try source.contextRules.map { rule in
            CommandWheelContextRule(
                id: try nextID(used: &usedIDs),
                frontmostApplicationBundleIdentifier:
                    rule.frontmostApplicationBundleIdentifier,
                priority: rule.priority,
                isEnabled: false
            )
        }
        return CommandWheelProfile(
            id: profileID,
            name: String("\(source.name) Copy".prefix(CommandWheelLimits.maximumNameLength)),
            isEnabled: source.isEnabled,
            shortcut: nil,
            activationBehavior: source.activationBehavior,
            placement: source.placement,
            rootPageID: try requiredMappedID(source.rootPageID, in: pageMap),
            pages: pages,
            contextRules: rules,
            appearance: source.appearance,
            interaction: source.interaction,
            hidesUnavailableSegments: source.hidesUnavailableSegments
        )
    }

    private func requiredMappedID(_ id: UUID, in map: [UUID: UUID]) throws -> UUID {
        guard let mapped = map[id] else {
            throw CommandWheelSettingsError.identifierGenerationFailed
        }
        return mapped
    }

    private func nextProfileName() -> String {
        var index = profiles.count + 1
        var candidate = "Profile \(index)"
        let existing = Set(profiles.map { $0.name.lowercased() })
        while existing.contains(candidate.lowercased()) {
            index += 1
            candidate = "Profile \(index)"
        }
        return candidate
    }

    private func normalizedName(_ value: String) -> String {
        String(
            value.trimmingCharacters(in: .whitespacesAndNewlines)
                .prefix(CommandWheelLimits.maximumNameLength)
        )
    }

    private func allUsedIDs() -> Set<UUID> {
        Set(profiles.map(\.id))
            .union(profiles.flatMap(\.pages).map(\.id))
            .union(profiles.flatMap(\.pages).flatMap(\.segments).map(\.id))
            .union(profiles.flatMap(\.contextRules).map(\.id))
    }

    private func nextID(used: inout Set<UUID>) throws -> UUID {
        for _ in 0 ..< 256 {
            let candidate = uuidProvider.uuid()
            if used.insert(candidate).inserted { return candidate }
        }
        throw CommandWheelSettingsError.identifierGenerationFailed
    }

    private func sanitizedMessage(for error: any Error) -> String {
        if let localized = error as? any LocalizedError,
           let description = localized.errorDescription {
            return description
        }
        return "Command Wheel settings could not be updated."
    }
}
