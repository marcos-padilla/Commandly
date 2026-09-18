import CommandKit
import Testing
@testable import Commandly

@Suite("Emoji Search application entries")
@MainActor
struct EmojiSearchApplicationTests {
    @Test func builtInCatalogRegistersDedicatedApplicationAndBothTools() {
        let registry = LauncherApplicationRegistry.makeBuiltIn()
        for id in [EmojiSearchApplication.id, EmojiSearchApplication.openToolID, EmojiSearchApplication.semanticToolID] {
            #expect(registry.definition(for: id) != nil)
        }
    }

    @Test func preservesExistingEntryIDsAndExposesSeparateExplicitAIEntry() async throws {
        let app = try await makeApplication()
        #expect(app.definition.id.rawValue == "tools.emoji-search")
        #expect(app.toolDefinitions.map(\.id.rawValue) == ["tools.emoji-search.tool.open", "tools.emoji-search.ai"])
        #expect(app.toolDefinitions.allSatisfy { $0.parentID == app.definition.id })
        #expect(app.definition.documentation != nil)
    }
    @Test func openingEitherModeDoesNotSendPromptOrCopy() async throws {
        let catalog = ControlledEmojiCatalog(try await EmojiTestData.catalog())
        let semantic = ControlledEmojiSemanticSearch()
        let board = EmojiPasteboardFake()
        let app = EmojiSearchApplication(services: .init(catalog: catalog, semantic: semantic, pasteboard: board))
        for toolID in [EmojiSearchApplication.openToolID, EmojiSearchApplication.semanticToolID] {
            let launch = app.launch(toolID: toolID, arguments: CommandArguments(), in: context())
            guard case .present(let session) = launch else { Issue.record("Expected an emoji application session"); return }
            let model = try #require(session.model(as: EmojiSearchViewModel.self))
            #expect(model.mode == (toolID == EmojiSearchApplication.openToolID ? .local : .ai))
            model.start(); await model.waitForLoadingForTesting()
            #expect(await semantic.requestCount == 0)
            #expect(await board.writes.isEmpty)
            session.stop()
        }
    }
    private func makeApplication() async throws -> EmojiSearchApplication {
        EmojiSearchApplication(services: .init(catalog: ControlledEmojiCatalog(try await EmojiTestData.catalog()),
            semantic: ControlledEmojiSemanticSearch(), pasteboard: EmojiPasteboardFake()))
    }
    private func context() -> LauncherApplicationContext {
        LauncherApplicationContext(navigation: LauncherApplicationNavigation(dismissLauncher: {}, openSettings: {}, goBack: {}),
            settings: LauncherApplicationResolvedSettings(alias: "", hotKey: nil, isEnabled: true, configuration: [:]))
    }
}
