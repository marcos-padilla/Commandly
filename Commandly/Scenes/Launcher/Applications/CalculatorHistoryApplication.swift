import CommandKit
import Infrastructure
import SwiftUI

@MainActor
struct CalculatorHistoryApplication: LauncherApplication {
    static let id = CommandID(rawValue: "calculator.history")

    private static let manifest = CommandManifest(
        id: id,
        title: "Calculation History",
        subtitle: "Browse and copy results from this session",
        systemImage: "clock.arrow.circlepath",
        category: .productivity,
        mode: .view,
        keywords: ["calculator", "math", "results", "answers"],
        badgeTitle: "Application",
        defaultActions: [
            CommandActionDescriptor(
                id: BuiltInCommandActionID.copy,
                title: "Copy Result",
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
        kind: .application,
        order: 25,
        documentation: RegisteredApplicationDocumentation.calculatorHistory
    )

    private let sessionStore: CalculatorSessionStore
    private let pasteboard: any PasteboardAccessing

    init(
        sessionStore: CalculatorSessionStore,
        pasteboard: any PasteboardAccessing
    ) {
        self.sessionStore = sessionStore
        self.pasteboard = pasteboard
    }

    func launch(in context: LauncherApplicationContext) -> LauncherApplicationLaunch {
        let model = CalculatorHistoryViewModel(
            sessionStore: sessionStore,
            pasteboard: pasteboard,
            onGoBack: context.navigation.goBack
        )
        return .present(
            LauncherApplicationSession(manifest: Self.manifest, model: model) {
                CalculatorHistoryView(viewModel: $0)
            }
        )
    }
}

extension CalculatorHistoryViewModel: LauncherApplicationModel {}
