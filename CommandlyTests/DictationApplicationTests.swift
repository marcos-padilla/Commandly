import CommandKit
import Testing
@testable import Commandly

@MainActor
struct DictationApplicationTests {
    @Test func catalogRegistersDictationAndItsExplicitEntryPoints() {
        let registry = LauncherApplicationRegistry.makeBuiltIn()
        for id in [DictationApplication.id, DictationApplication.openToolID, DictationApplication.historyToolID] {
            #expect(registry.definition(for: id) != nil)
            #expect(registry.isLaunchableCommand(id))
        }
    }

    @Test func toolsOpenReviewOrHistoryWithoutCapturePermissionOrNetwork() async throws {
        let context = DictationTestContext(); let app = DictationApplication(services: context.services)
        #expect(app.definition.id.rawValue == "text.dictation")
        #expect(app.toolDefinitions.map(\.id) == [DictationApplication.openToolID, DictationApplication.historyToolID])
        #expect(app.definition.documentation != nil)
        let navigation = LauncherApplicationContext(navigation: LauncherApplicationNavigation(dismissLauncher: {}, openSettings: {}, goBack: {}),
            settings: LauncherApplicationResolvedSettings(alias: "", hotKey: nil, isEnabled: true, configuration: [:]))
        for id in [DictationApplication.openToolID, DictationApplication.historyToolID] {
            let result = app.launch(toolID: id, arguments: CommandArguments(), in: navigation)
            guard case .present(let session) = result else { Issue.record("Expected Dictation session"); return }
            let model = try #require(session.model(as: DictationViewModel.self))
            #expect(model.showsHistory == (id == DictationApplication.historyToolID))
            model.load(); await model.waitForLoadingForTesting(); await model.history.waitForWorkForTesting()
            #expect(await context.permission.requests == 0)
            #expect(await context.capture.requests.isEmpty)
            #expect(await context.style.requests.isEmpty)
            #expect(await context.pasteboard.values.isEmpty)
            session.stop()
        }
    }
}
