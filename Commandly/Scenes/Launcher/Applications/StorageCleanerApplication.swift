import CommandKit
import Infrastructure
import SwiftUI

enum StorageCleanerApplicationID {
    static let command = CommandID(rawValue: "system.storage-cleaner")
    static let reviewLibraryTool = CommandID(rawValue: "system.storage-cleaner.review-library")
    static let findDuplicatesTool = CommandID(
        rawValue: "system.storage-cleaner.find-exact-duplicates"
    )
}

@MainActor
struct StorageCleanerApplication: LauncherApplication {
    private static let manifest = CommandManifest(
        id: StorageCleanerApplicationID.command,
        title: "Storage Cleaner",
        subtitle: "Review app leftovers, caches, and exact duplicate files",
        systemImage: "internaldrive.fill",
        category: .system,
        mode: .view,
        keywords: [
            "storage", "disk", "disc", "clean", "cleanup", "cache", "caches",
            "leftovers", "residual files", "duplicates", "duplicate finder", "junk"
        ],
        badgeTitle: "Application",
        defaultActions: [
            CommandActionDescriptor(
                id: StorageCleanerActionID.toggleSelection,
                title: "Toggle Selection",
                isPrimary: true,
                keyHint: .return
            ),
            CommandActionDescriptor(
                id: StorageCleanerActionID.reviewCleanup,
                title: "Review Cleanup…",
                keyHint: CommandKeyHint(symbols: ["⌘", "↩"])
            ),
            CommandActionDescriptor(
                id: BuiltInCommandActionID.openActions,
                title: "Actions",
                keyHint: .commandK
            )
        ]
    )

    let definition = LauncherApplicationDefinition(
        manifest: Self.manifest,
        parentID: BuiltInLauncherApplicationGroup.catalogID,
        kind: .application,
        order: 47,
        documentation: RegisteredApplicationDocumentation.storageCleaner
    )

    private let scanner: any StorageCleanupScanning
    private let directoryChooser: any StorageCleanupDirectoryChoosing
    private let trashManager: any ApplicationBundleManaging

    init(
        scanner: any StorageCleanupScanning = InMemoryStorageCleanupScanner(),
        directoryChooser: any StorageCleanupDirectoryChoosing =
            InMemoryStorageCleanupDirectoryChooser(),
        trashManager: any ApplicationBundleManaging = InMemoryApplicationBundleManager()
    ) {
        self.scanner = scanner
        self.directoryChooser = directoryChooser
        self.trashManager = trashManager
    }

    var toolDefinitions: [LauncherApplicationDefinition] {
        [
            LauncherApplicationDefinition.tool(
                id: StorageCleanerApplicationID.reviewLibraryTool,
                parentID: StorageCleanerApplicationID.command,
                title: "Review App Leftovers and Caches",
                subtitle: "Scan conservative Library locations and review every candidate",
                systemImage: "internaldrive",
                category: .system,
                keywords: [
                    "scan storage", "app leftovers", "residual files", "caches", "review cleanup"
                ]
            ),
            LauncherApplicationDefinition.tool(
                id: StorageCleanerApplicationID.findDuplicatesTool,
                parentID: StorageCleanerApplicationID.command,
                title: "Find Exact Duplicates",
                subtitle: "Choose one folder for an exact on-device duplicate scan",
                systemImage: "doc.on.doc",
                category: .system,
                order: 1,
                keywords: [
                    "duplicate finder", "duplicate files", "choose folder", "exact duplicates"
                ]
            )
        ]
    }

    func launch(in context: LauncherApplicationContext) -> LauncherApplicationLaunch {
        makeLaunch(initialEntryPoint: .libraryReview, context: context)
    }

    func launch(
        toolID: CommandID,
        arguments: CommandArguments,
        in context: LauncherApplicationContext
    ) -> LauncherApplicationLaunch {
        _ = arguments
        switch toolID {
        case StorageCleanerApplicationID.reviewLibraryTool:
            return makeLaunch(initialEntryPoint: .libraryReview, context: context)
        case StorageCleanerApplicationID.findDuplicatesTool:
            return makeLaunch(initialEntryPoint: .exactDuplicates, context: context)
        default:
            return .message("Storage Cleaner tool is unavailable.")
        }
    }

    private func makeLaunch(
        initialEntryPoint: StorageCleanerEntryPoint,
        context: LauncherApplicationContext
    ) -> LauncherApplicationLaunch {
        let model = StorageCleanerViewModel(
            scanner: scanner,
            directoryChooser: directoryChooser,
            trashManager: trashManager,
            onGoBack: context.navigation.goBack,
            initialEntryPoint: initialEntryPoint
        )
        return .present(
            LauncherApplicationSession(manifest: Self.manifest, model: model) {
                StorageCleanerView(viewModel: $0)
            }
        )
    }
}

extension StorageCleanerViewModel: LauncherApplicationModel {}
