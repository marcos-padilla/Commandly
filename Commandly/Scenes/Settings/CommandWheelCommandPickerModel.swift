import CommandKit
import Foundation
import Infrastructure
import Observation
import SearchKit

nonisolated struct CommandWheelCommandCatalogSnapshot: Sendable {
    let manifests: [CommandManifest]
    let availabilitySnapshot: CommandAvailabilitySnapshot

    init(
        manifests: [CommandManifest],
        availability: [CommandID: CommandAvailability] = [:]
    ) {
        self.manifests = manifests
        self.availabilitySnapshot = CommandAvailabilitySnapshot(
            commandAvailability: availability
        )
    }

    init(_ snapshot: CommandCatalogSnapshot) {
        self.manifests = snapshot.manifests
        self.availabilitySnapshot = snapshot.availability
    }

    var knownCommandIDs: Set<CommandID> {
        Set(manifests.map(\.id))
    }

    func availability(for reference: CommandReference) -> CommandAvailability {
        availabilitySnapshot.availability(for: reference)
    }
}

nonisolated struct CommandWheelCommandOption: Identifiable, Sendable {
    let reference: CommandReference
    let manifest: CommandManifest
    let title: String
    let subtitle: String?
    let icon: LauncherItemIcon
    let availability: CommandAvailability

    var id: String {
        if case .string(let bundleIdentifier)? = reference.arguments[
            BuiltInCommandArgumentName.bundleIdentifier
        ], reference.commandID == BuiltInCommandID.openInstalledApplication {
            return "application:\(bundleIdentifier)"
        }
        return "command:\(reference.commandID.rawValue)"
    }

    var accessibilityIdentifier: String {
        "command-wheel.command.\(id)"
    }
}

/// Cancellable command picker backed by the launcher's existing command search provider.
@Observable
@MainActor
final class CommandWheelCommandPickerModel {
    private let provider: any SearchProviding
    private let installedApplicationQuery: any InstalledApplicationQuerying
    private let knownManifestsByID: [CommandID: CommandManifest]
    private let manifestsByID: [CommandID: CommandManifest]
    private let availabilitySnapshot: CommandAvailabilitySnapshot
    private var installedApplicationsByBundleID: [String: InstalledApplication] = [:]

    var query = ""
    private(set) var options: [CommandWheelCommandOption]
    private(set) var isSearching = false
    private(set) var errorMessage: String?

    init(
        catalog: CommandWheelCommandCatalogSnapshot,
        provider: (any SearchProviding)? = nil,
        installedApplicationQuery: any InstalledApplicationQuerying =
            InMemoryInstalledApplicationQuery()
    ) {
        self.provider = provider ?? CommandSearchProvider(manifests: catalog.manifests)
        self.installedApplicationQuery = installedApplicationQuery
        var knownManifestsByID: [CommandID: CommandManifest] = [:]
        for manifest in catalog.manifests where knownManifestsByID[manifest.id] == nil {
            knownManifestsByID[manifest.id] = manifest
        }
        self.knownManifestsByID = knownManifestsByID
        let assignableManifests = catalog.manifests.filter(Self.isAssignableWithoutInput)
        var manifestsByID: [CommandID: CommandManifest] = [:]
        for manifest in assignableManifests where manifestsByID[manifest.id] == nil {
            manifestsByID[manifest.id] = manifest
        }
        self.manifestsByID = manifestsByID
        self.availabilitySnapshot = catalog.availabilitySnapshot
        self.options = assignableManifests.map { manifest in
            let reference = CommandReference(commandID: manifest.id)
            return CommandWheelCommandOption(
                reference: reference,
                manifest: manifest,
                title: manifest.title,
                subtitle: manifest.subtitle,
                icon: .system(manifest.systemImage),
                availability: catalog.availability(
                    for: reference
                )
            )
        }
    }

    /// Loads installed-app presentation metadata through the existing shared query.
    func prepareInstalledApplications() async {
        let applications = await installedApplicationQuery.installedApplications()
        guard Task.isCancelled == false else { return }
        installedApplicationsByBundleID = Dictionary(
            applications.map { ($0.bundleIdentifier, $0) },
            uniquingKeysWith: { first, _ in first }
        )
    }

    func search() async {
        isSearching = true
        errorMessage = nil
        defer { isSearching = false }
        do {
            await prepareInstalledApplications()
            async let commandResult = provider.search(
                SearchQuery(text: query, limit: 100)
            )
            async let applicationResult = ApplicationSearchProvider(
                applications: installedApplicationsByBundleID.values.map {
                    InstalledApplicationSnapshot(
                        bundleIdentifier: $0.bundleIdentifier,
                        name: $0.name,
                        path: $0.path
                    )
                }
            ).search(SearchQuery(text: query, limit: 100))
            let result = try await merged(commandResult, applicationResult)
            try Task.checkCancellation()
            options = result.items.compactMap { item in
                if item.providerID == BuiltInSearchProviderID.applications {
                    return installedApplicationOption(bundleIdentifier: item.id)
                }
                let commandID = CommandID(rawValue: item.id)
                guard let manifest = manifestsByID[commandID] else { return nil }
                let reference = CommandReference(commandID: commandID)
                return CommandWheelCommandOption(
                    reference: reference,
                    manifest: manifest,
                    title: manifest.title,
                    subtitle: manifest.subtitle,
                    icon: .system(manifest.systemImage),
                    availability: availabilitySnapshot.availability(
                        for: reference
                    )
                )
            }
        } catch is CancellationError {
            return
        } catch {
            options = []
            errorMessage = "Commands could not be searched."
        }
    }

    func manifest(for commandID: CommandID) -> CommandManifest? {
        knownManifestsByID[commandID]
    }

    func assignableManifest(for commandID: CommandID) -> CommandManifest? {
        manifestsByID[commandID]
    }

    func availability(for reference: CommandReference) -> CommandAvailability? {
        guard knownManifestsByID[reference.commandID] != nil else { return nil }
        return availabilitySnapshot.availability(for: reference)
    }

    func installedApplication(for reference: CommandReference) -> InstalledApplication? {
        guard reference.commandID == BuiltInCommandID.openInstalledApplication,
              case .string(let bundleIdentifier)? = reference.arguments[
                  BuiltInCommandArgumentName.bundleIdentifier
              ] else {
            return nil
        }
        return installedApplicationsByBundleID[bundleIdentifier]
    }

    func isValidAssignment(_ reference: CommandReference) -> Bool {
        guard let manifest = knownManifestsByID[reference.commandID] else { return false }
        let argumentsByName = Dictionary(
            uniqueKeysWithValues: manifest.arguments.map { ($0.name, $0) }
        )
        guard reference.arguments.values.keys.allSatisfy({ argumentsByName[$0] != nil }) else {
            return false
        }
        for argument in manifest.arguments {
            if let value = reference.arguments[argument.name] {
                guard value.valueType == argument.valueType else { return false }
            } else if argument.isRequired, argument.defaultValue == nil {
                return false
            }
        }
        if reference.commandID == BuiltInCommandID.openInstalledApplication {
            guard case .string(let bundleIdentifier)? = reference.arguments[
                BuiltInCommandArgumentName.bundleIdentifier
            ], bundleIdentifier.isEmpty == false,
            bundleIdentifier == bundleIdentifier.trimmingCharacters(
                in: .whitespacesAndNewlines
            ) else {
                return false
            }
        }
        return true
    }

    private func installedApplicationOption(
        bundleIdentifier: String
    ) -> CommandWheelCommandOption? {
        guard let application = installedApplicationsByBundleID[bundleIdentifier],
              let manifest = knownManifestsByID[BuiltInCommandID.openInstalledApplication] else {
            return nil
        }
        let reference = BuiltInCommandReference.openInstalledApplication(
            bundleIdentifier: bundleIdentifier
        )
        return CommandWheelCommandOption(
            reference: reference,
            manifest: manifest,
            title: application.name,
            subtitle: application.bundleIdentifier,
            icon: .application(path: application.path),
            availability: availabilitySnapshot.availability(for: reference)
        )
    }

    private func merged(
        _ commandResult: SearchResult,
        _ applicationResult: SearchResult
    ) -> SearchResult {
        let items = (commandResult.items + applicationResult.items).sorted { lhs, rhs in
            if lhs.score == rhs.score {
                let titleOrder = lhs.title.localizedCaseInsensitiveCompare(rhs.title)
                if titleOrder != .orderedSame { return titleOrder == .orderedAscending }
                return lhs.id < rhs.id
            }
            return lhs.score > rhs.score
        }
        return SearchResult(
            query: commandResult.query,
            items: Array(items.prefix(100)),
            isComplete: commandResult.isComplete && applicationResult.isComplete
        )
    }

    /// Commands requiring invocation-specific input must enter through a result that already owns
    /// those typed arguments (for example the launcher's installed-application result).
    private nonisolated static func isAssignableWithoutInput(
        _ manifest: CommandManifest
    ) -> Bool {
        manifest.arguments.contains { argument in
            argument.isRequired && argument.defaultValue == nil
        } == false
    }
}
