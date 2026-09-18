import CommandKit
import Testing
@testable import Commandly

@MainActor
struct QuickAIApplicationTests {
    @Test func applicationCreatesAnInertSessionAndRoutesAISettings() throws {
        let service = ControlledQuickAIService(catalog: .empty)
        let application = QuickAIApplication(services: .init(chat: service))
        var openedSettings = false
        let context = LauncherApplicationContext(navigation: .init(dismissLauncher: {}, openSettings: {},
            openAISettings: { openedSettings = true }, goBack: {}),
            settings: .init(alias: "", hotKey: nil, isEnabled: true, configuration: [:]))
        guard case .present(let session) = application.launch(in: context) else {
            Issue.record("Expected Quick AI session")
            return
        }
        let model = try #require(session.model(as: QuickAIViewModel.self))
        #expect(model.isLoading == false)
        #expect(model.entries.isEmpty)
        model.perform(QuickAIActionID.settings)
        #expect(openedSettings)
        #expect(application.definition.kind == .aiExtension)
        #expect(application.toolDefinitions.map(\.id) == [QuickAIApplication.openToolID])
        #expect(application.toolDefinitions.first?.parentID == QuickAIApplication.id)
        session.stop()
    }
}
