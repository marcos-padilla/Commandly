import CommandKit
import Foundation
import Infrastructure
import SearchKit

/// A registered application that can be discovered and launched from Commandly.
///
/// Applications own their feature-specific model and surface construction. The launcher only
/// coordinates discovery, navigation, and the shared application-session contract.
@MainActor
protocol LauncherApplication {
    var definition: LauncherApplicationDefinition { get }

    func launch(in context: LauncherApplicationContext) -> LauncherApplicationLaunch
}

/// Launcher-shell navigation available while constructing an application session.
/// Feature services are injected into each application when it is registered.
@MainActor
struct LauncherApplicationContext {
    let navigation: LauncherApplicationNavigation
    let settings: LauncherApplicationResolvedSettings
}

/// File Search's focused dependency group.
@MainActor
struct FileSearchApplicationServices {
    let searchService: any FileSearching
    let urlOpener: any URLOpening
    let fileRevealer: any FileRevealing
    let fileActionService: any FileActionServicing
    let finderInfoPresenter: any FinderInfoPresenting
    let pasteboard: any PasteboardAccessing
}

/// Navigation callbacks shared by launcher applications.
@MainActor
struct LauncherApplicationNavigation {
    let dismissLauncher: () -> Void
    let openSettings: () -> Void
    let goBack: () -> Void
}

/// Result of launching a registered application.
@MainActor
enum LauncherApplicationLaunch {
    case present(LauncherApplicationSession)
    case openSettings
    case dismiss
    case message(String)
}

enum LauncherApplicationRegistryError: Error, Equatable {
    case duplicateApplication(CommandID)
    case missingParent(child: CommandID, parent: CommandID)
    case invalidParent(CommandID)
    case invalidDefinition(CommandID, reason: String)
}

/// The single source of truth for applications exposed by the launcher.
@MainActor
final class LauncherApplicationRegistry {
    private let preferencesStore: any LauncherApplicationPreferencesStoring
    private var definitions: [CommandID: LauncherApplicationDefinition] = [:]
    private var applications: [CommandID: any LauncherApplication] = [:]
    private var rootIDs: Set<CommandID> = []
    private var childIDsByParent: [CommandID: Set<CommandID>] = [:]

    init(
        preferencesStore: any LauncherApplicationPreferencesStoring =
            InMemoryLauncherApplicationPreferencesStore()
    ) {
        self.preferencesStore = preferencesStore
    }

    func register(_ definition: LauncherApplicationDefinition) throws {
        try validate(definition)
        guard definitions[definition.id] == nil else {
            throw LauncherApplicationRegistryError.duplicateApplication(definition.id)
        }
        definitions[definition.id] = definition
        if let parentID = definition.parentID {
            childIDsByParent[parentID, default: []].insert(definition.id)
        } else {
            rootIDs.insert(definition.id)
        }
    }

    func register(_ application: any LauncherApplication) throws {
        let definition = application.definition
        guard definition.commandManifest != nil else {
            throw LauncherApplicationRegistryError.invalidDefinition(
                definition.id,
                reason: "Launchable applications require a command manifest."
            )
        }
        guard let documentation = definition.documentation else {
            throw LauncherApplicationRegistryError.invalidDefinition(
                definition.id,
                reason: "Launchable applications require documentation."
            )
        }
        try validate(documentation, for: definition.id)
        try register(definition)
        guard applications[definition.id] == nil else {
            removeDefinition(definition)
            let id = definition.id
            throw LauncherApplicationRegistryError.duplicateApplication(id)
        }
        applications[definition.id] = application
    }

    func application(for id: CommandID) -> (any LauncherApplication)? {
        applications[id]
    }

    func enabledApplication(for id: CommandID) -> (any LauncherApplication)? {
        guard isEffectivelyEnabled(id) else { return nil }
        return applications[id]
    }

    func definition(for id: CommandID) -> LauncherApplicationDefinition? {
        definitions[id]
    }

    func allDefinitions() -> [LauncherApplicationDefinition] {
        definitions.values.sorted(by: Self.sortDefinitions)
    }

    func rootDefinitions() -> [LauncherApplicationDefinition] {
        rootIDs
            .compactMap { definitions[$0] }
            .sorted(by: Self.sortDefinitions)
    }

    func children(of id: CommandID) -> [LauncherApplicationDefinition] {
        (childIDsByParent[id] ?? [])
            .compactMap { definitions[$0] }
            .sorted(by: Self.sortDefinitions)
    }

    func resolvedSettings(for id: CommandID) -> LauncherApplicationResolvedSettings? {
        guard let definition = definitions[id] else { return nil }
        let preferences = preferencesStore.preferences(for: id)
        var configuration = Dictionary(
            uniqueKeysWithValues: definition.configurationFields.map {
                ($0.variable, $0.defaultValue)
            }
        )
        for field in definition.configurationFields {
            guard let value = preferences.configuration[field.variable],
                  field.kind.accepts(value) else {
                continue
            }
            if field.kind == .selection,
               let selection = value.textValue,
               field.options.contains(where: { $0.id == selection }) == false {
                continue
            }
            configuration[field.variable] = value
        }
        return LauncherApplicationResolvedSettings(
            alias: Self.normalizedAlias(preferences.alias ?? ""),
            hotKey: preferences.hasHotKeyOverride ? preferences.hotKey : definition.defaultHotKey,
            isEnabled: preferences.isEnabled ?? definition.isEnabledByDefault,
            configuration: configuration
        )
    }

    func isEffectivelyEnabled(_ id: CommandID) -> Bool {
        var currentID: CommandID? = id
        var visited: Set<CommandID> = []
        while let candidate = currentID {
            guard visited.insert(candidate).inserted,
                  let definition = definitions[candidate],
                  isIndividuallyEnabled(definition) else {
                return false
            }
            currentID = definition.parentID
        }
        return true
    }

    func allManifests() -> [CommandManifest] {
        definitions.values
            .filter { applications[$0.id] != nil && isEffectivelyEnabled($0.id) }
            .compactMap { definition -> CommandManifest? in
                guard let manifest = definition.commandManifest else { return nil }
                let alias = resolvedSettings(for: definition.id)?.alias ?? ""
                guard alias.isEmpty == false,
                      manifest.keywords.contains(where: {
                          $0.caseInsensitiveCompare(alias) == .orderedSame
                      }) == false else {
                    return manifest
                }
                return CommandManifest(
                    id: manifest.id,
                    title: manifest.title,
                    subtitle: manifest.subtitle,
                    systemImage: manifest.systemImage,
                    category: manifest.category,
                    mode: manifest.mode,
                    keywords: [alias] + manifest.keywords,
                    badgeTitle: manifest.badgeTitle,
                    defaultActions: manifest.defaultActions
                )
            }
            .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }

    func savePreferences(_ preferences: LauncherApplicationPreferences, for id: CommandID) {
        guard definitions[id] != nil else { return }
        preferencesStore.save(preferences, for: id)
    }

    func preferences(for id: CommandID) -> LauncherApplicationPreferences {
        preferencesStore.preferences(for: id)
    }

    func resetPreferences(for id: CommandID) {
        preferencesStore.resetPreferences(for: id)
    }

    static func makeBuiltIn(
        clipboardHistoryStore: ClipboardHistoryStore = ClipboardHistoryStore(),
        fileSearchServices: FileSearchApplicationServices = .inMemory,
        calculatorSessionStore: CalculatorSessionStore = CalculatorSessionStore(),
        downloadsServices: DownloadsApplicationServices? = nil,
        timerStore: TimerStore = TimerStore(),
        productivityLibraryServices: ProductivityLibraryApplicationServices = .inMemory,
        offlineToolsServices: OfflineToolsServices? = nil,
        windowLayoutsServices: WindowLayoutsApplicationServices = WindowLayoutsApplicationServices(
            layoutService: InMemoryWindowLayoutService(),
            customStore: InMemoryCustomWindowLayoutStore()
        ),
        systemActivityService: any SystemActivityServicing = NativeSystemActivityService(),
        preferencesStore: any LauncherApplicationPreferencesStoring =
            InMemoryLauncherApplicationPreferencesStore()
    ) -> LauncherApplicationRegistry {
        let registry = LauncherApplicationRegistry(preferencesStore: preferencesStore)
        let resolvedOfflineToolsServices = offlineToolsServices ?? OfflineToolsServices(
            pasteboard: fileSearchServices.pasteboard
        )
        let resolvedDownloadsServices = downloadsServices ?? DownloadsApplicationServices(
            provider: NativeRecentDownloadsService(),
            urlOpener: fileSearchServices.urlOpener,
            fileRevealer: fileSearchServices.fileRevealer,
            pasteboard: fileSearchServices.pasteboard
        )
        do {
            try registry.register(BuiltInLauncherApplicationGroup.catalog)
            try registry.register(OpenSettingsApplication())
            try registry.register(
                ClipboardHistoryApplication(store: clipboardHistoryStore)
            )
            try registry.register(
                FileSearchApplication(services: fileSearchServices)
            )
            try registry.register(
                CalculatorHistoryApplication(
                    sessionStore: calculatorSessionStore,
                    pasteboard: fileSearchServices.pasteboard
                )
            )
            try registry.register(DownloadsApplication(services: resolvedDownloadsServices))
            try registry.register(TimersApplication(store: timerStore))
            try registry.register(
                ProductivityLibraryApplication(services: productivityLibraryServices)
            )
            try registry.register(SystemActivityApplication(service: systemActivityService))
            try registry.register(WindowLayoutsApplication(services: windowLayoutsServices))
            for tool in OfflineToolKind.allCases {
                try registry.register(
                    OfflineToolsApplication(tool: tool, services: resolvedOfflineToolsServices)
                )
            }
        } catch {
            preconditionFailure("Built-in launcher application definitions must be valid: \(error)")
        }
        return registry
    }

    private func validate(_ definition: LauncherApplicationDefinition) throws {
        if definition.kind == .group, definition.commandManifest != nil {
            throw LauncherApplicationRegistryError.invalidDefinition(
                definition.id,
                reason: "Groups cannot declare launch manifests."
            )
        }
        if let manifest = definition.commandManifest, manifest.id != definition.id {
            throw LauncherApplicationRegistryError.invalidDefinition(
                definition.id,
                reason: "Definition and command manifest identifiers must match."
            )
        }
        if let parentID = definition.parentID {
            guard parentID != definition.id else {
                throw LauncherApplicationRegistryError.invalidParent(definition.id)
            }
            guard definitions[parentID] != nil else {
                throw LauncherApplicationRegistryError.missingParent(
                    child: definition.id,
                    parent: parentID
                )
            }
        }
        guard Set(definition.configurationFields.map(\.id)).count
                == definition.configurationFields.count,
              Set(definition.configurationFields.map(\.variable)).count
                == definition.configurationFields.count else {
            throw LauncherApplicationRegistryError.invalidDefinition(
                definition.id,
                reason: "Configuration field identifiers and variables must be unique."
            )
        }
        for field in definition.configurationFields {
            guard field.variable.isEmpty == false,
                  field.kind.accepts(field.defaultValue) else {
                throw LauncherApplicationRegistryError.invalidDefinition(
                    definition.id,
                    reason: "Configuration defaults must match their field type."
                )
            }
            if field.kind == .selection {
                guard let defaultID = field.defaultValue.textValue,
                      Set(field.options.map(\.id)).count == field.options.count,
                      field.options.contains(where: { $0.id == defaultID }) else {
                    throw LauncherApplicationRegistryError.invalidDefinition(
                        definition.id,
                        reason: "Selection defaults must reference a declared option."
                    )
                }
            }
        }
    }

    private func validate(
        _ documentation: LauncherApplicationDocumentation,
        for id: CommandID
    ) throws {
        guard documentation.overview.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                == false,
              documentation.sections.isEmpty == false else {
            throw LauncherApplicationRegistryError.invalidDefinition(
                id,
                reason: "Documentation requires an overview and at least one section."
            )
        }
        let sectionIDs = documentation.sections.map(\.id)
        guard Set(sectionIDs).count == sectionIDs.count,
              documentation.sections.allSatisfy({
                  $0.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
                      && $0.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
                      && $0.blocks.isEmpty == false
              }) else {
            throw LauncherApplicationRegistryError.invalidDefinition(
                id,
                reason: "Documentation section identifiers must be unique and sections nonempty."
            )
        }
        let blocks = documentation.sections.flatMap(\.blocks)
        let blockIDs = blocks.map(\.id)
        guard Set(blockIDs).count == blockIDs.count,
              blocks.allSatisfy({
                  $0.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
                      && isValidDocumentationBlock($0)
              })
        else {
            throw LauncherApplicationRegistryError.invalidDefinition(
                id,
                reason: "Documentation blocks must have unique IDs and nonempty content."
            )
        }
    }

    private func isValidDocumentationBlock(_ block: DocumentationBlock) -> Bool {
        switch block.content {
        case .paragraph(let text):
            return text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
        case .bullets(let items), .steps(let items):
            return items.isEmpty == false && items.allSatisfy(Self.isNonempty)
        case .shortcuts(let shortcuts):
            return shortcuts.isEmpty == false
                && Set(shortcuts.map(\.id)).count == shortcuts.count
                && shortcuts.allSatisfy { shortcut in
                    Self.isNonempty(shortcut.id)
                        && Self.isNonempty(shortcut.title)
                        && shortcut.keys.isEmpty == false
                        && shortcut.keys.allSatisfy(Self.isNonempty)
                }
        case .examples(let examples):
            return examples.isEmpty == false
                && Set(examples.map(\.id)).count == examples.count
                && examples.allSatisfy { example in
                    Self.isNonempty(example.id) && Self.isNonempty(example.input)
                }
        case .callout(let callout):
            return Self.isNonempty(callout.title) && Self.isNonempty(callout.text)
        }
    }

    private static func isNonempty(_ value: String) -> Bool {
        value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
    }

    private func isIndividuallyEnabled(_ definition: LauncherApplicationDefinition) -> Bool {
        preferencesStore.preferences(for: definition.id).isEnabled
            ?? definition.isEnabledByDefault
    }

    private func removeDefinition(_ definition: LauncherApplicationDefinition) {
        definitions[definition.id] = nil
        if let parentID = definition.parentID {
            childIDsByParent[parentID]?.remove(definition.id)
        } else {
            rootIDs.remove(definition.id)
        }
    }

    private static func normalizedAlias(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func sortDefinitions(
        _ left: LauncherApplicationDefinition,
        _ right: LauncherApplicationDefinition
    ) -> Bool {
        if left.order != right.order { return left.order < right.order }
        return left.title.localizedCaseInsensitiveCompare(right.title) == .orderedAscending
    }
}

enum BuiltInLauncherApplicationGroup {
    static let catalogID = CommandID(rawValue: "commandly.catalog")

    static let catalog = LauncherApplicationDefinition.group(
        id: catalogID,
        title: "Commandly Applications",
        subtitle: "Built-in launcher applications and commands",
        systemImage: "square.grid.2x2",
        order: 0
    )
}

extension FileSearchApplicationServices {
    static var inMemory: FileSearchApplicationServices {
        FileSearchApplicationServices(
            searchService: InMemoryFileSearchService(),
            urlOpener: NoOpURLOpener(),
            fileRevealer: InMemoryFileRevealer(),
            fileActionService: InMemoryFileActionService(),
            finderInfoPresenter: InMemoryFinderInfoPresenter(),
            pasteboard: SystemPasteboard()
        )
    }
}
