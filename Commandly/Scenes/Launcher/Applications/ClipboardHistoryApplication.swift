import CommandKit
import SwiftUI

@MainActor
struct ClipboardHistoryApplication: LauncherApplication {
    private let store: ClipboardHistoryStore

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

    init(store: ClipboardHistoryStore) {
        self.store = store
    }

    func launch(in context: LauncherApplicationContext) -> LauncherApplicationLaunch {
        let model = ClipboardHistoryViewModel(
            store: store,
            onGoBack: context.navigation.goBack,
            onDismiss: context.navigation.dismissLauncher
        )
        return .present(
            LauncherApplicationSession(manifest: manifest, model: model) {
                ClipboardHistoryView(viewModel: $0)
            }
        )
    }
}

extension ClipboardHistoryViewModel: LauncherApplicationModel {}
