import CommandKit
import SwiftUI

@MainActor
struct TranslationApplication: LauncherApplication {
    static let applicationID = CommandID(rawValue: "text.translate")
    static let wordToolID = CommandID(rawValue: "text.translate.word")
    static let manifest = CommandManifest(
        id: applicationID, title: "Translate", subtitle: "Translate text with native language detection",
        systemImage: "character.bubble", category: .productivity, mode: .view,
        keywords: ["translate", "translation", "language", "detect language", "word translation"], badgeTitle: "Application",
        defaultActions: [.init(id: TranslationActionID.translate, title: "Translate", isPrimary: true, keyHint: CommandKeyHint(symbols: ["⌘", "↩"]))]
    )
    let definition = LauncherApplicationDefinition(manifest: Self.manifest, parentID: BuiltInLauncherApplicationGroup.catalogID,
        kind: .application, order: 46, documentation: RegisteredApplicationDocumentation.translation)
    private let services: TranslationApplicationServices
    init(services: TranslationApplicationServices) { self.services = services }
    var toolDefinitions: [LauncherApplicationDefinition] {
        [.tool(id: Self.wordToolID, parentID: Self.applicationID, title: "Translate a Word",
               subtitle: "Choose a target, type a word, and press Return", systemImage: "character.bubble.fill",
               keywords: ["word", "quick translation", "translate word", "language"])]
    }
    func launch(in context: LauncherApplicationContext) -> LauncherApplicationLaunch { makeLaunch(word: false, context: context) }
    func launch(toolID: CommandID, arguments: CommandArguments, in context: LauncherApplicationContext) -> LauncherApplicationLaunch {
        _ = arguments
        guard toolID == Self.wordToolID else { return .message("Translation entry is unavailable.") }
        return makeLaunch(word: true, context: context)
    }
    private func makeLaunch(word: Bool, context: LauncherApplicationContext) -> LauncherApplicationLaunch {
        let services = services.freshSession()
        let model = TranslationViewModel(services: services, isWordMode: word, onGoBack: context.navigation.goBack)
        return .present(LauncherApplicationSession(manifest: Self.manifest, model: model) {
            TranslationView(viewModel: $0, nativeBridge: services.nativeBridge)
        })
    }
}
