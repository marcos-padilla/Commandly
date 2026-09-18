import CommandKit
import MarkdownPreviewKit
import Testing
@testable import Commandly

@Suite("Markdown Preview application")
@MainActor
struct MarkdownPreviewApplicationTests {
    @Test
    func builtInRegistryDeclaresDocumentApplicationSettingsAndDocumentation() throws {
        let registry = LauncherApplicationRegistry.makeBuiltIn(
            markdownPreviewServices: .inMemory
        )
        let definition = try #require(
            registry.definition(for: MarkdownPreviewApplication.applicationID)
        )
        let settings = try #require(registry.resolvedSettings(for: definition.id))

        #expect(definition.kind == .application)
        #expect(definition.parentID == BuiltInLauncherApplicationGroup.catalogID)
        #expect(definition.commandManifest?.mode == .view)
        #expect(definition.commandManifest?.title == "Markdown Preview")
        #expect(definition.documentation != nil)
        #expect(definition.configurationFields.count == 15)
        #expect(Set(definition.configurationFields.compactMap(\.section)) == [
            "Appearance", "Rendering", "Typography", "Reading",
        ])
        #expect(definition.configurationFields.allSatisfy { $0.section?.isEmpty == false })
        #expect(MarkdownPreviewApplication.configuration(from: settings) == .default)
        #expect(registry.allManifests().contains { $0.id == definition.id })
    }

    @Test
    func configurationParsesSelectionsTogglesAndClampsNumericValues() {
        let settings = LauncherApplicationResolvedSettings(
            alias: "",
            hotKey: nil,
            isEnabled: true,
            configuration: [
                MarkdownPreviewApplication.Setting.previewTheme: .text(MarkdownTheme.dark.rawValue),
                MarkdownPreviewApplication.Setting.codeTheme: .text(MarkdownCodeTheme.monokai.rawValue),
                MarkdownPreviewApplication.Setting.defaultView: .text(SourceViewMode.source.rawValue),
                MarkdownPreviewApplication.Setting.enableMermaid: .boolean(false),
                MarkdownPreviewApplication.Setting.enableMath: .boolean(false),
                MarkdownPreviewApplication.Setting.enableEmoji: .boolean(false),
                MarkdownPreviewApplication.Setting.enableTypst: .boolean(false),
                MarkdownPreviewApplication.Setting.collapseBlockquotes: .boolean(true),
                MarkdownPreviewApplication.Setting.showLineNumbers: .boolean(true),
                MarkdownPreviewApplication.Setting.showOutline: .boolean(false),
                MarkdownPreviewApplication.Setting.automaticReload: .boolean(false),
                MarkdownPreviewApplication.Setting.rememberScroll: .boolean(false),
                MarkdownPreviewApplication.Setting.baseFontSize: .integer(200),
                MarkdownPreviewApplication.Setting.finderFontSize: .integer(-20),
                MarkdownPreviewApplication.Setting.defaultZoom: .decimal(99),
            ]
        )

        let configuration = MarkdownPreviewApplication.configuration(from: settings)

        #expect(configuration.theme == .dark)
        #expect(configuration.codeTheme == .monokai)
        #expect(configuration.sourceViewMode == .source)
        #expect(configuration.enablesMermaid == false)
        #expect(configuration.enablesMath == false)
        #expect(configuration.mathMode == .disabled)
        #expect(configuration.enablesEmoji == false)
        #expect(configuration.enablesTypst == false)
        #expect(configuration.collapsesBlockquotes)
        #expect(configuration.showsLineNumbers)
        #expect(configuration.showsTableOfContents == false)
        #expect(configuration.automaticallyReloads == false)
        #expect(configuration.remembersScrollPosition == false)
        #expect(configuration.fontSize == MarkdownPreviewConfiguration.fontSizeRange.upperBound)
        #expect(
            configuration.finderFontSize
                == MarkdownPreviewConfiguration.finderFontSizeRange.lowerBound
        )
        #expect(configuration.initialZoom == MarkdownPreviewConfiguration.zoomRange.upperBound)
    }

    @Test
    func launchCreatesAnEmptySessionWithResolvedReadingDefaults() throws {
        let application = MarkdownPreviewApplication(services: .inMemory)
        let settings = LauncherApplicationResolvedSettings(
            alias: "",
            hotKey: nil,
            isEnabled: true,
            configuration: [
                MarkdownPreviewApplication.Setting.defaultView: .text(SourceViewMode.source.rawValue),
                MarkdownPreviewApplication.Setting.automaticReload: .boolean(false),
                MarkdownPreviewApplication.Setting.defaultZoom: .decimal(1.25),
            ]
        )
        let context = LauncherApplicationContext(
            navigation: LauncherApplicationNavigation(
                dismissLauncher: {},
                openSettings: {},
                goBack: {}
            ),
            settings: settings
        )

        guard case .present(let session) = application.launch(in: context) else {
            Issue.record("Expected Markdown Preview to present a session")
            return
        }
        let model = try #require(session.model(as: MarkdownPreviewViewModel.self))

        #expect(model.state == .empty)
        #expect(model.showsSource)
        #expect(model.autoReload == false)
        #expect(model.zoom == 1.25)
        #expect(model.footerActions.first?.id == MarkdownPreviewActionID.chooseDocument)

        session.stop()
        #expect(model.state == .empty)
    }

    @Test
    func toolsSeparateOpeningTheReaderFromChoosingADocument() throws {
        let application = MarkdownPreviewApplication(services: .inMemory)
        let tools = application.toolDefinitions

        #expect(tools.count == 2)
        #expect(tools.map(\.id) == [
            MarkdownPreviewApplication.openToolID,
            MarkdownPreviewApplication.chooseDocumentToolID,
        ])
        #expect(tools.allSatisfy { $0.kind == .tool })
        #expect(tools.allSatisfy {
            $0.parentID == MarkdownPreviewApplication.applicationID
        })

        guard case .present(let openSession) = application.launch(
            toolID: MarkdownPreviewApplication.openToolID,
            arguments: CommandArguments(),
            in: makeContext()
        ) else {
            Issue.record("Expected Open Markdown Preview to present a session")
            return
        }
        let openModel = try #require(
            openSession.model(as: MarkdownPreviewViewModel.self)
        )
        #expect(openModel.showsDocumentPicker == false)

        guard case .present(let chooseSession) = application.launch(
            toolID: MarkdownPreviewApplication.chooseDocumentToolID,
            arguments: CommandArguments(),
            in: makeContext()
        ) else {
            Issue.record("Expected Choose Markdown File to present a session")
            return
        }
        let chooseModel = try #require(
            chooseSession.model(as: MarkdownPreviewViewModel.self)
        )
        #expect(chooseModel.showsDocumentPicker)

        openSession.stop()
        chooseSession.stop()
    }

    private func makeContext() -> LauncherApplicationContext {
        LauncherApplicationContext(
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
    }
}
