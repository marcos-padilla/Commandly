import CommandKit
import SwiftUI

@MainActor
struct ClipboardHistoryApplication: LauncherApplication {
    private let store: ClipboardHistoryStore

    private static let manifest = CommandManifest(
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

    let definition = LauncherApplicationDefinition(
        manifest: Self.manifest,
        parentID: BuiltInLauncherApplicationGroup.catalogID,
        kind: .extension,
        order: 10,
        configurationFields: [
            LauncherConfigurationField(
                id: "default-filter",
                variable: "defaultFilter",
                title: "Default filter",
                description: "Choose which clipboard items appear when the application opens.",
                kind: .selection,
                defaultValue: .text(ClipboardHistoryFilter.all.rawValue),
                options: ClipboardHistoryFilter.allCases.map {
                    LauncherConfigurationOption(id: $0.rawValue, title: $0.title)
                }
            )
        ],
        documentation: RegisteredApplicationDocumentation.clipboardHistory
    )

    init(store: ClipboardHistoryStore) {
        self.store = store
    }

    func launch(in context: LauncherApplicationContext) -> LauncherApplicationLaunch {
        let configuredFilter = context.settings.value(for: "defaultFilter")?.textValue
            .flatMap { ClipboardHistoryFilter(rawValue: $0) } ?? .all
        let model = ClipboardHistoryViewModel(
            store: store,
            initialFilter: configuredFilter,
            onGoBack: context.navigation.goBack,
            onDismiss: context.navigation.dismissLauncher
        )
        return .present(
            LauncherApplicationSession(manifest: Self.manifest, model: model) {
                ClipboardHistoryView(viewModel: $0)
            }
        )
    }
}

extension ClipboardHistoryViewModel: LauncherApplicationModel {}
