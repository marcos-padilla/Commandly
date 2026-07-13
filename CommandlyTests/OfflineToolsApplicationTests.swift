import Foundation
import CommandKit
import Testing
@testable import Commandly

struct OfflineToolsApplicationTests {
    @Test @MainActor func textCaseConverterHandlesNamingAndSentenceStyles() {
        #expect(TextCaseConverter.convert("hello useful world", to: .uppercase) == "HELLO USEFUL WORLD")
        #expect(TextCaseConverter.convert("hello useful world", to: .camel) == "helloUsefulWorld")
        #expect(TextCaseConverter.convert("helloUsefulWorld", to: .snake) == "hello_useful_world")
        #expect(TextCaseConverter.convert("hello useful world", to: .pascal) == "HelloUsefulWorld")
        #expect(TextCaseConverter.convert("HELLO WORLD", to: .sentence) == "Hello world")
        #expect(TextCaseConverter.convert("hello useful world", to: .constant) == "HELLO_USEFUL_WORLD")
    }

    @Test @MainActor func colorParserConvertsHexRGBAndHSL() throws {
        let color = try #require(CommandlyColor(string: "#4A7DFF"))
        #expect(color.hex == "#4A7DFF")
        #expect(color.rgb == "rgb(74, 125, 255)")
        #expect(color.hsl == "hsl(223, 100%, 65%)")

        let translucent = try #require(CommandlyColor(string: "rgba(255, 0, 128, 0.5)"))
        #expect(translucent.hex == "#FF008080")
        #expect(CommandlyColor(string: "not-a-color") == nil)
    }

    @Test @MainActor func emojiCatalogIsLocalSearchableAndUnique() {
        #expect(EmojiCatalog.entries.count > 200)
        #expect(Set(EmojiCatalog.entries.map(\.id)).count == EmojiCatalog.entries.count)
        #expect(EmojiCatalog.entries.filter { $0.matches("heart") }.isEmpty == false)
        #expect(EmojiCatalog.entries.filter { $0.matches("sun") }.isEmpty == false)
    }

    @Test @MainActor func typingPracticeCalculatesAccuracyAndSpeed() {
        let result = TypingPracticeEngine.result(
            typed: TypingPracticeEngine.prompt,
            elapsed: 60
        )
        #expect(result.accuracyPercent == 100)
        #expect(result.wordsPerMinute > 0)

        let inaccurate = TypingPracticeEngine.result(typed: "xxxx", elapsed: 60)
        #expect(inaccurate.accuracyPercent < 100)
    }

    @Test @MainActor func dictionaryModelLooksUpAndCopiesLocalDefinition() async {
        let pasteboard = InMemoryPasteboard()
        let services = OfflineToolsServices(
            pasteboard: pasteboard,
            dictionary: StubDictionaryLookup(definition: "A reliable command launcher."),
            colorSampler: StubColorSampler(),
            fontCatalog: StubFontCatalog(families: ["Helvetica", "Menlo"])
        )
        let model = OfflineToolsViewModel(tool: .dictionary, services: services, onGoBack: {})
        model.query = "commandly"

        model.lookupDefinition()
        await model.flushLookupForTesting()
        #expect(model.dictionaryDefinition == "A reliable command launcher.")

        model.perform(BuiltInCommandActionID.copy)
        await model.flushCopyForTesting()
        #expect(pasteboard.currentValue == "A reliable command launcher.")
    }

    @Test @MainActor func everyOfflineToolBuildsABranchFreeApplicationSession() throws {
        let services = OfflineToolsServices(
            pasteboard: InMemoryPasteboard(),
            dictionary: StubDictionaryLookup(definition: nil),
            colorSampler: StubColorSampler(),
            fontCatalog: StubFontCatalog(families: ["Menlo"])
        )
        let context = LauncherApplicationContext(
            navigation: LauncherApplicationNavigation(
                dismissLauncher: {},
                openSettings: {},
                goBack: {}
            ),
            settings: LauncherApplicationResolvedSettings(
                alias: "",
                hotKey: nil,
                isEnabled: true,
                configuration: [:]
            )
        )

        for tool in OfflineToolKind.allCases {
            let application = OfflineToolsApplication(tool: tool, services: services)
            guard case .present(let session) = application.launch(in: context) else {
                Issue.record("Expected a view session for \(tool.title)")
                continue
            }
            #expect(session.model(as: OfflineToolsViewModel.self)?.tool == tool)
            #expect(application.definition.commandManifest?.mode == .view)
        }
    }
}

private struct StubDictionaryLookup: DictionaryLookingUp {
    let definition: String?

    func definition(for word: String) async -> String? {
        _ = word
        return definition
    }
}

@MainActor
private final class StubColorSampler: ColorSampling {
    func sample() async -> CommandlyColor? {
        CommandlyColor(red: 1, green: 0, blue: 0)
    }
}

@MainActor
private final class StubFontCatalog: FontCatalogProviding {
    let availableFamilies: [String]

    init(families: [String]) {
        availableFamilies = families
    }
}
