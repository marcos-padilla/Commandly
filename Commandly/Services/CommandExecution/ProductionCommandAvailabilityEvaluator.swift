import CommandKit
import Foundation
import Infrastructure
import SecurityKit

/// Builds one immutable availability generation for the shared resolver and Settings.
///
/// The evaluator checks state only; it never requests a permission or launches an application.
/// Known disabled manifests remain in the catalog with a `.disabled` availability override.
@MainActor
final class ProductionCommandAvailabilityEvaluator {
    private let applicationRegistry: LauncherApplicationRegistry
    private let permissionService: any PermissionChecking
    private let installedApplicationQuery: any InstalledApplicationQuerying

    init(
        applicationRegistry: LauncherApplicationRegistry,
        permissionService: any PermissionChecking,
        installedApplicationQuery: any InstalledApplicationQuerying
    ) {
        self.applicationRegistry = applicationRegistry
        self.permissionService = permissionService
        self.installedApplicationQuery = installedApplicationQuery
    }

    /// Conservative presentation state used before the first asynchronous evaluation finishes.
    func initialSnapshot() -> CommandCatalogSnapshot {
        let catalog = capturedCatalog()
        return makeSnapshot(
            catalog: catalog,
            permissionStates: [:],
            installedBundleIdentifiers: []
        )
    }

    /// Evaluates permissions and installed applications without causing system prompts.
    func snapshot() async -> CommandCatalogSnapshot {
        let catalog = capturedCatalog()
        var permissionIdentifiers: Set<String> = []
        for manifest in catalog.manifests {
            for requirement in manifest.availabilityRequirements {
                guard case .permission(let identifier) = requirement else { continue }
                permissionIdentifiers.insert(identifier)
            }
        }

        async let installedApplications = installedApplicationQuery.installedApplications()
        var permissionStates: [String: PermissionState] = [:]
        for identifier in permissionIdentifiers.sorted() {
            guard let kind = PermissionKind(rawValue: identifier) else { continue }
            permissionStates[identifier] = await permissionService.state(for: kind)
        }

        return makeSnapshot(
            catalog: catalog,
            permissionStates: permissionStates,
            installedBundleIdentifiers: Set(
                await installedApplications.map(\.bundleIdentifier)
            )
        )
    }

    private func capturedCatalog() -> CapturedCommandCatalog {
        let manifests = applicationRegistry.allKnownManifests()
            + [BuiltInCommandManifest.openInstalledApplication]
        return CapturedCommandCatalog(
            manifests: manifests,
            enabledCommandIDs: Set(applicationRegistry.allManifests().map(\.id))
                .union([BuiltInCommandID.openInstalledApplication])
        )
    }

    private func makeSnapshot(
        catalog: CapturedCommandCatalog,
        permissionStates: [String: PermissionState],
        installedBundleIdentifiers: Set<String>
    ) -> CommandCatalogSnapshot {
        var availability: [CommandID: CommandAvailability] = [:]
        for manifest in catalog.manifests {
            guard catalog.enabledCommandIDs.contains(manifest.id) else {
                availability[manifest.id] = .unavailable(.disabled)
                continue
            }
            for requirement in manifest.availabilityRequirements {
                switch requirement {
                case .permission(let identifier):
                    guard PermissionKind(rawValue: identifier) != nil else {
                        availability[manifest.id] = .unavailable(.unsupported)
                        break
                    }
                    guard permissionStates[identifier] == .authorized else {
                        availability[manifest.id] = .unavailable(
                            .missingPermission(identifier: identifier)
                        )
                        break
                    }
                }
                if availability[manifest.id] != nil { break }
            }
        }

        return CommandCatalogSnapshot(
            manifests: catalog.manifests,
            availability: CommandAvailabilitySnapshot(
                commandAvailability: availability,
                installedApplicationBundleIdentifiers: installedBundleIdentifiers
            )
        )
    }
}

private nonisolated struct CapturedCommandCatalog: Sendable {
    let manifests: [CommandManifest]
    let enabledCommandIDs: Set<CommandID>
}
