import CommandKit
import Foundation
import Testing
@testable import Commandly

@MainActor
struct DocumentationTests {
    @Test func coreDocumentationIncludesTheCompleteFirstRunFlow() throws {
        let article = try #require(
            CoreDocumentationCatalog.articles.first { $0.id == "core.first-run" }
        )

        #expect(article.documentation.sections.map(\.id) == [
            "first-run-flow",
            "first-run-preferences",
            "first-run-permissions",
            "first-run-navigation",
        ])
        guard case .steps(let steps) = article.documentation.sections[0].blocks[0].content else {
            Issue.record("Expected the first-run article to start with setup steps")
            return
        }
        #expect(steps.count == OnboardingStep.allCases.count)
    }

    @Test func offlineToolMetadataOnlyPublishesVerifiedReturnShortcuts() throws {
        let articles = DocumentationCatalog.articles(
            registry: LauncherApplicationRegistry.makeBuiltIn(),
            coreArticles: []
        )
        let toolsWithReturn: [OfflineToolKind] = [.emoji, .dictionary, .fonts]

        for tool in OfflineToolKind.allCases {
            let applicationID = CommandID(rawValue: tool.commandID)
            let article = try #require(
                articles.first { $0.applicationID == applicationID }
            )
            let publishesReturn = article.defaultActions.contains {
                $0.keyHint == .return
            }
            #expect(publishesReturn == toolsWithReturn.contains(tool))
        }
    }

    @Test func everyBuiltInLaunchableApplicationHasExactlyOneArticle() {
        let registry = LauncherApplicationRegistry.makeBuiltIn()
        let launchableDefinitions = registry.allDefinitions().filter {
            registry.application(for: $0.id) != nil
        }
        let applicationArticles = DocumentationCatalog.articles(
            registry: registry,
            coreArticles: []
        )

        #expect(launchableDefinitions.isEmpty == false)
        #expect(applicationArticles.count == launchableDefinitions.count)
        #expect(
            Set(applicationArticles.compactMap(\.applicationID)).count
                == applicationArticles.count
        )

        for definition in launchableDefinitions {
            #expect(definition.commandManifest != nil)
            #expect(definition.documentation != nil)
            #expect(
                applicationArticles.count { $0.applicationID == definition.id } == 1
            )
        }
    }

    @Test func disabledApplicationsRemainDocumented() throws {
        let registry = LauncherApplicationRegistry.makeBuiltIn()
        var preferences = LauncherApplicationPreferences.empty
        preferences.isEnabled = false
        registry.savePreferences(preferences, for: BuiltInCommandID.searchFiles)

        let article = try #require(
            DocumentationCatalog.articles(registry: registry, coreArticles: [])
                .first { $0.applicationID == BuiltInCommandID.searchFiles }
        )

        #expect(article.isEnabled == false)
        #expect(article.statusLabel == "Disabled")
        #expect(
            registry.allManifests().contains { $0.id == BuiltInCommandID.searchFiles }
                == false
        )
    }

    @Test func refreshResolvesCurrentAliasAndGlobalHotKey() throws {
        let preferencesStore = InMemoryLauncherApplicationPreferencesStore()
        let registry = LauncherApplicationRegistry.makeBuiltIn(
            preferencesStore: preferencesStore
        )
        let viewModel = DocumentationViewModel(registry: registry, coreArticles: [])
        let original = try #require(
            viewModel.articles.first { $0.applicationID == BuiltInCommandID.searchFiles }
        )
        #expect(original.alias == nil)

        var preferences = LauncherApplicationPreferences.empty
        preferences.alias = "  Finder Pro  "
        preferences.hotKey = LauncherHotKey(
            keyCode: 2,
            modifiers: [.control, .option]
        )
        preferences.hasHotKeyOverride = true
        registry.savePreferences(preferences, for: BuiltInCommandID.searchFiles)
        viewModel.refresh()

        let refreshed = try #require(
            viewModel.articles.first { $0.applicationID == BuiltInCommandID.searchFiles }
        )
        #expect(refreshed.alias == "Finder Pro")
        #expect(refreshed.globalHotKey == "⌃⌥D")
    }

    @Test func searchMatchesFoldedProseExamplesShortcutsAndAliases() throws {
        let applicationID = CommandID(rawValue: "test.documentation-search")
        let registry = LauncherApplicationRegistry()
        try registry.register(
            RawDocumentationTestApplication(
                definition: DocumentationTestFixtures.definition(
                    id: applicationID,
                    title: "Index Fixture",
                    documentation: LauncherApplicationDocumentation(
                        category: .utilities,
                        overview: "A neutral overview for the search fixture.",
                        sections: [
                            DocumentationSection(
                                id: "fixture.search",
                                title: "Search Sources",
                                blocks: [
                                    .paragraph("fixture.prose", "Café narrative"),
                                    .examples("fixture.examples", [
                                        DocumentationExample(
                                            id: "fixture.example",
                                            input: "Crème brûlée conversion"
                                        )
                                    ]),
                                    .shortcuts("fixture.shortcuts", [
                                        DocumentationShortcut(
                                            id: "fixture.shortcut",
                                            title: "Déployer flow",
                                            keys: ["⌥", "D"]
                                        )
                                    ])
                                ]
                            )
                        ]
                    )
                )
            )
        )
        var preferences = LauncherApplicationPreferences.empty
        preferences.alias = "ÜberAlias"
        registry.savePreferences(preferences, for: applicationID)
        let viewModel = DocumentationViewModel(registry: registry, coreArticles: [])

        for query in ["CAFE", "CREME BRULEE", "DEPLOYER", "UBERALIAS"] {
            viewModel.query = query
            #expect(viewModel.filteredArticles.map(\.applicationID) == [applicationID])
        }
    }

    @Test func selectionFallsBackWhenFilteringHidesTheCurrentArticle() {
        let registry = LauncherApplicationRegistry()
        let alpha = DocumentationTestFixtures.coreArticle(
            id: "core.alpha",
            title: "Alpha",
            order: 1,
            marker: "Alpha marker"
        )
        let beta = DocumentationTestFixtures.coreArticle(
            id: "core.beta",
            title: "Beta",
            order: 2,
            marker: "Beta marker"
        )
        let viewModel = DocumentationViewModel(
            registry: registry,
            coreArticles: [alpha, beta]
        )

        #expect(viewModel.selectedArticleID == alpha.id)
        viewModel.select(beta.id)
        #expect(viewModel.selectedArticleID == beta.id)

        viewModel.query = "ALPHA MARKER"
        #expect(viewModel.selectedArticleID == alpha.id)
        #expect(viewModel.selectedArticle?.id == alpha.id)

        viewModel.query = "no matching article"
        #expect(viewModel.selectedArticleID == nil)
        #expect(viewModel.selectedArticle == nil)

        viewModel.clearSearch()
        #expect(viewModel.selectedArticleID == alpha.id)
    }

    @Test func newlyRegisteredApplicationAppearsAfterCatalogRefresh() throws {
        let registry = LauncherApplicationRegistry()
        let viewModel = DocumentationViewModel(registry: registry, coreArticles: [])
        let applicationID = CommandID(rawValue: "test.documentation-auto-registration")
        #expect(viewModel.articles.isEmpty)

        try registry.register(
            RawDocumentationTestApplication(
                definition: DocumentationTestFixtures.definition(
                    id: applicationID,
                    title: "New Native Tool",
                    documentation: DocumentationTestFixtures.validDocumentation
                )
            )
        )
        viewModel.refresh()

        #expect(viewModel.articles.map(\.applicationID) == [applicationID])
        #expect(viewModel.articles.first?.title == "New Native Tool")
    }

    @Test func registryRejectsLaunchableApplicationWithoutDocumentation() {
        let applicationID = CommandID(rawValue: "test.documentation-missing")
        let registry = LauncherApplicationRegistry()
        let application = RawDocumentationTestApplication(
            definition: DocumentationTestFixtures.definition(
                id: applicationID,
                title: "Missing Documentation",
                documentation: nil
            )
        )

        do {
            try registry.register(application)
            Issue.record("Expected missing application documentation to be rejected")
        } catch let error as LauncherApplicationRegistryError {
            #expect(
                error == .invalidDefinition(
                    applicationID,
                    reason: "Launchable applications require documentation."
                )
            )
        } catch {
            Issue.record("Unexpected registry error: \(error)")
        }
    }

    @Test func registryRejectsMalformedApplicationDocumentation() {
        let applicationID = CommandID(rawValue: "test.documentation-malformed")
        let duplicateBlockID = "fixture.duplicate"
        let malformed = LauncherApplicationDocumentation(
            category: .utilities,
            overview: "This overview is present.",
            sections: [
                DocumentationSection(
                    id: "fixture.first",
                    title: "First",
                    blocks: [.paragraph(duplicateBlockID, "First paragraph")]
                ),
                DocumentationSection(
                    id: "fixture.second",
                    title: "Second",
                    blocks: [.paragraph(duplicateBlockID, "Second paragraph")]
                )
            ]
        )
        let registry = LauncherApplicationRegistry()

        do {
            try registry.register(
                RawDocumentationTestApplication(
                    definition: DocumentationTestFixtures.definition(
                        id: applicationID,
                        title: "Malformed Documentation",
                        documentation: malformed
                    )
                )
            )
            Issue.record("Expected malformed application documentation to be rejected")
        } catch let error as LauncherApplicationRegistryError {
            #expect(
                error == .invalidDefinition(
                    applicationID,
                    reason: "Documentation blocks must have unique IDs and nonempty content."
                )
            )
        } catch {
            Issue.record("Unexpected registry error: \(error)")
        }
    }

    @Test func calculatorDocumentationCoversMajorImplementedDomains() {
        let article = CalculatorDocumentationArticle.article
        let sections = article.documentation.sections
        let sectionIDs = Set(sections.map(\.id))
        let requiredSectionIDs: Set<String> = [
            "calculator-use-result",
            "calculator-arithmetic",
            "calculator-scientific",
            "calculator-percentages",
            "calculator-units",
            "calculator-currency",
            "calculator-calendar",
            "calculator-time-zones",
            "calculator-finance-pay",
            "calculator-developer",
            "calculator-session-memory",
            "calculator-ambiguities-limitations"
        ]
        let exampleCount = sections
            .flatMap(\.blocks)
            .reduce(into: 0) { count, block in
                guard case .examples(let examples) = block.content else { return }
                count += examples.count
            }

        #expect(article.id == "core.calculator")
        #expect(sections.count >= 15)
        #expect(requiredSectionIDs.isSubset(of: sectionIDs))
        #expect(exampleCount >= 150)
    }

    @Test func rootAppMenuOpensDocumentationFirstAndDismissesLauncher() throws {
        var events: [String] = []
        let viewModel = LauncherViewModel(
            onDismiss: { events.append("dismiss") },
            onOpenDocumentation: { events.append("documentation") }
        )

        #expect(viewModel.appMenuActions.map(\.id) == [
            BuiltInCommandActionID.documentation,
            BuiltInCommandActionID.settings,
            BuiltInCommandActionID.quit
        ])
        let documentationAction = try #require(viewModel.appMenuActions.first)
        #expect(documentationAction.title == "Documentation")
        #expect(documentationAction.keyHint == CommandKeyHint(symbols: ["⌘", "?"]))

        viewModel.performFooterAction(BuiltInCommandActionID.documentation)

        #expect(events == ["dismiss", "documentation"])
    }
}

@MainActor
enum DocumentationTestFixtures {
    static let validDocumentation = LauncherApplicationDocumentation(
        category: .utilities,
        overview: "Fixture documentation for a registered launcher application.",
        sections: [
            DocumentationSection(
                id: "fixture.overview",
                title: "Overview",
                blocks: [
                    .paragraph(
                        "fixture.overview.summary",
                        "This application exists only to verify documentation registration."
                    )
                ]
            )
        ],
        keywords: ["fixture"]
    )

    static func definition(
        id: CommandID,
        title: String,
        documentation: LauncherApplicationDocumentation?
    ) -> LauncherApplicationDefinition {
        let manifest = CommandManifest(
            id: id,
            title: title,
            subtitle: "Documentation test fixture",
            systemImage: "doc.text",
            category: .productivity,
            mode: .view,
            keywords: ["fixture"],
            defaultActions: []
        )
        return LauncherApplicationDefinition(
            id: id,
            kind: .application,
            title: title,
            subtitle: manifest.subtitle,
            systemImage: manifest.systemImage,
            commandManifest: manifest,
            documentation: documentation
        )
    }

    static func coreArticle(
        id: String,
        title: String,
        order: Int,
        marker: String
    ) -> CoreDocumentationArticle {
        CoreDocumentationArticle(
            id: id,
            title: title,
            subtitle: nil,
            systemImage: "doc.text",
            category: .gettingStarted,
            order: order,
            documentation: LauncherApplicationDocumentation(
                category: .gettingStarted,
                overview: marker,
                sections: [
                    DocumentationSection(
                        id: "\(id).section",
                        title: "\(title) Section",
                        blocks: [.paragraph("\(id).paragraph", marker)]
                    )
                ]
            )
        )
    }
}

@MainActor
private struct RawDocumentationTestApplication: LauncherApplication {
    let definition: LauncherApplicationDefinition

    func launch(in context: LauncherApplicationContext) -> LauncherApplicationLaunch {
        _ = context
        return .message("Documentation fixture")
    }
}
