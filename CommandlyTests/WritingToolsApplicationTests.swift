import CommandKit
import Testing
@testable import Commandly

@MainActor
struct WritingToolsApplicationTests {
    @Test func reviewAndServiceInstructionsHaveDistinctDiscoverableLaunchPaths() throws {
        let app = WritingToolsApplication(services: .inMemory)
        #expect(app.definition.kind == .application)
        #expect(app.toolDefinitions.map(\.id) == [WritingToolsApplication.reviewToolID, WritingToolsApplication.inlineHelpToolID])
        #expect(app.toolDefinitions.last?.subtitle?.contains("Service") == true)
        let context = LauncherApplicationContext(navigation: .init(dismissLauncher: {}, openSettings: {},
            openAISettings: {}, goBack: {}),
            settings: .init(alias: "", hotKey: nil, isEnabled: true, configuration: [:]))
        guard case .present(let review) = app.launch(in: context),
              case .present(let help) = app.launch(toolID: WritingToolsApplication.inlineHelpToolID, arguments: .empty, in: context) else {
            Issue.record("Expected distinct writing tool sessions")
            return
        }
        let reviewModel = try #require(review.model(as: WritingToolsViewModel.self))
        let helpModel = try #require(help.model(as: WritingToolsViewModel.self))
        #expect(reviewModel.showsInlineInstructions == false && reviewModel.isChecking == false)
        #expect(helpModel.showsInlineInstructions && helpModel.isChecking == false)
        review.stop(); help.stop()
    }
}
