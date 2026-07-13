import CommandKit
import Foundation
import Infrastructure
import SearchKit

/// A registered application that can be discovered and launched from Commandly.
///
/// Applications own their feature-specific model and surface construction. The launcher only
/// coordinates discovery, navigation, and the shared application-session contract.
@MainActor
protocol LauncherApplication {
    var manifest: CommandManifest { get }

    func launch(in context: LauncherApplicationContext) -> LauncherApplicationLaunch
}

/// Launcher-shell navigation available while constructing an application session.
/// Feature services are injected into each application when it is registered.
@MainActor
struct LauncherApplicationContext {
    let navigation: LauncherApplicationNavigation
}

/// File Search's focused dependency group.
@MainActor
struct FileSearchApplicationServices {
    let searchService: any FileSearching
    let urlOpener: any URLOpening
    let fileRevealer: any FileRevealing
    let fileActionService: any FileActionServicing
    let finderInfoPresenter: any FinderInfoPresenting
    let pasteboard: any PasteboardAccessing
}

/// Navigation callbacks shared by launcher applications.
@MainActor
struct LauncherApplicationNavigation {
    let dismissLauncher: () -> Void
    let openSettings: () -> Void
    let goBack: () -> Void
}

/// Result of launching a registered application.
@MainActor
enum LauncherApplicationLaunch {
    case present(LauncherApplicationSession)
    case openSettings
    case dismiss
    case message(String)
}

enum LauncherApplicationRegistryError: Error, Equatable {
    case duplicateApplication(CommandID)
}

/// The single source of truth for applications exposed by the launcher.
@MainActor
final class LauncherApplicationRegistry {
    private var applications: [CommandID: any LauncherApplication] = [:]

    init() {}

    func register(_ application: any LauncherApplication) throws {
        let id = application.manifest.id
        guard applications[id] == nil else {
            throw LauncherApplicationRegistryError.duplicateApplication(id)
        }
        applications[id] = application
    }

    func application(for id: CommandID) -> (any LauncherApplication)? {
        applications[id]
    }

    func allManifests() -> [CommandManifest] {
        applications.values
            .map(\.manifest)
            .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }

    static func makeBuiltIn(
        clipboardHistoryStore: ClipboardHistoryStore = ClipboardHistoryStore(),
        fileSearchServices: FileSearchApplicationServices = .inMemory
    ) -> LauncherApplicationRegistry {
        let registry = LauncherApplicationRegistry()
        do {
            try registry.register(OpenSettingsApplication())
            try registry.register(
                ClipboardHistoryApplication(store: clipboardHistoryStore)
            )
            try registry.register(
                FileSearchApplication(services: fileSearchServices)
            )
        } catch {
            preconditionFailure("Built-in launcher application identifiers must be unique: \(error)")
        }
        return registry
    }
}

extension FileSearchApplicationServices {
    static var inMemory: FileSearchApplicationServices {
        FileSearchApplicationServices(
            searchService: InMemoryFileSearchService(),
            urlOpener: NoOpURLOpener(),
            fileRevealer: InMemoryFileRevealer(),
            fileActionService: InMemoryFileActionService(),
            finderInfoPresenter: InMemoryFinderInfoPresenter(),
            pasteboard: SystemPasteboard()
        )
    }
}
