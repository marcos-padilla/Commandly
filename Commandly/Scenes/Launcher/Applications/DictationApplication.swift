import CommandKit
import SwiftUI

@MainActor
struct DictationApplication: LauncherApplication {
    static let id = CommandID(rawValue: "text.dictation")
    static let openToolID = CommandID(rawValue: "text.dictation.tool.open")
    static let historyToolID = CommandID(rawValue: "text.dictation.history")
    static let manifest = CommandManifest(id: id, title: "Dictation", subtitle: "Transcribe speech on this Mac, review, and copy",
        systemImage: "waveform", category: .productivity, mode: .view,
        keywords: ["dictate", "speech", "voice", "transcription", "microphone", "multilingual", "writing style", "dictation history"], badgeTitle: "Application")
    let definition = LauncherApplicationDefinition(manifest: Self.manifest, parentID: BuiltInLauncherApplicationGroup.catalogID,
        kind: .application, order: 48, documentation: RegisteredApplicationDocumentation.dictation)
    private let services: DictationApplicationServices
    init(services: DictationApplicationServices) { self.services = services }
    var toolDefinitions: [LauncherApplicationDefinition] {
        [.tool(id: Self.openToolID, parentID: Self.id, title: "Open Dictation", subtitle: "Choose a language, then explicitly start the microphone",
               systemImage: "mic", keywords: ["voice", "speech", "dictate", "transcribe"]),
         .tool(id: Self.historyToolID, parentID: Self.id, title: "Saved Dictations", subtitle: "Review, copy, or delete text you explicitly saved",
               systemImage: "clock.arrow.circlepath", keywords: ["voice history", "dictation history", "transcript"])]
    }
    func launch(in context: LauncherApplicationContext) -> LauncherApplicationLaunch { makeLaunch(history: false, context: context) }
    func launch(toolID: CommandID, arguments: CommandArguments, in context: LauncherApplicationContext) -> LauncherApplicationLaunch {
        _ = arguments
        guard toolID == Self.openToolID || toolID == Self.historyToolID else { return .message("This dictation tool is unavailable.") }
        return makeLaunch(history: toolID == Self.historyToolID, context: context)
    }
    private func makeLaunch(history: Bool, context: LauncherApplicationContext) -> LauncherApplicationLaunch {
        let model = DictationViewModel(services: services, onGoBack: context.navigation.goBack, onAISettings: context.navigation.openAISettings)
        if history { model.presentHistory() }
        return .present(LauncherApplicationSession(manifest: Self.manifest, model: model) { DictationView(viewModel: $0) })
    }
}
