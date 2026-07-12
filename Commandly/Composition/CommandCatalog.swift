import Foundation
import CommandKit
import Infrastructure
import SearchKit
import SwiftUI

/// Runtime helpers shared by command surfaces.
@MainActor
struct CommandRuntime {
    let clipboardHistoryStore: ClipboardHistoryStore
    let fileSearchService: any FileSearching
    let urlOpener: any URLOpening
    let fileRevealer: any FileRevealing
    let fileActionService: any FileActionServicing
    let finderInfoPresenter: any FinderInfoPresenting
    let pasteboard: any PasteboardAccessing
    var dismissLauncher: () -> Void
    var openSettings: () -> Void
    var goBack: () -> Void
}

/// Outcome when activating a registered command from the root list.
enum CommandActivation: Equatable {
    case pushView(CommandID)
    case openSettings
    case dismiss
    case message(String)
}

/// App-layer registration of a launcher command.
@MainActor
protocol LauncherCommandRegistering {
    var manifest: CommandManifest { get }
    func activate(runtime: CommandRuntime) -> CommandActivation
    @ViewBuilder
    func makeSurface(runtime: CommandRuntime) -> AnyView
}

/// Catalog of built-in commands available to the launcher.
@MainActor
final class CommandCatalog {
    private var commands: [CommandID: any LauncherCommandRegistering] = [:]

    init() {}

    func register(_ command: any LauncherCommandRegistering) {
        commands[command.manifest.id] = command
    }

    func command(for id: CommandID) -> (any LauncherCommandRegistering)? {
        commands[id]
    }

    func allManifests() -> [CommandManifest] {
        commands.values
            .map(\.manifest)
            .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }

    static func makeBuiltIn() -> CommandCatalog {
        let catalog = CommandCatalog()
        catalog.register(OpenSettingsCommand())
        catalog.register(ClipboardHistoryCommand())
        catalog.register(FileSearchCommand())
        return catalog
    }
}

@MainActor
struct FileSearchCommand: LauncherCommandRegistering {
    let manifest = CommandManifest(
        id: BuiltInCommandID.searchFiles,
        title: "Search Files",
        subtitle: "Find files, folders, and indexed contents",
        systemImage: "doc.text.magnifyingglass",
        category: .productivity,
        mode: .view,
        keywords: ["files", "finder", "documents", "folders", "images"],
        badgeTitle: "Command",
        defaultActions: [
            CommandActionDescriptor(
                id: BuiltInCommandActionID.openFile,
                title: "Open",
                isPrimary: true,
                keyHint: .return
            ),
            CommandActionDescriptor(
                id: BuiltInCommandActionID.openActions,
                title: "Actions",
                keyHint: .commandK
            )
        ]
    )

    func activate(runtime: CommandRuntime) -> CommandActivation {
        .pushView(manifest.id)
    }

    func makeSurface(runtime: CommandRuntime) -> AnyView {
        AnyView(
            FileSearchView(
                viewModel: FileSearchViewModel(
                    searchService: runtime.fileSearchService,
                    urlOpener: runtime.urlOpener,
                    fileRevealer: runtime.fileRevealer,
                    fileActionService: runtime.fileActionService,
                    finderInfoPresenter: runtime.finderInfoPresenter,
                    pasteboard: runtime.pasteboard,
                    onGoBack: runtime.goBack,
                    onDismiss: runtime.dismissLauncher,
                    onOpenSettings: runtime.openSettings
                )
            )
        )
    }
}

@MainActor
struct OpenSettingsCommand: LauncherCommandRegistering {
    let manifest = CommandManifest(
        id: BuiltInCommandID.openSettings,
        title: "Open Settings",
        subtitle: "Preferences, permissions, and about",
        systemImage: "gearshape",
        category: .navigation,
        mode: .action,
        keywords: ["preferences", "general"],
        badgeTitle: "Settings",
        defaultActions: [
            CommandActionDescriptor(
                id: CommandActionID(rawValue: "open"),
                title: "Open Settings",
                isPrimary: true,
                keyHint: .return
            )
        ]
    )

    func activate(runtime: CommandRuntime) -> CommandActivation {
        .openSettings
    }

    func makeSurface(runtime: CommandRuntime) -> AnyView {
        AnyView(EmptyView())
    }
}

@MainActor
struct ClipboardHistoryCommand: LauncherCommandRegistering {
    let manifest = CommandManifest(
        id: BuiltInCommandID.clipboardHistory,
        title: "Clipboard History",
        subtitle: "Browse and copy recent clipboard items",
        systemImage: "clipboard",
        category: .productivity,
        mode: .view,
        keywords: ["paste", "history", "copy", "clipboard"],
        badgeTitle: "Command",
        defaultActions: [
            CommandActionDescriptor(
                id: BuiltInCommandActionID.copy,
                title: "Copy",
                isPrimary: true,
                keyHint: .return
            ),
            CommandActionDescriptor(
                id: BuiltInCommandActionID.openActions,
                title: "Actions",
                keyHint: .commandK
            )
        ]
    )

    func activate(runtime: CommandRuntime) -> CommandActivation {
        .pushView(manifest.id)
    }

    func makeSurface(runtime: CommandRuntime) -> AnyView {
        AnyView(
            ClipboardHistoryView(
                viewModel: ClipboardHistoryViewModel(
                    store: runtime.clipboardHistoryStore,
                    onGoBack: runtime.goBack,
                    onDismiss: runtime.dismissLauncher
                )
            )
        )
    }
}
