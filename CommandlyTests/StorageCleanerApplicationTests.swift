import CommandKit
import Foundation
import Infrastructure
import Testing
@testable import Commandly

@MainActor
struct StorageCleanerApplicationTests {
    @Test
    func toolsRouteToLibraryReviewAndTheExplicitDuplicateFolderPicker() async throws {
        let libraryItem = StorageCleanupItem(
            name: "com.example.removed.plist",
            containerPath: "~/Library/Preferences",
            path: "/Users/test/Library/Preferences/com.example.removed.plist",
            byteCount: 120,
            category: .applicationLeftover,
            associatedBundleIdentifier: "com.example.removed",
            isSuggestedForRemoval: true
        )
        let duplicateItem = StorageCleanupItem(
            name: "copy.txt",
            containerPath: "~/Documents",
            path: "/Users/test/Documents/copy.txt",
            byteCount: 42,
            category: .duplicate,
            duplicateGroupID: "group",
            isSuggestedForRemoval: true
        )
        let scope = URL(fileURLWithPath: "/Users/test/Documents", isDirectory: true)
        let scanner = InMemoryStorageCleanupScanner(
            libraryResult: StorageCleanupScanResult(items: [libraryItem]),
            duplicateResult: StorageCleanupScanResult(items: [duplicateItem])
        )
        let chooser = InMemoryStorageCleanupDirectoryChooser(selectedDirectory: scope)
        let application = StorageCleanerApplication(
            scanner: scanner,
            directoryChooser: chooser
        )

        #expect(application.toolDefinitions.map(\.id) == [
            StorageCleanerApplicationID.reviewLibraryTool,
            StorageCleanerApplicationID.findDuplicatesTool,
        ])
        #expect(application.toolDefinitions.allSatisfy { $0.kind == .tool })
        #expect(application.toolDefinitions.allSatisfy {
            $0.parentID == StorageCleanerApplicationID.command
        })

        guard case .present(let reviewSession) = application.launch(
            toolID: StorageCleanerApplicationID.reviewLibraryTool,
            arguments: CommandArguments(),
            in: makeContext()
        ) else {
            Issue.record("Expected library review to present Storage Cleaner")
            return
        }
        let reviewModel = try #require(
            reviewSession.model(as: StorageCleanerViewModel.self)
        )
        reviewModel.start()
        await reviewModel.waitForCurrentOperationsForTesting()
        #expect(reviewModel.items == [libraryItem])
        #expect(chooser.requestCount == 0)

        guard case .present(let duplicateSession) = application.launch(
            toolID: StorageCleanerApplicationID.findDuplicatesTool,
            arguments: CommandArguments(),
            in: makeContext()
        ) else {
            Issue.record("Expected duplicate finder to present Storage Cleaner")
            return
        }
        let duplicateModel = try #require(
            duplicateSession.model(as: StorageCleanerViewModel.self)
        )
        duplicateModel.start()
        await duplicateModel.waitForCurrentOperationsForTesting()
        #expect(chooser.requestCount == 1)
        #expect(await scanner.duplicateDirectories == [scope])
        #expect(duplicateModel.category == .duplicates)
        #expect(duplicateModel.items == [duplicateItem])

        reviewSession.stop()
        duplicateSession.stop()
    }

    @Test
    func registeredApplicationScansSelectsAndMovesOnlyConfirmedItemsToTrash() async throws {
        let leftover = StorageCleanupItem(
            name: "com.example.removed.plist",
            containerPath: "~/Library/Preferences",
            path: "/Users/test/Library/Preferences/com.example.removed.plist",
            byteCount: 120,
            category: .applicationLeftover,
            associatedBundleIdentifier: "com.example.removed",
            isSuggestedForRemoval: true
        )
        let cache = StorageCleanupItem(
            name: "com.example.current",
            containerPath: "~/Library/Caches",
            path: "/Users/test/Library/Caches/com.example.current",
            byteCount: 2_048,
            category: .cache,
            associatedBundleIdentifier: "com.example.current",
            isSuggestedForRemoval: false
        )
        let keptDuplicate = StorageCleanupItem(
            name: "report.pdf",
            containerPath: "~/Documents",
            path: "/Users/test/Documents/report.pdf",
            byteCount: 4_096,
            category: .duplicate,
            duplicateGroupID: "group-one",
            isSuggestedForRemoval: false
        )
        let removableDuplicate = StorageCleanupItem(
            name: "report copy.pdf",
            containerPath: "~/Documents/Archive",
            path: "/Users/test/Documents/Archive/report copy.pdf",
            byteCount: 4_096,
            category: .duplicate,
            duplicateGroupID: "group-one",
            isSuggestedForRemoval: true
        )
        let scanner = InMemoryStorageCleanupScanner(
            libraryResult: StorageCleanupScanResult(items: [leftover, cache]),
            duplicateResult: StorageCleanupScanResult(
                items: [keptDuplicate, removableDuplicate],
                inspectedFileCount: 3
            )
        )
        let chooser = InMemoryStorageCleanupDirectoryChooser(
            selectedDirectory: URL(fileURLWithPath: "/Users/test/Documents", isDirectory: true)
        )
        let trashManager = InMemoryApplicationBundleManager()
        let registry = LauncherApplicationRegistry.makeBuiltIn(
            storageCleanupScanner: scanner,
            storageCleanupDirectoryChooser: chooser,
            storageCleanupTrashManager: trashManager
        )

        let definition = try #require(
            registry.definition(for: StorageCleanerApplicationID.command)
        )
        #expect(definition.commandManifest?.title == "Storage Cleaner")
        #expect(definition.documentation != nil)

        let application = try #require(
            registry.application(for: StorageCleanerApplicationID.command)
        )
        let launch = application.launch(in: makeContext())
        guard case .present(let session) = launch else {
            Issue.record("Expected Storage Cleaner to present a session")
            return
        }
        let model = try #require(session.model(as: StorageCleanerViewModel.self))

        model.start()
        await model.waitForCurrentOperationsForTesting()
        #expect(model.items == [leftover, cache])
        #expect(model.selectedPaths == [leftover.path])

        model.chooseAndScanDuplicateFolder()
        await model.waitForCurrentOperationsForTesting()
        #expect(model.category == .duplicates)
        #expect(model.selectedPaths.contains(removableDuplicate.path))
        #expect(model.selectedPaths.contains(keptDuplicate.path) == false)

        model.toggleSelection(of: keptDuplicate)
        #expect(model.selectedPaths.contains(keptDuplicate.path))
        #expect(model.selectedPaths.contains(removableDuplicate.path) == false)

        model.requestCleanupConfirmation()
        model.confirmCleanup()
        await model.waitForCurrentOperationsForTesting()

        #expect(Set(trashManager.trashedPaths) == [leftover.path, keptDuplicate.path])
        #expect(model.items.contains(where: { $0.duplicateGroupID == "group-one" }) == false)
        #expect(model.statusMessage == "Moved 2 items to the Trash.")
    }

    @Test
    func workspaceScannerFindsConservativeLeftoversCachesAndExactDuplicates() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("CommandlyStorageCleaner-\(UUID().uuidString)", isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: root)
        }

        let library = root.appendingPathComponent("Library", isDirectory: true)
        let preferences = library.appendingPathComponent("Preferences", isDirectory: true)
        let containers = library.appendingPathComponent("Containers", isDirectory: true)
        let caches = library.appendingPathComponent("Caches", isDirectory: true)
        try FileManager.default.createDirectory(
            at: preferences,
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: containers,
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: caches,
            withIntermediateDirectories: true
        )

        try Data("removed preference".utf8).write(
            to: preferences.appendingPathComponent("com.example.removed.plist")
        )
        try Data("current preference".utf8).write(
            to: preferences.appendingPathComponent("com.example.current.plist")
        )
        try Data("current helper preference".utf8).write(
            to: preferences.appendingPathComponent("com.example.current.helper.plist")
        )
        try Data("apple preference".utf8).write(
            to: preferences.appendingPathComponent("com.apple.Safari.plist")
        )
        let abandonedContainer = containers.appendingPathComponent(
            "com.vendor.abandoned",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: abandonedContainer,
            withIntermediateDirectories: true
        )
        try Data("container data".utf8).write(
            to: abandonedContainer.appendingPathComponent("data.bin")
        )
        let currentCache = caches.appendingPathComponent(
            "com.example.current",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: currentCache,
            withIntermediateDirectories: true
        )
        try Data("cache".utf8).write(to: currentCache.appendingPathComponent("cache.bin"))
        try FileManager.default.createDirectory(
            at: caches.appendingPathComponent("com.apple.Safari", isDirectory: true),
            withIntermediateDirectories: true
        )

        let scanner = WorkspaceStorageCleanupScanner(
            installedApplicationQuery: InMemoryInstalledApplicationQuery(
                applications: [
                    InstalledApplication(
                        bundleIdentifier: "com.example.current",
                        name: "Current",
                        path: "/Applications/Current.app"
                    )
                ]
            ),
            homeDirectory: root
        )
        let libraryResult = try await scanner.scanLibrary()

        #expect(
            Set(libraryResult.items.map(\.name)) == [
                "com.example.removed.plist",
                "com.vendor.abandoned",
                "com.example.current"
            ]
        )
        #expect(
            libraryResult.items.first {
                $0.name == "com.example.current"
            }?.category == .cache
        )
        #expect(libraryResult.items.contains { $0.name.contains("com.apple") } == false)
        #expect(libraryResult.isPartial == false)

        let duplicateRoot = root.appendingPathComponent("Duplicate Scope", isDirectory: true)
        let nested = duplicateRoot.appendingPathComponent("Nested", isDirectory: true)
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        try Data("same bytes".utf8).write(
            to: duplicateRoot.appendingPathComponent("first.txt")
        )
        try Data("same bytes".utf8).write(
            to: nested.appendingPathComponent("second.txt")
        )
        try Data("different".utf8).write(
            to: duplicateRoot.appendingPathComponent("different.txt")
        )

        let duplicateResult = try await scanner.scanDuplicates(in: duplicateRoot)
        #expect(duplicateResult.items.count == 2)
        #expect(Set(duplicateResult.items.compactMap(\.duplicateGroupID)).count == 1)
        #expect(duplicateResult.items.filter(\.isSuggestedForRemoval).count == 1)
        #expect(duplicateResult.inspectedFileCount == 3)
        #expect(duplicateResult.isPartial == false)
    }

    private func makeContext() -> LauncherApplicationContext {
        LauncherApplicationContext(
            navigation: LauncherApplicationNavigation(
                dismissLauncher: {},
                openSettings: {},
                goBack: {}
            ),
            settings: LauncherApplicationResolvedSettings(
                alias: "",
                hotKey: nil,
                isEnabled: true,
                configuration: [:]
            )
        )
    }
}
